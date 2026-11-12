#!/usr/bin/env bash
set -uo pipefail
src=${1:-}; ev=${2:-}
if [ -z "$src" ] || [ -z "$ev" ]; then
  echo "usage: event.sh <src> <ev> [key=value | key:=json]..." >&2
  echo "       appends one line to the active run's event file; does nothing outside a run" >&2
  exit 2
fi
shift 2

run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
events_dir="${DELIVERY_EVENTS_DIR:-$(dirname "$run_dir")/events}"
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
hash() { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12; }
id=$(printf '%s' "$root" | hash)
marker="$run_dir/$id"
[ -f "$marker" ] || exit 0

if [[ $(<"$marker") =~ \"run\":\"([^\"]+)\" ]]; then run=${BASH_REMATCH[1]}; else run="$id-0"; fi

args=()
for pair in "$@"; do
  case $pair in
    *:=*) args+=(--argjson "${pair%%:=*}" "${pair#*:=}") ;;
    *=*)  args+=(--arg "${pair%%=*}" "${pair#*=}") ;;
  esac
done

line=$(EV_RUN="$run" EV_SRC="$src" EV_EV="$ev" jq -cn ${args[@]+"${args[@]}"} \
  '{ts: (now * 1000 | floor / 1000), run: env.EV_RUN, src: env.EV_SRC, ev: env.EV_EV} + $ARGS.named' 2>/dev/null) || exit 0
[ -n "$line" ] || exit 0
mkdir -p "$events_dir" 2>/dev/null || exit 0
printf '%s\n' "$line" >> "$events_dir/$run.jsonl" 2>/dev/null
exit 0
