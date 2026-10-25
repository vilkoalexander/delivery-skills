#!/usr/bin/env bash
# Plugin hook for PreToolUse (Bash, Read) and SubagentStop. Turns four rules of
# the delivery run from prose into refusals:
#   - while a run is active (scripts/run.sh start), nobody runs a git write
#   - a reviewer or verifier agent never writes, run or no run
#   - while a run is active, the controller never reads a chunk snapshot
#   - an implementer whose dispatch asked for a Proof block ends with one
# Exit 2 refuses; stderr is the reason the model sees. Anything unexpected
# exits 0 so a hook bug never blocks work.
set -uo pipefail
input=$(cat)
j() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }

event=$(j .hook_event_name)
agent=$(j .agent_type)
agent_id=$(j .agent_id)
cwd=$(j .cwd)

run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
root=$(git -C "$proj" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$proj")
hash() { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12; }
marker="$run_dir/$(printf '%s' "$root" | hash)"

run_active() { [ -f "$marker" ]; }
is_reviewer() { case "$agent" in reviewer|*:reviewer|verifier|*:verifier) return 0 ;; esac; return 1; }
deny() { printf '%s\n' "$1" >&2; exit 2; }
run_reason() {
  printf 'delivery run active on %s: %s. The human commits after handoff; to end the run: bash <chunked-delivery>/scripts/run.sh stop' "$root" "$1"
}

# one shell segment per line: split on && || ; | and newlines, drop env prefixes
segments() {
  printf '%s\n' "$1" | sed -E 's/\|\||&&|;|\|/\n/g' \
    | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//'
}
git_sub() { # prints the git subcommand and its args, or nothing
  printf '%s' "$1" | sed -nE 's/^[[:space:]]*git[[:space:]]+(((-C|-c)[[:space:]]+[^[:space:]]+|--no-pager)[[:space:]]+)*(.*)$/\4/p'
}
has_flag() { printf '%s' "$1" | grep -qE -- "(^|[[:space:]])($2)([[:space:]]|$)"; }

check_bash() {
  local cmd seg sub first
  cmd=$(j .tool_input.command)
  [ -n "$cmd" ] || exit 0
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    first=$(printf '%s' "$seg" | awk '{print $1}')
    sub=$(git_sub "$seg")

    if run_active; then
      case "$sub" in
        commit*|push*|merge*|rebase*|cherry-pick*|stash*|clean*|restore*)
          deny "$(run_reason "git ${sub%% *} is not run during a run")" ;;
        add*)
          has_flag "$sub" '-N|--intent-to-add' || deny "$(run_reason "git add is not run during a run; only git add -N, which records paths for the snapshot")" ;;
        reset*)
          has_flag "$sub" '--hard' && deny "$(run_reason "git reset --hard discards the uncommitted work; redo uses git apply -R on the chunk snapshot")" ;;
        checkout*)
          has_flag "$sub" '--' && deny "$(run_reason "git checkout -- discards the uncommitted work; redo uses git apply -R on the chunk snapshot")" ;;
      esac
      case "$seg" in
        *gh\ pr\ create*|*gh\ pr\ merge*) deny "$(run_reason "no PR is opened or merged during a run")" ;;
      esac
      if [ -z "$agent_id" ]; then
        case "$first" in
          cat|head|tail|less|more|sed|awk|bat|nl)
            printf '%s' "$seg" | grep -qE 'chunk-[0-9]+[^[:space:]]*\.diff' \
              && deny "the controller does not read a chunk snapshot; the reviewer reads it and reports, the controller works from reports and git diff --stat" ;;
        esac
      fi
    fi

    if is_reviewer; then
      local stripped
      stripped=$(printf '%s' "$seg" | sed -E 's/[0-9]*>&[0-9]+//g; s/[0-9]*>[[:space:]]*\/dev\/null//g')
      case "$stripped" in *\>*) deny "$agent seat is read-only: no redirect to a file. Report findings in your reply." ;; esac
      case "$first" in
        tee|rm|mv|cp|mkdir|touch|chmod|chown|ln|truncate|rmdir|patch)
          deny "$agent seat is read-only: $first writes. Report findings in your reply." ;;
        sed)
          has_flag "$seg" '-[A-Za-z]*i[A-Za-z]*|-i[^[:space:]]*|--in-place' && deny "$agent seat is read-only: sed -i writes. Report findings in your reply." ;;
        npm|pnpm|yarn|bun|pip|pip3)
          printf '%s' "$seg" | grep -qE "^[[:space:]]*$first[[:space:]]+(install|i|add|ci|uninstall|remove|rm|update|up)([[:space:]]|$)" \
            && deny "$agent seat is read-only: no installs. Report findings in your reply." ;;
        npx|prettier|eslint)
          has_flag "$seg" '--write|--fix' && deny "$agent seat is read-only: no --write or --fix. Report findings in your reply." ;;
      esac
      case "$sub" in
        apply*|checkout*|restore*|stash*|reset*|clean*|commit*|add*|push*|merge*|rebase*|cherry-pick*|am*)
          deny "$agent seat is read-only: git ${sub%% *} changes the tree. Report findings in your reply." ;;
      esac
    fi
  done <<<"$(segments "$cmd")"
  exit 0
}

check_read() {
  local path base
  run_active || exit 0
  [ -z "$agent_id" ] || exit 0
  path=$(j .tool_input.file_path)
  base=$(basename -- "$path")
  case "$base" in
    chunk-[0-9]*.diff) deny "the controller does not read a chunk snapshot; the reviewer reads it and reports, the controller works from reports and git diff --stat" ;;
  esac
  exit 0
}

check_stop() {
  local t prompt last missing block
  [ "$(j .stop_hook_active)" = true ] && exit 0
  t=$(j .agent_transcript_path); t="${t/#\~/$HOME}"
  [ -n "$t" ] && [ -f "$t" ] || exit 0
  prompt=$(jq -rn 'first(inputs | select(.type=="user") | .message.content
      | if type=="string" then . else map(.text? // empty) | join("\n") end)' "$t" 2>/dev/null | head -c 60000)
  [ -n "$prompt" ] || exit 0
  last=$(j .last_assistant_message)
  missing=""
  for block in "## Proof" "## Reuse"; do
    case "$prompt" in *"$block"*) case "$last" in *"$block"*) ;; *) missing="$missing $block" ;; esac ;; esac
  done
  [ -z "$missing" ] && exit 0
  deny "Your report is missing:$missing. The dispatch asked for it. Append the block(s) now — ## Proof with ran / shows / exercised / not verified, ## Reuse with reused / searched / new shared / new dependency — and stop. Do not re-implement anything."
}

case "$event" in
  PreToolUse)
    case "$(j .tool_name)" in
      Bash) check_bash ;;
      Read) check_read ;;
    esac ;;
  SubagentStop) check_stop ;;
esac
exit 0
