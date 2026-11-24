#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/run-log.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export DELIVERY_LOG="$tmp/state/log.jsonl"
export DELIVERY_RUN_DIR="$tmp/state/runs" DELIVERY_EVENTS_DIR="$tmp/events"
repo="$tmp/repo"
mkdir -p "$repo" && git -C "$repo" init -q
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
head_sha=$(git -C "$repo" rev-parse HEAD)
cd "$repo" || exit 1
bash "$script" add plan=a chunk=2 risk=medium mode=long implementer=h reviewer=s fix_rounds=0 findings=0 verify=pass decision=edited > /dev/null 2> "$tmp/err"
norun="$?:$(cat "$tmp/err")"
bash "$here/run.sh" start > /dev/null
m() { bash "$here/mark.sh" chunk=2 of=3 "$@"; }
m phase=implement risk=medium
bash "$script" add plan=a chunk=2 risk=medium mode=long implementer=h reviewer=s fix_rounds=0 findings=0 verify=pass decision=edited > /dev/null 2> "$tmp/err"
noreport="$?:$(cat "$tmp/err")"
m phase=gate && m phase=review && m phase=verify && m phase=report

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1" "got '$2', wanted '$3'"; fi; }
last() { tail -n 1 "$DELIVERY_LOG" | jq -r "$1"; }
lines() { wc -l < "$DELIVERY_LOG" | tr -d ' '; }

valid=(plan=plans/a.md chunk=2 risk=medium mode=long implementer=haiku reviewer=sonnet
       fix_rounds=1 findings=3 verify=pass decision=edited)

bash "$script" add "${valid[@]}" >/dev/null; eq "valid entry exits 0" "$?" 0
eq "one line written" "$(lines)" 1
eq "base is HEAD" "$(last .base)" "$head_sha"
eq "project is the toplevel" "$(last .project)" "$(git rev-parse --show-toplevel)"
eq "plan kept" "$(last .plan)" plans/a.md
eq "chunk is a number" "$(last '.chunk | type')" number
eq "fix_rounds is a number" "$(last '.fix_rounds | type')" number
eq "findings value" "$(last .findings)" 3
eq "decision kept" "$(last .decision)" edited
eq "version is the plugin's" "$(last .version)" "$(jq -r .version "$here/../../../.claude-plugin/plugin.json")"
eq "the line names its run" "$(last .run)" "$(jq -r .run "$DELIVERY_RUN_DIR"/*)"
eq "and the build of the chunk" "$(last .build)" 1
case $norun in 2:*"no run on"*) ok "outside a run: refused" ;; *) nok "outside a run: refused" "$norun" ;; esac
case $noreport in 2:*"has no report yet"*) ok "before the report: refused" ;; *) nok "before the report: refused" "$noreport" ;; esac
eq "timestamp set" "$(last '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")')" true

with() { # replaces one valid field with the given key=value
  local key=${1%%=*} rest=() pair
  for pair in "${valid[@]}"; do
    [ "${pair%%=*}" = "$key" ] || rest+=("$pair")
  done
  bash "$script" add "${rest[@]}" "$1"
}

with 'plan=has "quotes" and \slash.md' >/dev/null
eq "awkward values stay valid JSON" "$(last .plan)" 'has "quotes" and \slash.md'
eq "entries append" "$(lines)" 2

reject() {
  local before
  before=$(lines)
  if with "$2" >/dev/null 2>"$tmp/err"; then nok "$1" "exited 0"
  elif grep -q "$3" "$tmp/err"; then ok "$1"
  else nok "$1" "wrong reason: $(cat "$tmp/err")"; fi
  eq "$1 writes nothing" "$(lines)" "$before"
}
reject "bad risk"     risk=huge      "risk must be"
reject "bad mode"     mode=fast      "mode must be"
reject "bad verify"   verify=maybe   "verify must be"
reject "bad decision" decision=fine  "decision must be"
reject "bad chunk"    chunk=two      "chunk must be"
reject "bad rounds"   fix_rounds=-1  "fix_rounds must be"
reject "unknown key"  colour=red     "unknown key"
reject "malformed"    noequals       "expected key=value"

if bash "$script" add plan=a chunk=1 risk=low >/dev/null 2>&1; then nok "missing key" "exited 0"; else ok "missing key"; fi
if bash "$script" add "${valid[@]}" risk=low >/dev/null 2>&1; then nok "repeated key" "exited 0"; else ok "repeated key"; fi
eq "rejected entries write nothing" "$(lines)" 2

with static=2 >/dev/null && bash "$script" add "${valid[@]}" static=1 human_found=1 >/dev/null
eq "optional counts are numbers" "$(last '.human_found | type')" number
reject "bad optional" human_found=some "human_found must be"
stats=$(bash "$script" stats)
eq "stats sums what each gate caught" "$(awk '$1 == "medium" { print $2, $3, $4, $5; exit }' <<<"$stats")" "4 3 12 1"
old='{"risk":"low","decision":"rejected","human_found":2}'
echo "$old" >> "$DELIVERY_LOG"
DELIVERY_PLUGIN_VERSION=0.9.0 bash "$script" add "${valid[@]}" human_found=1 >/dev/null
DELIVERY_PLUGIN_VERSION=0.10.0 with decision=rejected >/dev/null
stats=$(bash "$script" stats)
byversion=$(awk '$1 == "version" { on = 1; next } on && !NF { exit } on && $1 != "by" { print $1, $2, $5, $6 }' <<<"$stats" | head -3 | tr '\n' ';')
eq "stats by version, an entry with none first, then in number order" "$byversion" "unknown 1 2 1;0.9.0 1 1 0;0.10.0 1 0 1;"
sed -i.bak '$d' "$DELIVERY_LOG"; sed -i.bak '$d' "$DELIVERY_LOG"; sed -i.bak '$d' "$DELIVERY_LOG"; rm -f "$DELIVERY_LOG.bak"
stats=$(bash "$script" stats)
echo 'not json at all' >> "$DELIVERY_LOG"
eq "a line that is not JSON does not stop stats" "$(bash "$script" stats 2>/dev/null | awk '$1 == "medium" { print $2; exit }')" 4
eq "and is named" "$(bash "$script" stats 2>&1 >/dev/null | grep -c 'skipped 1 line')" 1
sed -i.bak '$d' "$DELIVERY_LOG"; rm -f "$DELIVERY_LOG.bak"
with decision=stopped > /dev/null; eq "stopped is a decision" "$(last .decision)" stopped
sed -i.bak '$d' "$DELIVERY_LOG"; rm -f "$DELIVERY_LOG.bak"
eq "stats on an empty log exits 0" "$(DELIVERY_LOG="$tmp/none.jsonl" bash "$script" stats >/dev/null; echo $?)" 0

bash "$here/run.sh" stop > /dev/null
rm -rf "$DELIVERY_EVENTS_DIR"
mkdir -p "$DELIVERY_EVENTS_DIR"
ts=0
ev() { # ev RUN JSON-FIELDS — appends one event with a rising timestamp
  ts=$((ts + 1))
  printf '{"ts":%s,"run":"%s",%s}\n' "$ts" "$1" "$2" >> "$DELIVERY_EVENTS_DIR/$1.jsonl"
}
mark() { # mark RUN CHUNK PHASE [EXTRA-FIELDS]
  ev "$1" "\"ev\":\"mark\",\"chunk\":$2,\"phase\":\"$3\"${4:+,$4}"
}
step() { # step RUN NAME OK
  ev "$1" "\"ev\":\"gate_step\",\"step\":\"$2\",\"ok\":$3"
}
section() { # the rows below the header TITLE (single spaces), up to the next blank line
  awk -v title="$1" '{ line = $0; gsub(/ +/, " ", line) }
    index(line, title) == 1 { on = 1; next } on && !NF { on = 0 } on' <<<"$stats"
}
row() { # row TITLE FIRST-COLUMN — the remaining columns of that row
  section "$1" | awk -v key="$2" '$1 == key { $1 = ""; sub(/^ /, ""); print }'
}

eq "stats with no event files exits 0" "$(bash "$script" stats >/dev/null; echo $?)" 0

named='"name":"orders","risk":"high","plan":"p.md"'
mark r1 1 implement "$named"
step r1 lint false; step r1 test true; ev r1 '"ev":"gate_end","ok":false'
step r1 lint true;  step r1 test true; ev r1 '"ev":"gate_end","ok":true'
mark r1 1 gate; mark r1 1 review
mark r1 1 fix '"round":1'; mark r1 1 fix '"round":2'
mark r1 1 verify; mark r1 1 cross; mark r1 1 report
mark r1 2 implement '"name":"copy","risk":"low","plan":"p.md"'
mark r1 2 gate; mark r1 2 report
mark r1 3 implement '"name":"mail","risk":"medium","plan":"p.md"'
mark r1 3 review; mark r1 3 verify; mark r1 3 report
mark r1 1 fix; mark r1 1 gate; mark r1 1 report
ev r1 '"ev":"chunk_logged","entry":{"chunk":1,"decision":"rejected"}'
mark r1 1 implement; mark r1 1 gate; mark r1 1 report '"parked":"the plan is wrong"'
ev r1 '"ev":"mark","phase":"final"'
echo 'not json' >> "$DELIVERY_EVENTS_DIR/r1.jsonl"

stats=$(bash "$script" stats)
eq "a chunk built twice is two builds"           "$(row "risk builds review" high)" "2 1 1 1 1 1 1"
eq "a low-risk chunk reaches no review"          "$(row "risk builds review" low)" "1 0 0 0 0 0 0"
eq "a clean review reaches no fix round"         "$(row "risk builds review" medium)" "1 1 0 1 0 0 0"
eq "a fix after the report is not a review round" "$(row "risk 0 1" high)" "1 0 1 0 0 0 0"
eq "a build with no fix is in column 0"          "$(row "risk 0 1" medium)" "1 0 0 0 0 0 0"
eq "a gate step counts its runs and failures"    "$(row "gate_step" lint)" "2 1"
eq "a step that never fails shows 0"             "$(row "gate_step" test)" "2 0"
eq "the whole gate has its own row"              "$(row "gate_step" whole_gate)" "2 1"
eq "the log table is still first"                "$(awk '$1 == "medium" { print $2; exit }' <<<"$stats")" 4

if bash "$script" nonsense >/dev/null 2>&1; then nok "unknown command" "exited 0"; else ok "unknown command"; fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" = 0 ]
