#!/usr/bin/env bash
set -uo pipefail

source=${1:-}
event=${2:-}
if [ -z "$source" ] || { [ -z "$event" ] && [ "$source" != file ]; }; then
  echo "usage: event.sh <src> <ev> [key=value | key:=json]..." >&2
  echo "       appends one line to the active run's event file; does nothing outside a run" >&2
  echo "       event.sh file    prints the path of that file; prints nothing outside a run" >&2
  exit 2
fi
shift
[ $# -eq 0 ] || shift

run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
events_dir="${DELIVERY_EVENTS_DIR:-$(dirname "$run_dir")/events}"
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

short_hash() {
  if command -v shasum > /dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12
}

checkout_id=$(printf '%s' "$root" | short_hash)
marker="$run_dir/$checkout_id"
[ -f "$marker" ] || exit 0

if [[ $(< "$marker") =~ \"run\":\"([^\"]+)\" ]]; then
  run=${BASH_REMATCH[1]}
else
  run="$checkout_id-0"
fi

if [ "$source" = file ] && [ -z "$event" ]; then
  printf '%s\n' "$events_dir/$run.jsonl"
  exit 0
fi

# key=value is a string field, key:=value a JSON one (a number, true, an object).
fields=()
for pair in "$@"; do
  case $pair in
    *:=*) fields+=(--argjson "${pair%%:=*}" "${pair#*:=}") ;;
    *=*)  fields+=(--arg "${pair%%=*}" "${pair#*=}") ;;
  esac
done

line=$(EV_RUN="$run" EV_SRC="$source" EV_EV="$event" jq -cn ${fields[@]+"${fields[@]}"} '
  {ts: (now * 1000 | floor / 1000), run: env.EV_RUN, src: env.EV_SRC, ev: env.EV_EV} + $ARGS.named
' 2>/dev/null) || exit 0
[ -n "$line" ] || exit 0

mkdir -p "$events_dir" 2>/dev/null || exit 0
printf '%s\n' "$line" >> "$events_dir/$run.jsonl" 2>/dev/null
exit 0
