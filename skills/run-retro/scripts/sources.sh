#!/usr/bin/env bash
set -euo pipefail

run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
events_dir="${DELIVERY_EVENTS_DIR:-$(dirname "$run_dir")/events}"
log="${DELIVERY_LOG:-$HOME/.claude/delivery-skills/log.jsonl}"

usage() {
  echo "usage: sources.sh list        the recorded runs, newest first" >&2
  echo "       sources.sh [run-id]    what one run left behind; the newest run if none is named" >&2
  exit 2
}

die() {
  echo "sources: $1" >&2
  exit 1
}

table() {
  column -t -s $'\t' | sed 's/ *$//'
}

section() {
  local title=$1 body
  body=$(cat)
  echo
  echo "## $title"
  if [ -n "$body" ]; then printf '%s\n' "$body"; else echo "none"; fi
}

read_events() {
  jq -cR 'fromjson? // empty' "$1"
}

list_runs() {
  local file
  for file in $(ls -t "$events_dir"/*.jsonl 2>/dev/null); do
    read_events "$file" | jq -rs --arg run "$(basename "$file" .jsonl)" '
      [$run, (map(.ts) | min | floor | todate), (map(select(.ev == "mark")) | length | tostring) + " marks",
       (map(select(.ev == "run_start"))[0].project // "unknown")] | @tsv'
  done | table
}

case "${1:-}" in
  -h|--help) usage ;;
  list) list_runs; exit 0 ;;
esac

run=${1:-}
if [ -z "$run" ]; then
  newest=$(ls -t "$events_dir"/*.jsonl 2>/dev/null | head -1 || true)
  [ -n "$newest" ] || die "no event files in $events_dir"
  run=$(basename "$newest" .jsonl)
fi
file="$events_dir/$run.jsonl"
[ -f "$file" ] || die "no event file for run '$run' in $events_dir"

events=$(read_events "$file")
[ -n "$events" ] || die "$file has no events"

query() {
  jq -rs "$@" <<< "$events"
}

from=$(query 'map(.ts) | min | floor | todate')
to=$(query 'map(.ts) | max | ceil | todate')
project=$(query 'map(select(.ev == "run_start"))[0].project // ""')

section Run <<EOF
$(printf 'run\t%s\nproject\t%s\nbranch\t%s\nfrom\t%s\nto\t%s\ncompactions\t%s\n' \
  "$run" "${project:-unknown}" "$(query 'map(select(.ev == "run_start"))[0].branch // "unknown"')" \
  "$from" "$to" "$(query 'map(select(.ev == "compact")) | length')" | table)
EOF

query '
  map(select(.ev == "mark" and .chunk != null)) | group_by(.chunk)[]
  | [(.[0].chunk | tostring), (map(.risk // empty)[0] // "unknown"),
     (map(select(.phase == "fix")) | length | tostring) + " fix",
     (map(.phase) | unique | join(",")), (map(.name // empty)[0] // "")]
  | @tsv' | table | section "Chunks, from the marks"

if [ -s "$log" ]; then
  jq -r --arg project "$project" --arg from "$from" --arg to "$to" '
    select(.project == $project and .ts >= $from and .ts <= $to)
    | [(.chunk | tostring), .risk, .decision, "static=\(.static // 0)", "review=\(.findings)",
       "human=\(.human_found // 0)", "fix_rounds=\(.fix_rounds)", "verify=\(.verify)"]
    | @tsv' "$log" | table
fi | section "Decisions, from the run log"

controllers=$(query 'map(select(.agent == null) | .transcript // empty) | unique[]')

while IFS= read -r transcript; do
  [ -f "$transcript" ] || continue
  # A turn that starts with "<" is a command wrapper or a notification, not the human.
  jq -r --arg from "${from:0:19}" --arg to "${to:0:19}" '
    select(.type == "user" and .isMeta != true and .isSidechain != true)
    | select((.timestamp // "")[0:19] >= $from and (.timestamp // "")[0:19] <= $to)
    | .timestamp[11:19] as $at
    | .message.content
    | if type == "string" then . else map(select(.type == "text") | .text) | join(" ") end
    | select(length > 0 and (startswith("<") | not))
    | $at + "  " + (gsub("\\s+"; " ") | .[0:400])
  ' "$transcript" 2>/dev/null || true
done <<< "$controllers" | section "Human turns"

query '
  map(select(.ev == "refusal")) | group_by(.reason[0:60])
  | sort_by(-length)[] | [(length | tostring), (.[0].tool // "stop"), .[0].reason[0:140]] | @tsv
' | table | section Refusals

query '
  map(select(.ev == "gate_step")) | group_by(.step)[]
  | select(any(.ok == false))
  | [.[0].step, "\(map(select(.ok == false)) | length) of \(length) failed"] | @tsv
' | table | section "Gate failures"

query '
  map(select(.ev == "tool_end" and .ok == false)) | group_by(.tool)
  | sort_by(-length)[] | [(length | tostring), (.[0].tool // "unknown"), ((.[0].error // "") | gsub("\\s+"; " ") | .[0:100])] | @tsv
' | table | section "Failed tool calls"

{
  while IFS= read -r transcript; do
    [ -f "$transcript" ] && printf '%s\tcontroller\t%s\n' "$(wc -l < "$transcript" | tr -d ' ')" "$transcript"
  done <<< "$controllers"
  query '
    map(select(.agent != null)) | group_by(.agent)[]
    | [(map(.agent_type // empty)[0] // "general-purpose"), (map(.agent_transcript // empty)[0] // "")] | @tsv
  ' | while IFS=$'\t' read -r seat transcript; do
    transcript="${transcript/#\~/$HOME}"
    [ -f "$transcript" ] && printf '%s\t%s\t%s\n' "$(wc -l < "$transcript" | tr -d ' ')" "$seat" "$transcript"
  done | sort -rn
} | table | section "Transcripts, lines and seat, longest agent first"
