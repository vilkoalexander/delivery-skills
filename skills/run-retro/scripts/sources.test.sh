#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
script="$here/sources.sh"
export DELIVERY_LOG="$tmp/log.jsonl"

echo "# with nothing recorded"
has "no event files"            1 "no event files in"              bash "$script"
has "unknown run"               1 "no event file for run 'nope'"   bash "$script" nope
has "list is silent"            0 ""                               bash "$script" list

mkdir -p "$DELIVERY_EVENTS_DIR" "$tmp/subagents"
controller="$tmp/controller.jsonl"
agent="$tmp/subagents/agent-a1.jsonl"
cat > "$controller" <<JSON
{"type":"user","timestamp":"2026-01-01T00:00:10.000Z","message":{"content":"from before the run"}}
{"type":"user","timestamp":"2026-01-02T00:00:20.000Z","message":{"content":"fix the   null check\nin orders"}}
{"type":"user","timestamp":"2026-01-02T00:00:30.000Z","message":{"content":"<task-notification>done</task-notification>"}}
{"type":"user","timestamp":"2026-01-02T00:00:40.000Z","isMeta":true,"message":{"content":"meta turn"}}
{"type":"user","timestamp":"2026-01-02T00:00:50.000Z","message":{"content":[{"type":"tool_result","content":"tool output"}]}}
{"type":"user","timestamp":"2026-01-02T00:01:00.000Z","message":{"content":[{"type":"text","text":"next"}]}}
JSON
printf '{"type":"user"}\n{"type":"assistant"}\n' > "$agent"

# 1767312000 is 2026-01-02T00:00:00Z
event() { # seconds-after-start json-fields
  jq -cn --argjson at "$1" --argjson fields "$2" '{ts: (1767312000 + $at), run: "r1"} + $fields' >> "$DELIVERY_EVENTS_DIR/r1.jsonl"
}
event 0   '{"src":"run","ev":"run_start","project":"/work/shop","branch":"feat/orders"}'
event 5   '{"src":"mark","ev":"mark","phase":"implement","chunk":1,"of":2,"name":"order totals","risk":"medium"}'
event 6   "$(jq -cn --arg t "$controller" '{src:"hook",ev:"tool",tool:"Bash",agent:null,transcript:$t}')"
event 7   '{"src":"hook","ev":"agent_start","agent":"a1","agent_type":"delivery-skills:reviewer"}'
event 8   "$(jq -cn --arg t "$agent" '{src:"hook",ev:"agent_stop",agent:"a1",agent_transcript:$t}')"
event 9   '{"src":"hook","ev":"agent_stop","agent":"a2","agent_transcript":"/gone/agent-a2.jsonl"}'
event 10  '{"src":"mark","ev":"mark","phase":"fix","chunk":1,"round":1}'
event 11  '{"src":"mark","ev":"mark","phase":"fix","chunk":1,"round":2}'
event 12  '{"src":"hook","ev":"refusal","tool":"Bash","reason":"git stash is not run during a run"}'
event 13  '{"src":"hook","ev":"refusal","tool":"Bash","reason":"git stash is not run during a run"}'
event 14  '{"src":"gate","ev":"gate_step","step":"lint","ok":false}'
event 15  '{"src":"gate","ev":"gate_step","step":"lint","ok":true}'
event 16  '{"src":"gate","ev":"gate_step","step":"test","ok":true}'
event 17  '{"src":"hook","ev":"tool_end","ok":false,"tool":"Edit","error":"String to replace\n not found"}'
event 18  '{"src":"hook","ev":"compact","trigger":"auto"}'
event 90  '{"src":"run","ev":"run_stop"}'
echo 'not json' >> "$DELIVERY_EVENTS_DIR/r1.jsonl"

log_line() { # ts project chunk decision
  jq -cn --arg ts "$1" --arg project "$2" --argjson chunk "$3" --arg decision "$4" '
    {ts: $ts, project: $project, chunk: $chunk, risk: "medium", decision: $decision,
     findings: 3, fix_rounds: 2, verify: "pass", static: 1, human_found: 1}' >> "$DELIVERY_LOG"
}
log_line 2026-01-01T12:00:00Z /work/shop  1 rejected
log_line 2026-01-02T00:01:10Z /work/shop  1 edited
log_line 2026-01-02T00:01:10Z /work/other 7 accepted

echo "# one run"
out=$(bash "$script")
eq    "newest run is the default"          "$(under Run | awk '$1 == "run" { print $2 }')" r1
eq    "project and branch"                 "$(under Run | awk '$1 == "project" || $1 == "branch" { print $2 }' | xargs)" "/work/shop feat/orders"
eq    "window is first to last event"      "$(under Run | awk '$1 == "from" || $1 == "to" { print $2 }' | xargs)" "2026-01-02T00:00:00Z 2026-01-02T00:01:30Z"
eq    "compactions are counted"            "$(under Run | awk '$1 == "compactions" { print $2 }')" 1
sees  "chunk with risk, fix marks, name"   "^1 +medium +2 fix +fix,implement +order totals$" "$(under Chunks)"
eq    "decision of this project and run"   "$(under Decisions | awk '{ print $1, $3, $6 }')" "1 edited human=1"
sees  "human turn, whitespace folded"      "^00:00:20  fix the null check in orders$" "$(under Human)"
sees  "text block turn"                    "^00:01:00  next$" "$(under Human)"
eq    "no wrapper, meta, tool or old turn" "$(under Human | wc -l | tr -d ' ')" 2
sees  "refusals grouped and counted"       "^2 +Bash +git stash is not run" "$(under Refusals)"
eq    "only a failed gate step"            "$(under Gate)" "lint  1 of 2 failed"
sees  "failed tool call, error on a line"  "^1 +Edit +String to replace not found$" "$(under Failed)"
sees  "controller transcript with lines"   "^6 +controller +$controller$" "$(under Transcripts)"
sees  "agent transcript with its seat"     "^2 +delivery-skills:reviewer +$agent$" "$(under Transcripts)"
misses "a transcript that is gone"         "agent-a2" "$(under Transcripts)"

echo "# a quiet run and the list"
jq -cn '{ts: 1767398400, run: "r2", src: "run", ev: "run_start", project: "/work/shop"}' > "$DELIVERY_EVENTS_DIR/r2.jsonl"
touch -t 202601030000 "$DELIVERY_EVENTS_DIR/r2.jsonl"
touch -t 202601020000 "$DELIVERY_EVENTS_DIR/r1.jsonl"
out=$(bash "$script" r2)
eq    "empty sections say none"            "$(grep -c '^none$' <<< "$out")" 7
out=$(bash "$script" list)
eq    "list is newest first"               "$(awk '{ print $1 }' <<< "$out" | xargs)" "r2 r1"
sees  "list shows marks and project"       "^r1 +2026-01-02T00:00:00Z +3 marks +/work/shop$" "$out"

finish
