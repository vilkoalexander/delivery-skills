#!/usr/bin/env bash
# Marks a delivery run on this checkout. While the marker exists the plugin's
# hooks (hooks/guard.sh) refuse git writes and snapshot reads in this session.
#
#   bash scripts/run.sh start            at preflight; refuses when a run is active already
#   bash scripts/run.sh start --resume   go on with the run that is active (after a crash or a new session)
#   bash scripts/run.sh mode gated|long  after the human approved the cut: stop after each chunk, or not
#   bash scripts/run.sh status           the run and where each chunk is; exit 1 when no run is active here
#   bash scripts/run.sh stop             at handoff, or to free a checkout after a crash
set -euo pipefail

action=${1:-status}
here=$(cd "$(dirname "$0")" && pwd)
source "$here/lib/run.sh"
run_locate

event() {
  bash "$here/event.sh" run "$@" || true
}

need() {
  command -v "$1" > /dev/null 2>&1 && return 0
  echo "run: $1 is not on PATH. The hooks and the gate cannot work without it, so no run starts." >&2
  exit 2
}

say_writing() {
  local writing
  writing=$(node "$here/../../delivery-pipeline/scripts/config.mjs" get writing 2>/dev/null || echo ste100)
  if [ "$writing" = free ]; then
    echo "writing: free"
  else
    echo "writing: $writing. Read references/writing.md now. All text for a person obeys it."
  fi
}

# Event files of runs that ended long ago hold command text nobody reads again.
prune_old_events() {
  [ -d "$run_events_dir" ] || return 0
  find "$run_events_dir" -name '*.jsonl' -mtime +"${DELIVERY_EVENTS_KEEP_DAYS:-30}" -delete 2> /dev/null || true
}

case $action in
  start)
    need jq
    need node
    mkdir -p "$run_dir"
    if run_active; then
      if [ "${2:-}" != --resume ]; then
        echo "run: a run is active on $run_root already (started $(run_field started), run $(run_field run))." >&2
        echo "     To go on with it: run.sh start --resume. To end it: run.sh stop." >&2
        exit 2
      fi
      echo "run resumed on $run_root"
      node "$here/lifecycle.mjs" status "$(run_events_file)"
    else
      checkout_id=$(basename "$run_marker")
      jq -cn --arg project "$run_root" --arg started "$(date -u +%FT%TZ)" \
        --arg run "$checkout_id-$(date -u +%Y%m%dT%H%M%SZ)" \
        --arg head "$(git rev-parse -q --verify HEAD 2>/dev/null || echo none)" \
        '{project: $project, started: $started, run: $run, mode: "gated", head: $head}' > "$run_marker"
      prune_old_events
      event run_start project="$run_root" branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)"
      echo "run active on $run_root"
    fi
    say_writing
    ;;
  mode)
    run_active || { echo "run: no run on $run_root" >&2; exit 1; }
    [[ ${2:-} =~ ^(gated|long)$ ]] || { echo "usage: run.sh mode gated|long" >&2; exit 2; }
    updated=$(jq -c --arg mode "$2" '.mode = $mode' "$run_marker")
    printf '%s\n' "$updated" > "$run_marker"
    event run_mode mode="$2"
    echo "mode: $2"
    ;;
  stop)
    event run_stop
    rm -f "$run_marker"
    git for-each-ref --format='%(refname)' refs/delivery-skills 2> /dev/null | while IFS= read -r ref; do
      git update-ref -d "$ref" 2> /dev/null || true
    done
    echo "run ended on $run_root"
    ;;
  status)
    if ! run_active; then
      echo "no run on $run_root"
      exit 1
    fi
    cat "$run_marker"
    head_now=$(git rev-parse -q --verify HEAD 2>/dev/null || echo none)
    [ "$head_now" = "$(run_field head)" ] || echo "HEAD moved since the run started: $(run_field head) -> $head_now"
    node "$here/lifecycle.mjs" status "$(run_events_file)"
    ;;
  *)
    echo "usage: run.sh start [--resume] | mode gated|long | status | stop" >&2
    exit 2
    ;;
esac
