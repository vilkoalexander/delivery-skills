#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

phases='test|implement|gate|review|fix|verify|cross|report|final'
risks='low|medium|high'
keys=(phase chunk of name risk plan round)

usage() {
  echo "usage: mark.sh phase=<${phases}> chunk=N of=M [name=<text>] [risk=<${risks}>] [plan=<path>] [round=N]" >&2
  echo "       phase=final needs no chunk" >&2
  exit 2
}

die() {
  echo "mark: $1" >&2
  exit 2
}

is_key() {
  [[ " ${keys[*]} " == *" $1 "* ]]
}

[ $# -gt 0 ] || usage

fields=()
phase=""
chunk=""
seen=" "
for pair in "$@"; do
  [[ $pair == *=* ]] || die "expected key=value, got '$pair'"
  key=${pair%%=*}
  value=${pair#*=}
  is_key "$key" || die "unknown key '$key'"
  [[ $seen != *" $key "* ]] || die "repeated key '$key'"
  seen+="$key "

  case $key in
    phase)
      [[ $value =~ ^($phases)$ ]] || die "phase must be one of: ${phases//|/, } (got '$value')"
      phase=$value
      fields+=("phase=$value")
      ;;
    risk)
      [[ $value =~ ^($risks)$ ]] || die "risk must be one of: ${risks//|/, } (got '$value')"
      fields+=("risk=$value")
      ;;
    chunk|of|round)
      [[ $value =~ ^[0-9]+$ ]] || die "$key must be a whole number (got '$value')"
      [ "$key" = chunk ] && chunk=$value
      fields+=("$key:=$value")
      ;;
    *)
      fields+=("$key=$value")
      ;;
  esac
done

[ -n "$phase" ] || die "missing phase"
[ -n "$chunk" ] || [ "$phase" = final ] || die "missing chunk"

fix_limit() {
  case $1 in
    medium) echo 3 ;;
    high) echo 5 ;;
  esac
}

# Refuses a mark that the loop does not permit. It judges only what this run's file shows.
check_order() {
  local file=$1 build risk limit
  # A build is the marks of the chunk from the last test or implement mark that starts or restarts it.
  build=$(jq -cR 'fromjson? | select(.ev == "mark")' "$file" | jq -cs --argjson chunk "$chunk" '
    map(select(.chunk == $chunk)) as $marks
    | ([range(0; $marks | length)
        | select(($marks[.].phase | IN("test", "implement")) and (. == 0 or $marks[. - 1].phase == "report"))] | last) as $start
    | ($marks[($start // 0):] | map(.phase)) as $phases
    | { risk: ($marks | map(.risk // empty) | last // ""),
        from_start: ($start != null),
        reported: ($phases | index("report") != null),
        verified: ($phases | index("verify") != null),
        review_fixes: ($phases[($phases | index("review") // length):] | map(select(. == "fix")) | length),
        last_phase: ($marks | last | .phase // ""),
        last_at: ($marks | last | .ts // 0 | floor | todate) }')
  field() { jq -r ".$1" <<< "$build"; }
  risk=$(field risk)
  limit=$(fix_limit "$risk")

  case $phase in
    fix)
      if [ -n "$limit" ] && [ "$(field reported)" = false ] && [ "$(field review_fixes)" -ge "$limit" ]; then
        die "chunk $chunk is $risk risk and is at its limit of $limit fix rounds: park the open findings and report"
      fi
      ;;
    report)
      if [[ $risk =~ ^(medium|high)$ ]] && [ "$(field from_start)" = true ] && [ "$(field verified)" = false ]; then
        die "chunk $chunk is $risk risk and has no verify mark: dispatch the verifier before the report"
      fi
      ;;
    test|implement)
      [ "$(field last_phase)" = report ] || return 0
      local log root logged
      log="${DELIVERY_LOG:-$HOME/.claude/delivery-skills/log.jsonl}"
      root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
      logged=$(jq -rs --arg project "$root" --arg since "$(field last_at)" --argjson chunk "$chunk" '
        any(.[]; .project == $project and .chunk == $chunk and .ts >= $since)' "$log" 2>/dev/null || echo false)
      [ "$logged" = true ] \
        || die "chunk $chunk has a report and no run-log line after it: add the line (decision=rejected) before you build the chunk again"
      ;;
  esac
}

if [ -n "$chunk" ]; then
  file=$(bash "$here/event.sh" file)
  if [ -n "$file" ] && [ -f "$file" ]; then check_order "$file"; fi
fi

bash "$here/event.sh" mark mark "${fields[@]}" || true
