#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
mark="$here/mark.sh"
export DELIVERY_LOG="$tmp/log.jsonl"

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

echo "# outside a run"
has "a valid mark is refused"       2 "mark: no run on $tmp/project. Start one first" bash "$mark" phase=implement chunk=1 of=3 risk=low
eq  "and writes no event"           "$(ls "$DELIVERY_EVENTS_DIR" 2>/dev/null)" ""

echo "# inside a run"
bash "$here/run.sh" start > /dev/null
bash "$here/run.sh" mode long > /dev/null
has "valid mark is silent"          0 ""                                     bash "$mark" phase=implement chunk=2 of=3 name="add login" risk=high
event=$(last_event)
eq  "event source and name"         "$(jq -r '.src + "/" + .ev' <<< "$event")" "mark/mark"
eq  "phase is a string"             "$(jq -c '.phase' <<< "$event")" '"implement"'
eq  "chunk, of and build are numbers" "$(jq -c '[.chunk, .of, .build]' <<< "$event")" "[2,3,1]"
eq  "name keeps its spaces"         "$(jq -r '.name' <<< "$event")" "add login"
eq  "risk is carried"               "$(jq -r '.risk' <<< "$event")" "high"

m() { bash "$mark" chunk="$chunk" of=9 "$@"; }
logged() { # decision
  bash "$here/run-log.sh" add plan=p.md chunk="$chunk" risk=medium mode=gated implementer=haiku \
    reviewer=sonnet fix_rounds=0 findings=0 verify=none decision="$1" > /dev/null
}
prompt() {
  bash "$here/event.sh" hook prompt
}

echo "# the order of the loop"
chunk=3
has "the first mark of a chunk needs its risk" 2 "the first mark of chunk 3 needs risk=" m phase=implement
has "a chunk starts with test or implement"   2 "chunk 3 has no build: it starts with phase=test or phase=implement" m phase=review risk=medium
m phase=implement name="order totals" risk=medium
has "a phase out of order names what is next" 2 "chunk 3 is at implement; next is one of: implement, gate, report" m phase=review
has "a report before the gate needs parked="  2 "chunk 3 did not pass the gate: run it, or report with parked=<reason>" m phase=report
m phase=gate
has "a static round"                  0 ""   m phase=fix
eq  "is stamped as static, round 1"   "$(jq -r '.stage + " " + (.round | tostring)' <<< "$(last_event)")" "static 1"
has "the gate must follow a fix"      2 "chunk 3 is at fix; next is one of: gate$" m phase=review
m phase=gate && m phase=fix && m phase=gate
has "a third static round is refused" 2 "at its limit of 2 static rounds" m phase=fix
m phase=review
for round in 1 2 3; do m phase=fix && m phase=gate; done
eq  "a fix after the review is a review round" "$(jq -r 'select(.phase == "fix") | .stage + " " + (.round | tostring)' "$DELIVERY_EVENTS_DIR"/*.jsonl | tail -1)" "review 3"
has "a fourth review round on medium is refused" 2 "chunk 3 is medium risk and is at its limit of 3 fix rounds" m phase=fix
has "report without verify refused"   2 "chunk 3 is medium risk and has no verify mark" m phase=report
m phase=verify
has "report after verify"             0 ""   m phase=report
has "a fix of the human after the report" 0 "" m phase=fix
eq  "is stamped as human"             "$(jq -r .stage <<< "$(last_event)")" human
m phase=gate && m phase=report
has "rebuild with no log line refused" 2 "chunk 3 has a report and no rejected decision in the run log" m phase=implement
logged accepted
has "an accepted chunk is not built again" 2 "no rejected decision" m phase=implement
logged rejected
has "rebuild after a rejected line"   0 ""   m phase=implement
eq  "the rebuild is build 2"          "$(jq -r .build <<< "$(last_event)")" 2
m phase=gate && m phase=review
has "the rebuild counts its own rounds" 0 "" m phase=fix
m phase=gate && m phase=verify && m phase=report && logged edited
chunk=2; m phase=report parked="not needed" && logged accepted

echo "# risk classes"
chunk=4
m phase=implement name="copy" risk=low && m phase=gate
has "low risk reports with no verify" 0 ""   m phase=report
chunk=5
m phase=implement name="auth" risk=high && m phase=gate && m phase=review
for round in 1 2 3 4 5; do m phase=fix && m phase=gate; done
has "a sixth round on high refused"   2 "limit of 5 fix rounds" m phase=fix
has "a parked report needs no verify" 0 ""   m phase=report parked="two findings stay open"
eq  "and carries the reason"          "$(jq -r .parked <<< "$(last_event)")" "two findings stay open"
chunk=6
m phase=test name="refunds" risk=medium
has "a blocked test author can park the chunk" 0 "" m phase=report parked="criterion 2 cannot be asserted"

echo "# the stop between chunks"
bash "$here/run.sh" mode gated > /dev/null
chunk=7
has "a chunk before it has no decision" 2 "chunk 4 has a report and no accepted decision" m phase=implement risk=low
for chunk in 4 5 6; do logged accepted; done
chunk=7
has "decisions alone are not the human" 2 "was reported and the human has not answered since: stop and wait" m phase=implement risk=low
prompt
has "after the human answered, the chunk starts" 0 "" m phase=implement risk=low
chunk=8
has "a chunk in progress blocks the next" 2 "chunk 7 has no report yet" m phase=implement risk=low
bash "$here/run.sh" mode long > /dev/null
has "long mode does not stop between chunks" 0 "" m phase=implement risk=low

echo "# the final pass"
has "a phase with no chunk before final" 2 "missing chunk" bash "$mark" phase=review
has "final needs no chunk"            0 ""   bash "$mark" phase=final
has "final only once"                 2 "the final pass has started already" bash "$mark" phase=final
has "the whole-tree verify"           0 ""   bash "$mark" phase=verify
eq  "is stamped with its scope"       "$(jq -r .scope <<< "$(last_event)")" final
bash "$mark" phase=review
for round in 1 2 3 4 5; do bash "$mark" phase=fix && bash "$mark" phase=gate; done
has "a sixth final round is refused"  2 "the final pass is final risk and is at its limit of 5 fix rounds" bash "$mark" phase=fix
has "the final report"                0 ""   bash "$mark" phase=report

echo "# status"
has "one line per chunk, with what is next" 0 "^chunk 5/9 — auth · high risk · at report · 5 fix round\(s\) · parked: two findings stay open · decision: accepted — next: report, fix$" bash "$here/run.sh" status

has "the event file path, in a run"   0 "^$DELIVERY_EVENTS_DIR/.+\.jsonl$" bash "$here/event.sh" file
bash "$here/run.sh" stop > /dev/null
has "and nothing outside a run"       0 ""   bash "$here/event.sh" file

finish
