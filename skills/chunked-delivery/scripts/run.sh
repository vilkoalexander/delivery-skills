#!/usr/bin/env bash
# Marks a delivery run on this checkout. While the marker exists the plugin's
# hooks (hooks/guard.sh) refuse git writes and snapshot reads in this session.
#
#   bash scripts/run.sh start    # at preflight
#   bash scripts/run.sh stop     # at handoff, or to free a checkout after a crash
#   bash scripts/run.sh status   # exit 1 when no run is active here
set -euo pipefail
set -euo pipefail

action=${1:-status}
here=$(cd "$(dirname "$0")" && pwd)
run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

short_hash() {
  if command -v shasum > /dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12
}

checkout_id=$(printf '%s' "$root" | short_hash)
marker="$run_dir/$checkout_id"

event() {
  bash "$here/event.sh" run "$@" || true
}

case $action in
  start)
    mkdir -p "$run_dir"
    if [ ! -f "$marker" ]; then
      started=$(date -u +%FT%TZ)
      run_id="$checkout_id-$(date -u +%Y%m%dT%H%M%SZ)"
      branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)
      printf '{"project":"%s","started":"%s","run":"%s"}\n' "$root" "$started" "$run_id" > "$marker"
      event run_start project="$root" branch="$branch"
    fi
    echo "run active on $root"
    writing=$(node "$here/../../delivery-pipeline/scripts/config.mjs" get writing 2>/dev/null || echo ste100)
    if [ "$writing" = free ]; then
      echo "writing: free"
    else
      echo "writing: $writing. Read references/writing.md now. All text for a person obeys it."
    fi
    ;;
  stop)
    event run_stop
    rm -f "$marker"
    echo "run ended on $root"
    ;;
  status)
    if [ ! -f "$marker" ]; then
      echo "no run on $root"
      exit 1
    fi
    cat "$marker"
    ;;
  *)
    echo "usage: run.sh start|stop|status" >&2
    exit 2
    ;;
esac
