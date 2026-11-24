#!/usr/bin/env bash
# Plugin hook for PreToolUse (Bash, Read), SubagentStop and TaskCompleted.
# This list is the one place that says what it refuses:
#   - while a run is active (scripts/run.sh start), git is read-only: status,
#     diff, log, show, grep, blame and the like run, everything else does not
#   - while a run is active, nobody opens, changes or merges a PR or a release
#   - while a run is active, the controller never reads a chunk snapshot
#   - while a run is active, nobody installs or runs a package the registry
#     does not know, one published days ago, one reported as malware, or one
#     the registry could not be asked about (npm, pnpm, yarn, bun; pip, pipx
#     and uvx are not covered)
#   - while a run is active, an implementer whose dispatch asked for a Proof
#     or Reuse block ends with one
#   - while a run is active, a chunk task completes only after the run log
#     holds the human's accepted decision on that chunk
#   - a delivery-skills:reviewer or delivery-skills:verifier never writes
#     outside the temp and evidence directories, run or no run
# hooks/command.mjs reads the command; a command it cannot read is refused
# when it names git or a snapshot. This slows a mistake down. It is not a
# sandbox: hooks/tree-check.sh and the HEAD line of `run.sh status` are the
# checks that see what happened.
# Exit 2 refuses; stderr is the reason the model sees. Anything unexpected
# exits 0 so a hook bug never blocks work.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
scripts="$here/../skills/chunked-delivery/scripts"
input=$(cat)

field() {
  jq -r "$1 // empty" <<< "$input" 2>/dev/null
}

event=$(field .hook_event_name)
agent=$(field .agent_type)
agent_id=$(field .agent_id)
cwd=$(field .cwd)
[ -n "$cwd" ] || cwd=${CLAUDE_PROJECT_DIR:-$PWD}

source "$scripts/lib/run.sh" 2>/dev/null || exit 0
run_locate "$cwd"
root=$run_root

is_read_only_seat() {
  [ "$agent" = delivery-skills:reviewer ] || [ "$agent" = delivery-skills:verifier ]
}

# The controller is the session itself: a hook call with no agent id.
is_controller() {
  [ -z "$agent_id" ]
}

# ---------------------------------------------------------------- refusing
deny() {
  if run_active; then
    printf '%s' "$input" | EMIT_REFUSAL="$1" bash "$here/emit.sh" > /dev/null 2>&1 || true
  fi
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
  deny "the controller does not read a chunk snapshot; the reviewer reads it and reports, the controller works from reports and snapshot.sh stat"
}

# ------------------------------------------------------- reading a command
# `argv` holds the simple command under test: name first, wrappers and git's global options gone.
argv=()

has_arg() {
  local arg wanted
  for arg in ${argv[@]+"${argv[@]:1}"}; do
    for wanted in "$@"; do
      [ "$arg" = "$wanted" ] && return 0
    done
  done
  return 1
}

# The first argument that is not an option.
first_word() {
  local arg
  for arg in ${argv[@]+"${argv[@]:1}"}; do
    case $arg in
      -*) ;;
      *) printf '%s' "$arg"; return ;;
    esac
  done
}

is_snapshot() {
  [[ $(basename -- "${1#*=}") =~ ^chunk-[0-9]+[^/]*\.diff$ ]]
}

# ---------------------------------------------------------------- git
lists_only() { # WRITE_FLAGS LIST_FLAGS — true when `git branch` or `git tag` only lists
  local write=$1 list=$2 arg positional=0 listing=0
  for arg in ${argv[@]+"${argv[@]:2}"}; do
    case $arg in
      -*)
        [[ " $write " == *" ${arg%%=*} "* ]] && return 1
        [[ " $list " == *" ${arg%%=*} "* ]] && listing=1
        ;;
      *) positional=$((positional + 1)) ;;
    esac
  done
  [ "$positional" = 0 ] || [ "$listing" = 1 ]
}

git_is_read_only() {
  local sub=${argv[1]:-} second=${argv[2]:-}
  has_arg --help --dry-run && return 0
  case $sub in
    ''|--version|--help|version|help|status|diff|log|show|rev-parse|rev-list|ls-files|ls-tree|ls-remote) return 0 ;;
    cat-file|blame|annotate|grep|merge-base|describe|shortlog|whatchanged|diff-tree|diff-index|diff-files) return 0 ;;
    name-rev|for-each-ref|show-ref|show-branch|check-ignore|check-attr|var|count-objects|range-diff|cherry) return 0 ;;
    stash) [ "$second" = list ] || [ "$second" = show ] ;;
    reflog) [ "$second" != expire ] && [ "$second" != delete ] && [ "$second" != drop ] ;;
    worktree) [ "$second" = list ] ;;
    remote)
      case $second in
        ''|-v|--verbose|show|get-url) return 0 ;;
      esac
      return 1
      ;;
    config) has_arg --get --get-all --get-regexp --get-urlmatch --list -l || [[ $second =~ ^(get|list)$ ]] ;;
    apply) has_arg --check --stat --numstat --summary && ! has_arg --apply --index --cached -3 --3way ;;
    branch)
      lists_only "-d -D -m -M -c -C --delete --move --copy -f --force -u --set-upstream-to --unset-upstream --edit-description -t --track --no-track --create-reflog" \
        "-l --list -a -r --all --remotes --show-current -v -vv --verbose --contains --no-contains --merged --no-merged --points-at --format --sort --column"
      ;;
    tag)
      lists_only "-d --delete -a -s -u -f --force -m -F --annotate --sign -e --edit" \
        "-l --list -n --contains --no-contains --merged --no-merged --points-at --format --sort --column -v --verify"
      ;;
    *) return 1 ;;
  esac
}

git_hint() {
  case ${argv[1]:-} in
    add) echo "a snapshot needs no git add: use scripts/snapshot.sh" ;;
    reset|checkout|restore|clean|stash|switch|apply) echo "to undo a chunk use scripts/redo.sh N" ;;
    *) echo "only read-only git runs (status, diff, log, show, grep, blame, ls-files)" ;;
  esac
}

refuse_git_write() {
  [ "${argv[0]}" = git ] || return 0
  git_is_read_only || deny_during_run "git ${argv[1]} is not run during a run; $(git_hint)"
}

# ---------------------------------------------------------------- PRs
refuse_pr_write() {
  [ "${argv[0]}" = gh ] || return 0
  local arg words=() skip=0 method="" writes=0 target=0
  for arg in "${argv[@]:1}"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case $arg in
      -R|--repo) skip=1 ;;
      -*) ;;
      *) words+=("$arg") ;;
    esac
  done

  case "${words[0]:-} ${words[1]:-}" in
    pr\ create|pr\ merge|pr\ close|pr\ edit|pr\ ready|pr\ review|pr\ reopen)
      deny_during_run "gh pr ${words[1]} is not run during a run: no PR is opened, changed or merged"
      ;;
    release\ create|release\ edit|release\ delete|release\ upload)
      deny_during_run "gh release ${words[1]} is not run during a run"
      ;;
  esac
  [ "${words[0]:-}" = api ] || return 0

  skip=0
  for arg in "${argv[@]:1}"; do
    if [ "$skip" = 1 ]; then method=$arg; skip=0; continue; fi
    case $arg in
      -X|--method) skip=1 ;;
      -X*) method=${arg#-X} ;;
      --method=*) method=${arg#--method=} ;;
      -f|-F|--field|--raw-field|--input|-f*|-F*|--field=*|--raw-field=*|--input=*) writes=1 ;;
    esac
    [[ $arg =~ (^|/)(pulls|releases|merges|git/refs)(/|\?|$) ]] && target=1
  done
  method=$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')
  [ -z "$method" ] && [ "$writes" = 1 ] && method=POST
  [ "$target" = 1 ] && [ -n "$method" ] && [ "$method" != GET ] \
    && deny_during_run "gh api $method on a PR, a release or a ref is not run during a run"
}

# ---------------------------------------------------------------- snapshots
refuse_snapshot_print() {
  local arg
  case ${argv[0]} in
    wc|ls|stat|test|\[|du|rm|touch|git) return 0 ;;
  esac
  for arg in "${argv[@]:1}"; do
    is_snapshot "$arg" && deny_snapshot_read
  done
}

# ------------------------------------------------ packages from the registry
fetches=()
fetch_diff=0

unchecked_spec() {
  case $1 in
    file:*|./*|../*|/*|link:*|workspace:*) return 1 ;;
    git+*|git:*|git@*|github:*|gitlab:*|bitbucket:*|http:*|https:*|*.tgz|*.tar.gz) return 0 ;;
    @*) return 1 ;;
    */*) return 0 ;;
  esac
  return 1
}

fetch() {
  local spec=${1#[\"\']}
  spec=${spec%[\"\']}
  unchecked_spec "$spec" \
    && deny_during_run "$spec is a git or tarball spec, which the registry cannot vouch for, so an agent does not fetch it. Report it and stop; the human installs it"
  fetches+=("$spec")
}

# `npm create vite` fetches create-vite; `@scope/app` fetches @scope/create-app.
create_package() {
  local spec=$1 version=""
  case $spec in
    @*/*)
      [[ ${spec#@} == *@* ]] && version="@${spec##*@}" && spec=${spec%@*}
      printf '%s/create-%s%s' "${spec%%/*}" "${spec#*/}" "$version"
      ;;
    @*) printf '%s/create' "$spec" ;;
    *) printf 'create-%s' "$spec" ;;
  esac
}

# Records what the command in `argv` would fetch from the registry.
collect_fetches() {
  local tool=${argv[0]} index=1 word subcommand="" mode="" count=${#argv[@]}

  case $tool in
    npx|bunx|pnpx) mode=exec ;;
    npm|pnpm|yarn|bun)
      while [ -z "$mode" ]; do
        subcommand=""
        while [ $index -lt "$count" ]; do
          word=${argv[$index]}
          index=$((index + 1))
          case $word in
            --filter|-F|--prefix|-C|--dir|--cwd|--workspace) index=$((index + 1)) ;;
            -w) [ "$tool" = npm ] && index=$((index + 1)) ;;
            -*) ;;
            *) subcommand=$word; break ;;
          esac
        done
        case "$tool:$subcommand" in
          yarn:workspace) index=$((index + 1)) ;;
          npm:install|npm:i|npm:in|npm:ins|npm:inst|npm:insta|npm:instal|npm:isnt|npm:isnta|npm:isntal|npm:isntall|npm:add) mode=install ;;
          pnpm:add|pnpm:install|pnpm:i|yarn:add|yarn:install|yarn:|bun:add|bun:install|bun:i) mode=install ;;
          npm:update|npm:up|npm:upgrade|npm:udpate|pnpm:update|pnpm:up|pnpm:upgrade|yarn:up|yarn:upgrade|bun:update) mode=update ;;
          npm:exec|npm:x|pnpm:dlx|yarn:dlx|bun:x) mode=exec ;;
          npm:create|npm:init|npm:innit|pnpm:create|yarn:create|bun:create) mode=create ;;
          *) return 0 ;;
        esac
      done
      ;;
    *) return 0 ;;
  esac

  local named=0 package=""
  while [ $index -lt "$count" ]; do
    word=${argv[$index]}
    index=$((index + 1))
    case $word in
      --no-install)
        [ "$mode" = exec ] && return 0
        ;;
      -p|--package)
        if [ "$mode" = exec ]; then
          package=${argv[$index]:-}
          index=$((index + 1))
        fi
        ;;
      --package=*) [ "$mode" = exec ] && package=${word#--package=} ;;
      --filter|-F|--registry|--prefix|-C|--dir|--cwd|--workspace|--tag|--otp) index=$((index + 1)) ;;
      -w) [ "$tool" = npm ] && index=$((index + 1)) ;;
      --) [ "$mode" = install ] || break ;;
      -*) ;;
      *)
        named=1
        case $mode in
          exec) [ -n "$package" ] || package=$word; break ;;
          create) fetch "$(create_package "$word")"; return 0 ;;
          *) fetch "$word" ;;
        esac
        ;;
    esac
  done

  if [ "$mode" = install ] && [ "$named" = 0 ]; then
    fetch_diff=1
  fi
  [ "$mode" = exec ] && [ -n "$package" ] || return 0

  # exec: a binary the project already has installed is not fetched.
  local binary=${package##*/}
  binary=${binary%%@*}
  [ -e "$cwd/node_modules/.bin/$binary" ] || [ -e "$root/node_modules/.bin/$binary" ] || fetch "$package"
}

vet() {
  local verdict status blocked
  verdict=$(cd "$cwd" 2>/dev/null && bash "$here/../skills/delivery-pipeline/scripts/dep-vet.sh" "$@" 2>/dev/null)
  status=$?
  if [ "$status" = 1 ]; then
    blocked=$(printf '%s\n' "$verdict" | sed -n 's/^BLOCK *//p' | tr '\n' ';' | sed 's/;$//; s/;/; /g')
    deny_during_run "this package is not fetched by an agent — $blocked. Report it and stop; the human installs it, or names it in DEP_VET_ALLOW"
  fi
  if printf '%s\n' "$verdict" | grep -q '^SKIP'; then
    deny_during_run "the registry did not answer, so this package could not be checked and an agent does not fetch it. Try again, or the human installs it; DEP_VET=off turns the check off"
  fi
}

refuse_untrusted_fetches() {
  [ ${#fetches[@]} -eq 0 ] || vet "${fetches[@]}"
  [ "$fetch_diff" = 0 ] || vet --diff
}

# ---------------------------------------------------------------- read-only seats
# A seat keeps a log or a screenshot: under the temp directory or the evidence directory, never in the checkout.
is_scratch_place() {
  local path=$1 place parent
  case $path in
    /dev/null|/dev/stdout|/dev/stderr|/dev/tty|/dev/fd/*) return 0 ;;
    '$TMPDIR'/*|'${TMPDIR}'/*|'${TMPDIR:-/tmp}'/*) return 0 ;;
    /*) ;;
    *) path="$cwd/$path" ;;
  esac
  case "/$path/" in
    */../*) return 1 ;;
  esac
  # /var is a link to /private/var on macOS; git names the checkout by the second.
  parent=$path
  while [ ! -d "$parent" ] && [ "$parent" != / ]; do parent=$(dirname "$parent"); done
  path="$(cd "$parent" 2>/dev/null && pwd -P)${path#"$parent"}"
  [[ $path/ == "$root"/* ]] && return 1
  for place in /tmp /private/tmp /var/tmp /var/folders /private/var/folders "${TMPDIR:-}" "${DELIVERY_EVIDENCE_DIR:-}"; do
    [ -n "$place" ] && [[ $path == "${place%/}"/* ]] && return 0
  done
  return 1
}

refuse_seat_redirect() { # OP TARGET
  case $1 in
    '>'|'>>'|'&>'|'>|'|'>&'|'<>') is_scratch_place "$2" || deny_read_only "no redirect to a file outside the temp and evidence directories" ;;
  esac
}

refuse_seat_write() {
  local tool=${argv[0]} arg targets=() sub

  case $tool in
    git) git_is_read_only || deny_read_only "git ${argv[1]} changes the tree" ;;
    tee|rm|mkdir|touch|rmdir|truncate|chmod|chown|mv)
      for arg in "${argv[@]:1}"; do
        [[ $arg == -* ]] || targets+=("$arg")
      done
      ;;
    cp|ln|install|rsync) targets=("${argv[${#argv[@]}-1]}") ;;
    patch|dd) deny_read_only "$tool writes" ;;
    sed|perl)
      for arg in "${argv[@]:1}"; do
        [[ $arg =~ ^-[A-Za-z]*i|^--in-place ]] && deny_read_only "$tool -i writes"
      done
      ;;
    npm|pnpm|yarn|bun|pip|pip3|pipx|uv)
      sub=$(first_word)
      [[ $sub =~ ^(install|i|add|ci|uninstall|remove|rm|update|up|upgrade)$ ]] && deny_read_only "no installs"
      ;;
  esac
  case $tool in
    npm|pnpm|yarn|bun|npx|bunx|pnpx|prettier|eslint|biome)
      has_arg --write --fix && deny_read_only "no --write or --fix"
      ;;
  esac
  for arg in ${targets[@]+"${targets[@]}"}; do
    is_scratch_place "$arg" || deny_read_only "$tool writes outside the temp and evidence directories"
  done
}

# ---------------------------------------------------------------- the hooks
check_bash() {
  local command parsed line fields kind
  command=$(field .tool_input.command)
  [ -n "$command" ] || exit 0

  parsed=$(printf '%s' "$command" | node "$here/command.mjs" --lines 2>/dev/null) || parsed=X
  if [ "$parsed" = X ]; then
    is_read_only_seat && deny_read_only "this command does not parse, so nobody can tell what it writes; run it as a plain command"
    if run_active && [[ $command =~ (^|[^[:alnum:]_])git([^[:alnum:]_]|$)|chunk-[0-9]+[^[:space:]/]*\.diff ]]; then
      deny_during_run "this command does not parse and names git or a snapshot; run it as a plain command"
    fi
    exit 0
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS=$'\037' read -r -a fields <<< "$line"
    kind=${fields[0]}
    if [ "$kind" = R ]; then
      is_read_only_seat && refuse_seat_redirect "${fields[1]:-}" "${fields[2]:-}"
      if run_active && is_controller && [[ ${fields[1]:-} == '<'* ]] && is_snapshot "${fields[2]:-}"; then
        deny_snapshot_read
      fi
      continue
    fi
    argv=("${fields[@]:1}")
    [ ${#argv[@]} -gt 0 ] || continue

    if run_active; then
      if [ "${argv[0]}" = '?' ] && [[ $command =~ (^|[^[:alnum:]_])git([^[:alnum:]_]|$) ]]; then
        deny_during_run "the name of this command is built when it runs and the text names git; run git as a plain command"
      fi
      refuse_git_write
      refuse_pr_write
      is_read_only_seat || collect_fetches
      is_controller && refuse_snapshot_print
    fi
    is_read_only_seat && refuse_seat_write
  done <<< "$parsed"

  run_active && refuse_untrusted_fetches
  exit 0
}

check_read() {
  run_active || exit 0
  is_controller || exit 0
  is_snapshot "$(field .tool_input.file_path)" && deny_snapshot_read
  exit 0
}

# An implementer whose dispatch asked for a ## Proof or ## Reuse block ends with one.
check_stop() {
  run_active || exit 0
  is_read_only_seat && exit 0
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

  local chunk=${BASH_REMATCH[1]} decision
  decision=$(node "$scripts/lifecycle.mjs" builds "$(run_events_file)" 2>/dev/null \
    | jq -rs --argjson chunk "$chunk" 'map(select(.chunk == $chunk)) | last | .decision // empty' 2>/dev/null)
  case $decision in
    accepted|edited) exit 0 ;;
  esac

  deny "Chunk $chunk has no accepted decision in the run log of this run. Complete the task after the human decides on the chunk and you add the run-log line."
}

case "$event" in
  TaskCompleted) check_task_done ;;
  PreToolUse)
    case "$(field .tool_name)" in
      Bash) check_bash ;;
      Read) check_read ;;
    esac
    ;;
  SubagentStop) check_stop ;;
esac
exit 0
