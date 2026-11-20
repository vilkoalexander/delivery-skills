#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
mark="$here/mark.sh"

new_repo project
last_event() { tail -1 "$DELIVERY_EVENTS_DIR"/*.jsonl; }

echo "# refuses bad input"
has "no arguments prints usage"     2 "usage: mark.sh phase="                bash "$mark"
has "bare word"                     2 "expected key=value, got 'review'"     bash "$mark" review
has "unknown key"                   2 "unknown key 'stage'"                  bash "$mark" stage=review chunk=1
has "repeated key"                  2 "repeated key 'chunk'"                 bash "$mark" phase=review chunk=1 chunk=2
has "unknown phase"                 2 "phase must be one of: test, implement, gate" bash "$mark" phase=build chunk=1
has "unknown risk"                  2 "risk must be one of: low, medium, high" bash "$mark" phase=review chunk=1 risk=huge
has "chunk is not a number"         2 "chunk must be a whole number"         bash "$mark" phase=review chunk=one
has "missing phase"                 2 "missing phase"                        bash "$mark" chunk=1
has "missing chunk"                 2 "missing chunk"                        bash "$mark" phase=review

echo "# outside a run"
has "valid mark is silent"          0 ""                                     bash "$mark" phase=review chunk=1 of=3
eq  "and writes no event"           "$(ls "$DELIVERY_EVENTS_DIR" 2>/dev/null)" ""

echo "# inside a run"
bash "$here/run.sh" start > /dev/null
has "valid mark is silent"          0 ""                                     bash "$mark" phase=review chunk=2 of=3 name="add login" risk=high round=1
event=$(last_event)
eq  "event source and name"         "$(jq -r '.src + "/" + .ev' <<< "$event")" "mark/mark"
eq  "phase is a string"             "$(jq -c '.phase' <<< "$event")" '"review"'
eq  "chunk, of and round are numbers" "$(jq -c '[.chunk, .of, .round]' <<< "$event")" "[2,3,1]"
eq  "name keeps its spaces"         "$(jq -r '.name' <<< "$event")" "add login"
eq  "risk is carried"               "$(jq -r '.risk' <<< "$event")" "high"
has "final needs no chunk"          0 ""                                     bash "$mark" phase=final
eq  "final is recorded"             "$(jq -r '.phase' <<< "$(last_event)")" "final"

echo "# the order of the loop"
export DELIVERY_LOG="$tmp/log.jsonl"
m() { bash "$mark" chunk="$chunk" of=9 "$@"; }
logged() { # decision
  bash "$here/run-log.sh" add plan=p.md chunk="$chunk" risk=medium mode=gated implementer=haiku \
    reviewer=sonnet fix_rounds=0 findings=0 verify=none decision="$1" > /dev/null
}

chunk=3
m phase=implement name="order totals" risk=medium
m phase=gate && m phase=fix && m phase=gate && m phase=review
has "three fix rounds on medium"      0 ""   bash -c "bash '$mark' phase=fix chunk=3 round=1 && bash '$mark' phase=fix chunk=3 round=2 && bash '$mark' phase=fix chunk=3 round=3"
has "a fourth is refused"             2 "chunk 3 is medium risk and is at its limit of 3 fix rounds" m phase=fix round=4
has "report without verify refused"   2 "chunk 3 is medium risk and has no verify mark" m phase=report
m phase=verify
has "report after verify"             0 ""   m phase=report
has "a fix of the human after the report" 0 "" m phase=fix
m phase=report
has "rebuild with no log line refused" 2 "chunk 3 has a report and no run-log line after it" m phase=implement
sleep 1
logged rejected
has "rebuild after a rejected line"   0 ""   m phase=implement
m phase=review
has "the rebuild counts its own rounds" 0 "" m phase=fix round=1

chunk=4
m phase=implement name="copy" risk=low
has "static round on low is not a fix round" 0 "" m phase=fix
has "low risk reports with no verify" 0 ""   m phase=report

chunk=5
m phase=implement name="auth" risk=high
m phase=review
for round in 1 2 3 4 5; do m phase=fix round=$round; done
has "a sixth round on high refused"   2 "limit of 5 fix rounds" m phase=fix round=6

chunk=7
m phase=test name="refunds" risk=medium
m phase=implement && m phase=gate && m phase=review
has "a build that starts with tests needs verify" 2 "chunk 7 is medium risk and has no verify mark" m phase=report
m phase=verify && m phase=report
has "a rebuild from the tests needs the log line" 2 "chunk 7 has a report and no run-log line after it" m phase=test

chunk=6
has "a chunk this file did not see start may report" 0 "" m phase=report risk=high
has "the event file path, in a run"   0 "^$DELIVERY_EVENTS_DIR/.+\.jsonl$" bash "$here/event.sh" file
bash "$here/run.sh" stop > /dev/null
has "and nothing outside a run"       0 ""   bash "$here/event.sh" file

finish
