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

source "$(dirname "$0")/lib/run.sh"
run_locate
run_active || exit 0
run=$(run_field run)
[ -n "$run" ] || exit 0

if [ "$source" = file ] && [ -z "$event" ]; then
  run_events_file
  echo
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

mkdir -p "$run_events_dir" 2>/dev/null || exit 0
printf '%s\n' "$line" >> "$(run_events_file)" 2>/dev/null
exit 0
