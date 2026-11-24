#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../scripts/test-lib.sh"
check="$here/tree-check.sh"
scripts="$here/../skills/chunked-delivery/scripts"

new_repo project
echo one > a.txt && echo "*.log" > .gitignore && commit_all
echo work > b.txt

seat() { # EVENT AGENT_TYPE [ID] [STOP_HOOK_ACTIVE]
  jq -cn --arg cwd "$PWD" --arg event "$1" --arg agent "$2" --arg id "${3:-a1}" --argjson active "${4:-false}" \
    '{session_id: "s1", cwd: $cwd, hook_event_name: $event, agent_id: $id, agent_type: $agent, stop_hook_active: $active}' \
    | bash "$check"
}
records() { ls "$tmp/seats" 2>/dev/null | wc -l | tr -d ' '; }
export DELIVERY_RUN_DIR="$tmp/runs"

echo "# a seat that leaves the tree alone"
has "start is silent"                     0 "" seat SubagentStart delivery-skills:reviewer
eq  "the tree is recorded"                "$(records)" 1
echo noise > build.log
has "stop passes, a file git ignores is no change" 0 "" seat SubagentStop delivery-skills:reviewer
eq  "the record is gone"                  "$(records)" 0
eq  "nothing is staged"                   "$(git diff --cached --name-only)" ""

echo "# a seat that writes"
seat SubagentStart delivery-skills:verifier v1
echo two > a.txt; echo new > "c d.txt"
has "the first stop is refused"           2 "delivery-skills:verifier seat is read-only and the working tree changed while you ran: a.txt c d.txt\." seat SubagentStop delivery-skills:verifier v1
echo one > a.txt; rm "c d.txt"
has "after the files are back, it passes" 0 "" seat SubagentStop delivery-skills:verifier v1 true
eq  "and the record is gone"              "$(records)" 0

echo "# a seat that does not put it back, in a run"
bash "$scripts/run.sh" start > /dev/null
seat SubagentStart delivery-skills:reviewer r2
echo three > a.txt
has "the first stop is refused"           2 "a.txt" seat SubagentStop delivery-skills:reviewer r2
has "the second stop passes"              0 "" seat SubagentStop delivery-skills:reviewer r2 true
event=$(tail -1 "$DELIVERY_EVENTS_DIR"/*.jsonl)
eq  "and the run has the event"           "$(jq -r '.ev + " " + .agent + " " + .agent_type + " " + .paths' <<< "$event")" "seat_wrote r2 delivery-skills:reviewer a.txt"
bash "$scripts/run.sh" stop > /dev/null

echo "# not a read-only seat"
has "an implementer is not recorded"      0 "" seat SubagentStart general-purpose i1
eq  "no record"                           "$(records)" 0
has "nor is a reviewer of another plugin" 0 "" seat SubagentStart other:reviewer o1
eq  "no record"                           "$(records)" 0
has "a stop with no start passes"         0 "" seat SubagentStop delivery-skills:reviewer never
has "input that is not JSON passes"       0 "" bash -c "echo nope | bash '$check'"

finish
