#!/usr/bin/env bash
# Plugin hook for SubagentStart and SubagentStop. guard.sh slows a read-only
# seat down; this sees what it did. The working tree is recorded as a git tree
# when a reviewer or a verifier starts and compared when it stops.
#   - the first stop with a changed tree is refused: the seat puts the files back
#   - a second stop with a changed tree passes, and the run's event file gets a
#     `seat_wrote` event with the paths
# A file git ignores (a build, a log) is not in the tree. Anything unexpected exits 0.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(cat)

field() {
  jq -r "$1 // empty" <<< "$input" 2>/dev/null
}

agent=$(field .agent_type)
agent_id=$(field .agent_id)
case $agent in
  delivery-skills:reviewer|delivery-skills:verifier) ;;
  *) exit 0 ;;
esac
[ -n "$agent_id" ] || exit 0

cwd=$(field .cwd)
cd "${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}" 2>/dev/null || exit 0
cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || exit 0

source "$here/../skills/chunked-delivery/scripts/lib/run.sh" 2>/dev/null || exit 0
source "$here/../skills/delivery-pipeline/scripts/lib/changes.sh" 2>/dev/null || exit 0
unset DELIVERY_TREE DELIVERY_BASE

record="$(dirname "$run_dir")/seats/${agent_id//[^A-Za-z0-9_-]/_}.tree"

case $(field .hook_event_name) in
  SubagentStart)
    tree=$(worktree_tree 2>/dev/null) || exit 0
    mkdir -p "$(dirname "$record")" 2>/dev/null || exit 0
    printf '%s\n' "$tree" > "$record" 2>/dev/null
    ;;
  SubagentStop)
    [ -f "$record" ] || exit 0
    before=$(cat "$record")
    now=$(worktree_tree 2>/dev/null) || exit 0
    if [ "$before" = "$now" ]; then
      rm -f "$record"
      exit 0
    fi
    changed=$(git -c core.quotePath=false diff --name-only --no-renames "$before" "$now" 2>/dev/null | head -10 | tr '\n' ' ')
    if [ "$(field .stop_hook_active)" != true ]; then
      echo "$agent seat is read-only and the working tree changed while you ran: ${changed% }. Put each file back as it was, then end your report with one line that names them. If another agent changed them, say that instead." >&2
      exit 2
    fi
    rm -f "$record"
    bash "$here/../skills/chunked-delivery/scripts/event.sh" hook seat_wrote agent="$agent_id" agent_type="$agent" paths="${changed% }"
    ;;
esac
exit 0
