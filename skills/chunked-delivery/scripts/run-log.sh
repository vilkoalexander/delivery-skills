#!/usr/bin/env bash
set -euo pipefail

log="${DELIVERY_LOG:-$HOME/.claude/delivery-skills/log.jsonl}"
run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
events_dir="${DELIVERY_EVENTS_DIR:-$(dirname "$run_dir")/events}"
required=(plan chunk risk mode implementer reviewer fix_rounds findings verify decision)
optional=(static human_found)
numeric='chunk|fix_rounds|findings|static|human_found'

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

print_stats() {
  if [ ! -s "$log" ]; then
    echo "run-log: no entries in $log"
    return
  fi
  jq -rs '
    def total(field): map(field // 0) | add;
    def decided(value): map(select(.decision == value)) | length;
    (["risk", "chunks", "static", "review", "human", "accepted", "edited", "rejected"] | @tsv),
    (group_by(.risk)[]
      | [.[0].risk, length, total(.static), total(.findings), total(.human_found),
         decided("accepted"), decided("edited"), decided("rejected")]
      | @tsv)
  ' "$log" | column -t
  echo "static, review, human: defects each caught, in the order they run"

  echo
  jq -rs '
    def total(field): map(field // 0) | add;
    def order: if . == "unknown" then [-1] else split(".") | map(tonumber? // 0) end;
    (["version", "chunks", "static", "review", "human", "rejected"] | @tsv),
    (map(.version //= "unknown") | group_by(.version) | sort_by(.[0].version | order)[]
      | [.[0].version, length, total(.static), total(.findings), total(.human_found),
         (map(select(.decision == "rejected")) | length)]
      | @tsv)
  ' "$log" | column -t
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
  local files=("$events_dir"/*.jsonl) picked
  if [ ! -e "${files[0]}" ]; then
    echo "run-log: no event files in $events_dir"
    return
  fi
  # The hook events are most of each file and none of them is a branch.
  picked=$(cat "${files[@]}" | jq -cR '
    fromjson? | select(.ev == "mark" or .ev == "gate_step" or .ev == "gate_end")
  ')

  local chunks='
    def count(test): map(select(test)) | length;
    # A mark with a name opens a chunk. A resumed run names the chunk again, thus the name joins the parts.
    [ map(select(.ev == "mark" and .phase != "final"))
      | group_by(.run)[]
      | sort_by(.ts)
      | reduce .[] as $mark ([];
          if length == 0 or $mark.name != null or $mark.chunk != .[-1][-1].chunk
          then . + [[$mark]]
          else .[-1] += [$mark]
          end)
      | .[]
    ]
    | map({ key: (if .[0].name != null then [.[0].plan, .[0].name] else [.[0].run, .[0].chunk, .[0].ts] end | tostring),
            marks: . })
    | group_by(.key)
    | map(map(.marks) | add | sort_by(.ts)
        | (map(.phase) | index("report") // length) as $report
        | { risk: (map(.risk // empty)[0] // "unknown"),
            phases: (map(.phase) | unique),
            rounds: (.[:$report] | map(select(.phase == "fix")) | to_entries
                     | map(.value.round // (.key + 1)) | max // 0),
            fix_after_report: (.[$report:] | any(.phase == "fix")) })
    | group_by(.risk)[]'

  echo
  echo "paths taken, from ${#files[@]} event files"
  jq -rs "
    ([\"risk\", \"chunks\", \"review\", \"fix\", \"verify\", \"cross\", \"fix_after_report\"] | @tsv),
    ($chunks
      | [.[0].risk, length,
         count(.phases | index(\"review\")), count(.phases | index(\"fix\")),
         count(.phases | index(\"verify\")), count(.phases | index(\"cross\")),
         count(.fix_after_report)]
      | @tsv)
  " <<<"$picked" | table
  echo "chunks that got to each phase; fix_after_report: a fix that came after the report"

  echo
  echo "fix rounds before the report, chunks at each count"
  jq -rs "
    ([\"risk\", \"0\", \"1\", \"2\", \"3\", \"4\", \"5\", \"6+\"] | @tsv),
    ($chunks
      | [.[0].risk, (range(0; 6) as \$n | count(.rounds == \$n)), count(.rounds >= 6)]
      | @tsv)
  " <<<"$picked" | table

  echo
  jq -rs '
    def count(test): map(select(test)) | length;
    (["gate_step", "runs", "failed"] | @tsv),
    (map(select(.ev == "gate_step")) | group_by(.step)[]
      | [.[0].step, length, count(.ok == false)] | @tsv),
    (map(select(.ev == "gate_end"))
      | ["whole_gate", length, count(.ok == false)] | @tsv)
  ' <<<"$picked" | table
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
    decision) one_of decision "$value" 'accepted|edited|rejected' ;;
  esac
  if [[ $key =~ ^($numeric)$ ]]; then
    [[ $value =~ ^[0-9]+$ ]] || die "$key must be a whole number (got '$value')"
  fi

  fields+=(--arg "$key" "$value")
  seen+="$key "
done

for key in "${required[@]}"; do
  [[ $seen == *" $key "* ]] || die "missing $key"
done

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
base=$(git rev-parse HEAD 2>/dev/null || echo none)
entry=$(jq -cn "${fields[@]}" \
  --arg ts "$(date -u +%FT%TZ)" --arg project "$root" --arg base "$base" \
  --arg version "$(plugin_version)" '
  $ARGS.named
  | with_entries(
      if (.key | IN("chunk", "fix_rounds", "findings", "static", "human_found")) then .value |= tonumber else . end
    )
')

mkdir -p "$(dirname "$log")"
printf '%s\n' "$entry" >> "$log"
bash "$(dirname "$0")/event.sh" log chunk_logged "entry:=$entry" || true
