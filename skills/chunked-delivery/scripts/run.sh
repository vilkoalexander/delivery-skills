#!/usr/bin/env bash
# Marks a delivery run on this checkout. While the marker exists the plugin's
# hooks (hooks/guard.sh) refuse git writes and snapshot reads in this session.
#
#   bash scripts/run.sh start    # at preflight
#   bash scripts/run.sh stop     # at handoff, or to free a checkout after a crash
#   bash scripts/run.sh status   # exit 1 when no run is active here
set -euo pipefail
cmd=${1:-status}
here=$(cd "$(dirname "$0")" && pwd)
run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
hash() { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12; }
id=$(printf '%s' "$root" | hash)
marker="$run_dir/$id"

case $cmd in
  start)
    mkdir -p "$run_dir"
    if [ ! -f "$marker" ]; then
      printf '{"project":"%s","started":"%s","run":"%s"}\n' "$root" "$(date -u +%FT%TZ)" "$id-$(date -u +%Y%m%dT%H%M%SZ)" > "$marker"
      bash "$here/event.sh" run run_start project="$root" branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)" || true
    fi
    echo "run active on $root"
    ;;
  stop)
    bash "$here/event.sh" run run_stop || true
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
