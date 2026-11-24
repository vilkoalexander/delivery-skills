#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
source "$here/lib/run.sh"
log=$run_log
events_dir=$run_events_dir
required=(plan chunk risk mode implementer reviewer fix_rounds findings verify decision)
optional=(static human_found)
numbers=(chunk fix_rounds findings static human_found)

usage() {
  echo "usage: run-log.sh add ${required[*]/%/=<value>} [${optional[*]/%/=<n>}]" >&2
  echo "       run-log.sh stats" >&2
  exit 2
}

die() {
  echo "run-log: $1" >&2
  exit 2
}

is_key() {
  [[ " ${required[*]} ${optional[*]} " == *" $1 "* ]]
}

# one_of KEY VALUE ALLOWED — ALLOWED is an alternation such as 'low|medium|high'
one_of() {
  [[ $2 =~ ^($3)$ ]] || die "$1 must be one of: ${3//|/, } (got '$2')"
}

# A line that is not JSON is skipped and counted, so one bad write never hides the rest.
log_entries() {
  jq -cR 'fromjson? | select(type == "object")' "$log"
}

print_stats() {
  local bad
  if [ ! -s "$log" ]; then
    echo "run-log: no entries in $log"
    return
  fi
  bad=$(jq -cR 'try (fromjson | select(type != "object")) catch "bad"' "$log" | wc -l | tr -d ' ')
  [ "$bad" = 0 ] || echo "run-log: skipped $bad line(s) of $log that are not JSON objects" >&2

  log_entries | jq -rs '
    def total(field): map(field // 0) | add;
    def decided(value): map(select(.decision == value)) | length;
    (["risk", "chunks", "static", "review", "human", "accepted", "edited", "rejected"] | @tsv),
    (group_by(.risk)[]
      | [.[0].risk, length, total(.static), total(.findings), total(.human_found),
         decided("accepted"), decided("edited"), decided("rejected")]
      | @tsv)
  ' | column -t
  echo "static, review, human: defects each caught, in the order they run"

  echo
  log_entries | jq -rs '
    def total(field): map(field // 0) | add;
    def order: if . == "unknown" then [-1] else split(".") | map(tonumber? // 0) end;
    (["version", "chunks", "static", "review", "human", "rejected"] | @tsv),
    (map(.version //= "unknown") | group_by(.version) | sort_by(.[0].version | order)[]
      | [.[0].version, length, total(.static), total(.findings), total(.human_found),
         (map(select(.decision == "rejected")) | length)]
      | @tsv)
  ' | column -t
  echo "by plugin version: human and rejected per chunk should fall after a change to a gate or a rubric"
}

plugin_version() {
  local manifest
  manifest="$(dirname "$0")/../../../.claude-plugin/plugin.json"
  if [ -n "${DELIVERY_PLUGIN_VERSION:-}" ]; then
    echo "$DELIVERY_PLUGIN_VERSION"
  elif [ -f "$manifest" ]; then
    jq -r '.version // "unknown"' "$manifest" 2>/dev/null || echo unknown
  else
    echo unknown
  fi
}

table() {
  column -t | sed 's/ *$//'
}

print_paths() {
  local files=("$events_dir"/*.jsonl) builds picked
  if [ ! -e "${files[0]}" ]; then
    echo "run-log: no event files in $events_dir"
    return
  fi
  # lifecycle.mjs says what a build is; this only counts them.
  builds=$(node "$here/lifecycle.mjs" builds "${files[@]}" | jq -c 'select(.chunk != "final")')

  echo
  echo "paths taken, from ${#files[@]} event files"
  jq -rs '
    def count(test): map(select(test)) | length;
    def got(phase): count(.phases | index(phase));
    (["risk", "builds", "review", "fix", "verify", "cross", "parked", "fix_after_report"] | @tsv),
    (group_by(.risk)[]
      | [.[0].risk // "unknown", length, got("review"), got("fix"), got("verify"), got("cross"),
         count(.parked != null), count(.fix.human > 0)]
      | @tsv)
  ' <<< "$builds" | table
  echo "builds that got to each phase; fix_after_report: a fix the human asked for"

  echo
  echo "fix rounds after a review, builds at each count"
  jq -rs '
    def count(test): map(select(test)) | length;
    (["risk", "0", "1", "2", "3", "4", "5", "6+"] | @tsv),
    (group_by(.risk)[]
      | [.[0].risk // "unknown", (range(0; 6) as $n | count(.fix.review == $n)), count(.fix.review >= 6)]
      | @tsv)
  ' <<< "$builds" | table

  echo
  picked=$(cat "${files[@]}" | jq -cR 'fromjson? | select(.ev == "gate_step" or .ev == "gate_end")')
  jq -rs '
    def count(test): map(select(test)) | length;
    (["gate_step", "runs", "failed"] | @tsv),
    (map(select(.ev == "gate_step")) | group_by(.step)[]
      | [.[0].step, length, count(.ok == false)] | @tsv),
    (map(select(.ev == "gate_end"))
      | ["whole_gate", length, count(.ok == false)] | @tsv)
  ' <<< "$picked" | table
  echo "a step with no failures in many runs finds nothing, or its check is weak"
}

if [ "${1:-}" = stats ]; then
  print_stats
  print_paths
  exit 0
fi
[ "${1:-}" = add ] || usage
shift

fields=()
seen=" "
for pair in "$@"; do
  [[ $pair == *=* ]] || die "expected key=value, got '$pair'"
  key=${pair%%=*}
  value=${pair#*=}
  is_key "$key" || die "unknown key '$key'"
  [[ $seen != *" $key "* ]] || die "repeated key '$key'"

  case $key in
    risk)     one_of risk "$value" 'low|medium|high' ;;
    mode)     one_of mode "$value" 'gated|long' ;;
    verify)   one_of verify "$value" 'pass|fail|none' ;;
    decision) one_of decision "$value" 'accepted|edited|rejected|stopped' ;;
  esac
  if [[ " ${numbers[*]} " == *" $key "* ]]; then
    [[ $value =~ ^[0-9]+$ ]] || die "$key must be a whole number (got '$value')"
    fields+=(--argjson "$key" "$value")
  else
    fields+=(--arg "$key" "$value")
  fi
  seen+="$key "
done

for key in "${required[@]}"; do
  [[ $seen == *" $key "* ]] || die "missing $key"
done

run_locate
run_active || die "no run on $run_root: a line belongs to a run. Start one first: bash $here/run.sh start"
chunk=$(jq -rn "${fields[@]}" '$ARGS.named.chunk')
build=$(node "$here/lifecycle.mjs" builds "$(run_events_file)" \
  | jq -c --argjson chunk "$chunk" 'select(.chunk == $chunk)' | tail -1)
[ -n "$build" ] || die "chunk $chunk has no mark in this run"
[ "$(jq -r .reported <<< "$build")" = true ] || die "chunk $chunk has no report yet: the human decides on a report"

entry=$(jq -cn "${fields[@]}" \
  --arg ts "$(date -u +%FT%TZ)" --arg project "$run_root" --arg run "$(run_field run)" \
  --arg base "$(git rev-parse HEAD 2>/dev/null || echo none)" --arg version "$(plugin_version)" \
  --argjson build "$(jq .build <<< "$build")" '$ARGS.named')

mkdir -p "$(dirname "$log")"
printf '%s\n' "$entry" >> "$log"
bash "$here/event.sh" log chunk_logged "entry:=$entry"
