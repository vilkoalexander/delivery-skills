#!/usr/bin/env bash
# Puts the working tree back to what it was before chunk N. The discarded work
# is kept as a tree and as a patch, so it is not lost.
#
#   redo.sh N        WORKSPACE is the directory of the run's files
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../delivery-pipeline/scripts/lib/changes.sh"
unset DELIVERY_TREE DELIVERY_BASE

die() {
  echo "redo: $1" >&2
  exit 1
}

if [ $# != 1 ] || ! [[ $1 =~ ^[0-9]+$ ]]; then
  echo "usage: redo.sh N    (WORKSPACE is the directory of the run's files)" >&2
  exit 2
fi
[ -n "${WORKSPACE:-}" ] || die "WORKSPACE is not set"
record="$(cd "$WORKSPACE" 2> /dev/null && pwd)/chunk-$1-before.tree"
[ -f "$record" ] || die "no record of the tree before chunk $1: $WORKSPACE/chunk-$1-before.tree"
before=$(cat "$record")
git cat-file -e "$before^{tree}" 2> /dev/null || die "the tree before chunk $1 is gone from the repository: $before"

cd "$(git rev-parse --show-toplevel)"
now=$(worktree_tree) || die "nothing changed"

count=1
while [ -e "${record%-before.tree}-discarded-$count.tree" ]; do count=$((count + 1)); done
discarded=${record%-before.tree}-discarded-$count
printf '%s\n' "$now" > "$discarded.tree"
git update-ref "refs/delivery-skills/$(basename "$discarded")" "$now" 2> /dev/null || true
git diff --binary "$before" "$now" > "$discarded.diff"

paths=()
while IFS= read -r -d '' path; do
  paths+=("$path")
done < <(git diff -z --name-only --no-renames "$before" "$now")
if [ ${#paths[@]} -gt 0 ] && ! restore_paths "$before" "${paths[@]}"; then
  restore_paths "$now" "${paths[@]}" || true
  die "could not put every file back, the work is restored. It is also in $discarded.diff"
fi

echo "back to the tree before chunk $1 (${#paths[@]} files); discarded work saved in $discarded.diff"
echo "to get it back: git apply --binary $discarded.diff"
