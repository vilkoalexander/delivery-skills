#!/usr/bin/env bash
# Records one step of the loop in the event file of the run, when the loop
# permits it. lifecycle.mjs holds the rules and its message says what to do.
#
#   bash mark.sh phase=<phase> chunk=N of=M [name=<text>] [risk=<class>] [plan=<path>] [round=N] [parked=<reason>]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
source "$here/lib/run.sh"
run_locate

node "$here/lifecycle.mjs" parse "$@" || exit 2
if ! run_active; then
  echo "mark: no run on $run_root. Start one first: bash $here/run.sh start" >&2
  exit 2
fi

fields=()
while IFS= read -r field; do
  fields+=("$field")
done < <(LIFECYCLE_MODE=$(run_field mode) node "$here/lifecycle.mjs" check "$(run_events_file)" "$@" || echo refused)
[ "${fields[${#fields[@]}-1]}" != refused ] || exit 2

bash "$here/event.sh" mark mark "${fields[@]}"
