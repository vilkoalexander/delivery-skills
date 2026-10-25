#!/usr/bin/env bash
# Marks a delivery run on this checkout. While the marker exists the plugin's
# hooks (hooks/guard.sh) refuse git writes and snapshot reads in this session.
#
#   bash scripts/run.sh start    # at preflight
#   bash scripts/run.sh stop     # at handoff, or to free a checkout after a crash
#   bash scripts/run.sh status   # exit 1 when no run is active here
set -euo pipefail
cmd=${1:-status}
run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
hash() { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12; }
marker="$run_dir/$(printf '%s' "$root" | hash)"

case $cmd in
  start)
    mkdir -p "$run_dir"
    [ -f "$marker" ] || printf '{"project":"%s","started":"%s"}\n' "$root" "$(date -u +%FT%TZ)" > "$marker"
    echo "run active on $root"
    ;;
  stop)
    rm -f "$marker"
    echo "run ended on $root"
    ;;
  status)
    if [ -f "$marker" ]; then cat "$marker"; else echo "no run on $root"; exit 1; fi
    ;;
  *)
    echo "usage: run.sh start|stop|status" >&2
    exit 2
    ;;
esac
