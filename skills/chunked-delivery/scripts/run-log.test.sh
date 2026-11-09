#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/run-log.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export DELIVERY_LOG="$tmp/state/log.jsonl"
repo="$tmp/repo"
mkdir -p "$repo" && git -C "$repo" init -q
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
head_sha=$(git -C "$repo" rev-parse HEAD)
cd "$repo" || exit 1

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

if bash "$script" nonsense >/dev/null 2>&1; then nok "unknown command" "exited 0"; else ok "unknown command"; fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" = 0 ]
