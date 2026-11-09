#!/usr/bin/env bash
set -euo pipefail
die() { echo "redo: $1" >&2; exit 1; }

[ $# = 1 ] || { echo "usage: redo.sh <path>/chunk-N-before.diff" >&2; exit 2; }
before=$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")
case $before in *-before.diff) ;; *) die "expected a chunk-N-before.diff, got $1" ;; esac
[ -f "$before" ] || die "no such snapshot: $1"
[ ! -s "$before" ] || git apply --numstat "$before" >/dev/null 2>&1 || die "not a valid patch, nothing changed: $1"

cd "$(git rev-parse --show-toplevel)"
saved=${before%-before.diff}-discarded.diff

# Snapshots predate fix rounds and are cumulative, so reverse the live tree rather than chunk-N.diff.
git diff --binary > "$saved"
[ ! -s "$saved" ] || git apply -R "$saved"
if [ -s "$before" ] && ! git apply "$before"; then
  git apply "$saved"
  die "before snapshot did not apply, work restored: $1"
fi

git apply --summary "$saved" | sed -n 's/^ create mode [0-9]* //p' | while IFS= read -r path; do
  [ -e "$path" ] || git update-index --force-remove -- "$path"
done

stray=$(git ls-files --others --exclude-standard)
[ -z "$stray" ] || printf 'redo: left in place, not in any snapshot:\n%s\n' "$stray" >&2
echo "back to $(basename "$before"); discarded work saved in $saved"
