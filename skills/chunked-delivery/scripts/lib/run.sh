#!/usr/bin/env bash
# Sourced by the run scripts and the hooks: where a run keeps its state, and
# which run a directory belongs to. One marker per checkout names the run;
# every other file is found from it.
#
#   run_locate [DIR]     sets run_root and run_marker for the checkout DIR is in (default: the current directory)
#   run_active           is there a run on that checkout
#   run_field NAME       a field of the marker: run, project, started, mode, head
#   run_events_file      the event file of the run
#
#   DELIVERY_RUN_DIR     where the markers are (default ~/.claude/delivery-skills/runs)
#   DELIVERY_EVENTS_DIR  where the event files are (default: events/ beside the markers)
#   DELIVERY_LOG         the run log of all projects (default: log.jsonl beside the markers)

run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
run_events_dir="${DELIVERY_EVENTS_DIR:-$(dirname "$run_dir")/events}"
run_log="${DELIVERY_LOG:-$(dirname "$run_dir")/log.jsonl}"
run_root=""
run_marker=""

run_short_hash() {
  if command -v shasum > /dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12
}

run_marker_of() {
  printf '%s/%s' "$run_dir" "$(printf '%s' "$1" | run_short_hash)"
}

run_locate() {
  local dir=${1:-$PWD} parent
  if run_root=$(git -C "$dir" rev-parse --show-toplevel 2> /dev/null); then
    run_marker=$(run_marker_of "$run_root")
    return
  fi
  # Not a git checkout: the run belongs to the nearest directory above that has a marker.
  run_root=$dir
  run_marker=$(run_marker_of "$dir")
  parent=$dir
  while [ ! -f "$(run_marker_of "$parent")" ] && [ "$parent" != / ] && [ -n "$parent" ]; do
    parent=$(dirname "$parent")
  done
  if [ -f "$(run_marker_of "$parent")" ]; then
    run_root=$parent
    run_marker=$(run_marker_of "$parent")
  fi
}

run_active() {
  [ -n "$run_marker" ] && [ -f "$run_marker" ]
}

run_field() {
  jq -r --arg name "$1" '.[$name] // empty' "$run_marker" 2> /dev/null
}

run_events_file() {
  printf '%s/%s.jsonl' "$run_events_dir" "$(run_field run)"
}
