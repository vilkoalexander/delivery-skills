#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "redo: $1" >&2
  exit 1
}

is_valid_patch() {
  git apply --numstat "$1" > /dev/null 2>&1
}

if [ $# != 1 ]; then
  echo "usage: redo.sh <path>/chunk-N-before.diff" >&2
  exit 2
fi
before=$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")
[[ $before == *-before.diff ]] || die "expected a chunk-N-before.diff, got $1"
[ -f "$before" ] || die "no such snapshot: $1"
# An empty snapshot is valid: the chunk started from a clean tree.
[ ! -s "$before" ] || is_valid_patch "$before" || die "not a valid patch, nothing changed: $1"

cd "$(git rev-parse --show-toplevel)"
discarded=${before%-before.diff}-discarded.diff

# Snapshots predate fix rounds and are cumulative, so reverse the live tree rather than chunk-N.diff.
git diff --binary > "$discarded"
[ ! -s "$discarded" ] || git apply -R "$discarded"
if [ -s "$before" ] && ! git apply "$before"; then
  git apply "$discarded"
  die "before snapshot did not apply, work restored: $1"
fi

# Files the discarded work created are gone from disk; drop their intent-to-add entries too.
git apply --summary "$discarded" | sed -n 's/^ create mode [0-9]* //p' | while IFS= read -r path; do
  [ -e "$path" ] || git update-index --force-remove -- "$path"
done

untracked=$(git ls-files --others --exclude-standard)
if [ -n "$untracked" ]; then
  printf 'redo: left in place, not in any snapshot:\n%s\n' "$untracked" >&2
fi
echo "back to $(basename "$before"); discarded work saved in $discarded"
