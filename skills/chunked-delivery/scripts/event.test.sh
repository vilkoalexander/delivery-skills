#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
event="$here/event.sh"
mark="$here/mark.sh"
run="$here/run.sh"
runlog="$here/run-log.sh"
gate="$here/../../delivery-pipeline/scripts/static-gate.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export DELIVERY_RUN_DIR="$tmp/state/runs"
export DELIVERY_LOG="$tmp/state/log.jsonl"
events="$tmp/state/events"
repo="$tmp/repo"
mkdir -p "$repo" && git -C "$repo" init -q
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
cd "$repo" || exit 1

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1" "got '$2', wanted '$3'"; fi; }
file() { ls "$events"/*.jsonl 2>/dev/null | head -1; }
last() { tail -n 1 "$(file)" | jq -r "$1"; }
lines() { local f; f=$(file); if [ -n "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi; }
evs() { jq -r .ev "$(file)" | tr '\n' ' '; }
fails() { if "$@" >/dev/null 2>&1; then nok "$name" "exited 0"; else ok "$name"; fi; }

bash "$event" gate gate_start; eq "no run: exit 0" "$?" 0
eq "no run: nothing written" "$(lines)" 0
bash "$mark" phase=implement chunk=1 of=3; eq "mark outside a run: exit 0" "$?" 0
eq "mark outside a run: nothing written" "$(lines)" 0
name="no arguments is usage"; fails bash "$event"

bash "$run" start >/dev/null
eq "run_start" "$(last .ev)" run_start
eq "run_start: project" "$(last .project)" "$(git rev-parse --show-toplevel)"
eq "run_start: src" "$(last .src)" run
bash "$run" start >/dev/null
eq "second start writes no second run_start" "$(lines)" 1

bash "$event" gate gate_step step=lint ok:=false s:=4
eq "event: ev" "$(last .ev)" gate_step
eq "event: string field" "$(last .step)" lint
eq "event: json bool" "$(last '.ok | type')" boolean
eq "event: json number" "$(last .s)" 4
eq "event: ts is a number" "$(last '.ts | type')" number
before=$(lines)
bash "$event" gate gate_step ok:=notjson; eq "bad json value: exit 0" "$?" 0
eq "bad json value: nothing written" "$(lines)" "$before"
(cd "$repo" && mkdir -p sub && cd sub && bash "$event" gate from_subdir)
eq "event from a subdir lands in the same run" "$(last .ev)" from_subdir

bash "$mark" phase=implement chunk=2 of=5 name="invoice totals" risk=medium plan=plans/billing.md
eq "mark: ev" "$(last .ev)" mark
eq "mark: phase" "$(last .phase)" implement
eq "mark: chunk is a number" "$(last '.chunk | type')" number
eq "mark: of" "$(last .of)" 5
eq "mark: name with spaces" "$(last .name)" "invoice totals"
eq "mark: risk" "$(last .risk)" medium
eq "mark: plan" "$(last .plan)" plans/billing.md
bash "$mark" phase=fix chunk=2 of=5 round=2
eq "mark: round" "$(last .round)" 2
bash "$mark" phase=final; eq "mark: final needs no chunk" "$?" 0
eq "mark: final written" "$(last .phase)" final

before=$(lines)
name="mark: unknown phase";  fails bash "$mark" phase=lunch chunk=1 of=2
name="mark: missing phase";  fails bash "$mark" chunk=1 of=2
name="mark: missing chunk";  fails bash "$mark" phase=review
name="mark: bad risk";       fails bash "$mark" phase=review chunk=1 risk=huge
name="mark: bad chunk";      fails bash "$mark" phase=review chunk=one
name="mark: unknown key";    fails bash "$mark" phase=review chunk=1 colour=red
name="mark: repeated key";   fails bash "$mark" phase=review phase=fix chunk=1
name="mark: not key=value";  fails bash "$mark" review
eq "rejected marks write nothing" "$(lines)" "$before"

before=$(lines)
echo "nope.ts" | STATIC_SKIP="test-lock drift" bash "$gate" check >/dev/null 2>&1
eq "gate on missing paths: start and end" "$(jq -r .ev "$(file)" | tail -n $(( $(lines) - before )) | tr '\n' ' ')" "gate_start gate_end "
eq "gate_end: ok" "$(last .ok)" true
eq "gate_end: src" "$(last .src)" gate

echo "export const a = 1" > a.mjs
before=$(lines)
STATIC_SKIP="test-lock drift reuse" STATIC_TEST="false" bash "$gate" check a.mjs >/dev/null 2>&1
eq "failing gate exits 1" "$?" 1
eq "failing gate: events" "$(jq -r '.ev + (if .step then ":" + .step else "" end)' "$(file)" | tail -n $(( $(lines) - before )) | tr '\n' ' ')" "gate_start gate_step_start:test gate_step:test gate_end "
eq "failing gate: end not ok" "$(last .ok)" false
eq "failing gate: step not ok" "$(tail -n 2 "$(file)" | head -1 | jq -r .ok)" false
STATIC_SKIP="test-lock drift reuse" STATIC_TEST="true" bash "$gate" check a.mjs >/dev/null 2>&1
eq "passing gate exits 0" "$?" 0
eq "passing gate: end ok" "$(last .ok)" true

bash "$runlog" add plan=plans/a.md chunk=2 risk=medium mode=long implementer=haiku reviewer=sonnet \
  fix_rounds=1 findings=3 verify=pass decision=edited >/dev/null
eq "chunk_logged" "$(last .ev)" chunk_logged
eq "chunk_logged: entry chunk" "$(last .entry.chunk)" 2
eq "chunk_logged: entry decision" "$(last .entry.decision)" edited

chmod 500 "$events"
bash "$event" gate blocked; eq "unwritable event dir: exit 0" "$?" 0
bash "$mark" phase=review chunk=2 of=5; eq "mark with unwritable dir: exit 0" "$?" 0
chmod 700 "$events"

bash "$run" stop >/dev/null
eq "run_stop is the last event" "$(last .ev)" run_stop
before=$(lines)
bash "$event" gate after_stop
eq "after stop: nothing written" "$(lines)" "$before"

sleep 1
bash "$run" start >/dev/null
eq "a second run gets its own file" "$(ls "$events" | wc -l | tr -d ' ')" 2

echo
echo "passed: $pass  failed: $fail"
[ "$fail" = 0 ]
