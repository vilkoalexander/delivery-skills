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
has "unknown phase"                 2 "phase must be one of: implement, gate" bash "$mark" phase=build chunk=1
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

finish
