#!/usr/bin/env bash
# Plugin hook for PreToolUse (Bash, Read), SubagentStop and TaskCompleted. Turns six rules of
# the delivery run from prose into refusals:
#   - while a run is active (scripts/run.sh start), nobody runs a git write
#   - a reviewer or verifier agent never writes, run or no run
#   - while a run is active, the controller never reads a chunk snapshot
#   - an implementer whose dispatch asked for a Proof block ends with one
#   - while a run is active, nobody installs or runs a package the registry
#     does not know, one published days ago, or one reported as malware
#   - while a run is active, a chunk task completes only after the run log
#     holds the human's decision on that chunk
# Exit 2 refuses; stderr is the reason the model sees. Anything unexpected
# exits 0 so a hook bug never blocks work.
set -uo pipefail
here=$(dirname "$0")
input=$(cat)

field() {
  jq -r "$1 // empty" <<< "$input" 2>/dev/null
}

event=$(field .hook_event_name)
agent=$(field .agent_type)
agent_id=$(field .agent_id)
cwd=$(field .cwd)

run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
project="${CLAUDE_PROJECT_DIR:-$cwd}"
root=$(git -C "$project" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$project")

short_hash() {
  if command -v shasum > /dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12
}
marker="$run_dir/$(printf '%s' "$root" | short_hash)"

run_active() {
  [ -f "$marker" ]
}

is_reviewer() {
  case "$agent" in
    reviewer|*:reviewer|verifier|*:verifier) return 0 ;;
  esac
  return 1
}

# The controller is the session itself: a hook call with no agent id.
is_controller() {
  [ -z "$agent_id" ]
}

# ---------------------------------------------------------------- refusing
record_refusal() {
  run_active || return 0
  printf '%s' "$input" | EMIT_REFUSAL="$1" bash "$here/emit.sh" > /dev/null 2>&1 || true
}

deny() {
  record_refusal "$1"
  printf '%s\n' "$1" >&2
  exit 2
}

deny_during_run() {
  deny "delivery run active on $root: $1. The human commits after handoff; to end the run: bash <chunked-delivery>/scripts/run.sh stop"
}

deny_read_only() {
  deny "$agent seat is read-only: $1. Report findings in your reply."
}

deny_snapshot_read() {
  deny "the controller does not read a chunk snapshot; the reviewer reads it and reports, the controller works from reports and git diff --stat"
}

# ------------------------------------------------------- reading a command
# one shell segment per line: split on && || ; | and newlines, drop env prefixes
segments() {
  printf '%s\n' "$1" \
    | sed -E 's/\|\||&&|;|\|/\n/g' \
    | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//'
}

# prints the git subcommand and its args, or nothing
git_subcommand() {
  printf '%s' "$1" \
    | sed -nE 's/^[[:space:]]*git[[:space:]]+(((-C|-c)[[:space:]]+[^[:space:]]+|--no-pager)[[:space:]]+)*(.*)$/\4/p'
}

# has_flag TEXT FLAGS — FLAGS is an alternation such as '--write|--fix'
has_flag() {
  printf '%s' "$1" | grep -qE -- "(^|[[:space:]])($2)([[:space:]]|$)"
}

matches() {
  printf '%s' "$1" | grep -qE -- "$2"
}

# ------------------------------------------------ packages from the registry
# Prints what an install or run-from-registry command would fetch: one spec per
# line, or "--diff" for a bare install, which takes its list from package.json.
fetch_specs() {
  local tool=$1 segment=$2
  local words=() index=1 word subcommand="" mode=""
  read -r -a words <<< "$segment"

  case "$tool" in
    npx|bunx|pnpx)
      mode=exec
      ;;
    npm|pnpm|yarn|bun)
      # The subcommand is the first word that is neither an option nor an option's value.
      while [ $index -lt ${#words[@]} ]; do
        word=${words[$index]}
        index=$((index + 1))
        case "$word" in
          --filter|-F|--prefix|-C|--dir|--cwd) index=$((index + 1)) ;;
          -*) ;;
          *)
            subcommand=$word
            break
            ;;
        esac
      done
      case "$tool:$subcommand" in
        npm:install|npm:i|npm:add|pnpm:add|pnpm:install|pnpm:i|yarn:add|bun:add|bun:install|bun:i) mode=install ;;
        yarn:|yarn:install) mode=install ;;
        pnpm:dlx|yarn:dlx|bun:x) mode=exec ;;
        *) return 0 ;;
      esac
      ;;
    *)
      return 0
      ;;
  esac

  local named_a_package=0 package=""
  while [ $index -lt ${#words[@]} ]; do
    word=${words[$index]}
    index=$((index + 1))
    case "$word" in
      --no-install)
        [ "$mode" = exec ] && return 0
        ;;
      -p|--package)
        if [ "$mode" = exec ]; then
          package=${words[$index]:-}
          index=$((index + 1))
        fi
        ;;
      --package=*)
        [ "$mode" = exec ] && package=${word#--package=}
        ;;
      --filter|-F|--registry|--prefix|-C|--dir|--cwd|--workspace|--tag|--otp)
        index=$((index + 1))
        ;;
      -w)
        [ "$tool" = npm ] && index=$((index + 1))
        ;;
      --)
        [ "$mode" = exec ] && break
        ;;
      -*) ;;
      *)
        named_a_package=1
        if [ "$mode" = exec ]; then
          [ -n "$package" ] || package=$word
          break
        fi
        printf '%s\n' "$word"
        ;;
    esac
  done

  if [ "$mode" = install ]; then
    [ "$named_a_package" = 0 ] && echo "--diff"
    return 0
  fi

  # exec: a binary the project already has installed is not fetched.
  [ -n "$package" ] || return 0
  package=${package#[\"\']}
  package=${package%[\"\']}
  local binary=${package##*/}
  binary=${binary%%@*}
  [ -e "$cwd/node_modules/.bin/$binary" ] || [ -e "$root/node_modules/.bin/$binary" ] || printf '%s\n' "$package"
}

refuse_untrusted_fetch() {
  local specs=() spec verdict blocked
  while IFS= read -r spec; do
    [ -n "$spec" ] && specs+=("$spec")
  done < <(fetch_specs "$1" "$2")
  [ ${#specs[@]} -gt 0 ] || return 0

  verdict=$(cd "${cwd:-$root}" 2>/dev/null && bash "$here/../skills/delivery-pipeline/scripts/dep-vet.sh" "${specs[@]}" 2>/dev/null)
  [ $? = 1 ] || return 0

  blocked=$(printf '%s' "$verdict" | grep '^BLOCK ' | sed 's/^BLOCK //' | tr '\n' ';' | sed 's/;$//; s/;/; /g')
  deny_during_run "this package is not fetched by an agent — $blocked. Report it and stop; the human installs it, or names it in DEP_VET_ALLOW"
}

# ---------------------------------------------------------------- the rules
# While a run is active, nobody runs a git write or opens a PR.
refuse_git_write() {
  local git=$1 segment=$2
  case "$git" in
    stash\ list*|stash\ show*) ;;
    commit*|push*|merge*|rebase*|cherry-pick*|stash*|clean*|restore*)
      deny_during_run "git ${git%% *} is not run during a run"
      ;;
    add*)
      has_flag "$git" '-N|--intent-to-add' \
        || deny_during_run "git add is not run during a run; only git add -N, which records paths for the snapshot"
      ;;
    reset*)
      has_flag "$git" '--hard' \
        && deny_during_run "git reset --hard discards the uncommitted work; redo uses scripts/redo.sh"
      ;;
    checkout*)
      has_flag "$git" '--' \
        && deny_during_run "git checkout -- discards the uncommitted work; redo uses scripts/redo.sh"
      ;;
  esac
  case "$segment" in
    *gh\ pr\ create*|*gh\ pr\ merge*) deny_during_run "no PR is opened or merged during a run" ;;
  esac
}

# While a run is active, the controller never prints a chunk snapshot.
refuse_snapshot_print() {
  local tool=$1 segment=$2
  case "$tool" in
    cat|head|tail|less|more|sed|awk|bat|nl)
      matches "$segment" 'chunk-[0-9]+[^[:space:]]*\.diff' && deny_snapshot_read
      ;;
  esac
}

# A reviewer or verifier never writes, run or no run.
refuse_reviewer_write() {
  local tool=$1 git=$2 segment=$3 without_safe_redirects

  # "=>" is an arrow function in a node -e probe far more often than a redirect.
  without_safe_redirects=$(printf '%s' "$segment" | sed -E 's/[0-9]*>&[0-9]+//g; s/[0-9]*>[[:space:]]*\/dev\/null//g; s/=>//g')
  case "$without_safe_redirects" in
    *\>*) deny_read_only "no redirect to a file" ;;
  esac

  case "$tool" in
    tee|rm|mv|cp|mkdir|touch|chmod|chown|ln|truncate|rmdir|patch)
      deny_read_only "$tool writes"
      ;;
    sed)
      has_flag "$segment" '-[A-Za-z]*i[A-Za-z]*|-i[^[:space:]]*|--in-place' && deny_read_only "sed -i writes"
      ;;
    npm|pnpm|yarn|bun|pip|pip3)
      matches "$segment" "^[[:space:]]*${tool}[[:space:]]+(install|i|add|ci|uninstall|remove|rm|update|up)([[:space:]]|$)" \
        && deny_read_only "no installs"
      ;;
    npx|prettier|eslint)
      has_flag "$segment" '--write|--fix' && deny_read_only "no --write or --fix"
      ;;
  esac

  case "$git" in
    stash\ list*|stash\ show*) ;;
    apply*|checkout*|restore*|stash*|reset*|clean*|commit*|add*|push*|merge*|rebase*|cherry-pick*|am*)
      deny_read_only "git ${git%% *} changes the tree"
      ;;
  esac
}

# ---------------------------------------------------------------- the hooks
check_bash() {
  local command segment tool git
  command=$(field .tool_input.command)
  [ -n "$command" ] || exit 0

  while IFS= read -r segment; do
    [ -n "$segment" ] || continue
    tool=$(printf '%s' "$segment" | awk '{print $1}')
    git=$(git_subcommand "$segment")

    if run_active; then
      refuse_git_write "$git" "$segment"
      is_reviewer || refuse_untrusted_fetch "$tool" "$segment"
      is_controller && refuse_snapshot_print "$tool" "$segment"
    fi
    is_reviewer && refuse_reviewer_write "$tool" "$git" "$segment"
  done <<< "$(segments "$command")"
  exit 0
}

check_read() {
  run_active || exit 0
  is_controller || exit 0
  case "$(basename -- "$(field .tool_input.file_path)")" in
    chunk-[0-9]*.diff) deny_snapshot_read ;;
  esac
  exit 0
}

# An implementer whose dispatch asked for a ## Proof or ## Reuse block ends with one.
check_stop() {
  [ "$(field .stop_hook_active)" = true ] && exit 0

  local transcript dispatch report block missing=""
  transcript=$(field .agent_transcript_path)
  transcript="${transcript/#\~/$HOME}"
  [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

  dispatch=$(jq -rn '
    first(inputs | select(.type == "user") | .message.content
      | if type == "string" then . else map(.text? // empty) | join("\n") end)
  ' "$transcript" 2>/dev/null | head -c 60000)
  [ -n "$dispatch" ] || exit 0

  # A report can arrive as a hand-back call. The hook input then has no last message.
  report=$(field .last_assistant_message)$'\n'$(jq -rnR '
    [inputs | fromjson? | select(.type == "assistant") | .message.content[]?
     | select(.type == "tool_use" and .name == "SubagentHandback") | .input.message // empty]
    | last // empty
  ' "$transcript" 2>/dev/null)
  for block in "## Proof" "## Reuse"; do
    [[ $dispatch == *"$block"* ]] || continue
    [[ $report == *"$block"* ]] || missing="$missing $block"
  done
  [ -z "$missing" ] && exit 0

  deny "Your report is missing:$missing. The dispatch asked for it. Append the block(s) now — ## Proof with ran / shows / exercised / safe because (high risk) / not verified, ## Reuse with reused / searched / new shared / new dependency — and stop. Do not re-implement anything."
}

# A chunk task is "Chunk N/M — name [risk]". It completes after the human decided on the chunk.
check_task_done() {
  run_active || exit 0
  [[ $(field .task_subject) =~ ^Chunk\ ([0-9]+)/ ]] || exit 0

  local chunk=${BASH_REMATCH[1]} log started decision
  log="${DELIVERY_LOG:-$HOME/.claude/delivery-skills/log.jsonl}"
  started=$(jq -r '.started // empty' "$marker" 2>/dev/null)
  decision=$(jq -rs --arg project "$root" --arg started "$started" --argjson chunk "$chunk" '
    map(select(.project == $project and .chunk == $chunk and .ts >= $started)) | last | .decision // empty
  ' "$log" 2>/dev/null)
  case $decision in
    accepted|edited) exit 0 ;;
  esac

  deny "Chunk $chunk has no accepted decision in the run log of this run. Complete the task after the human decides on the chunk and you add the run-log line."
}

case "$event" in
  TaskCompleted)
    check_task_done
    ;;
  PreToolUse)
    case "$(field .tool_name)" in
      Bash) check_bash ;;
      Read) check_read ;;
    esac
    ;;
  SubagentStop)
    check_stop
    ;;
esac
exit 0
