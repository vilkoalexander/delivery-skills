#!/usr/bin/env bash
# The state of the working tree at a point of the run, kept as a git tree. The
# real index is never touched, so nothing is staged and a file git does not
# track yet is in the snapshot like any other.
#
#   snapshot.sh before N             record the tree before chunk N (a rebuild keeps the first record)
#   snapshot.sh after N              write chunk-N.diff: what chunk N changed, and nothing of the chunks before it
#   snapshot.sh part N NAME PATH...  write chunk-N-NAME.diff: the same, for these paths only
#   snapshot.sh final                write final.diff: everything the run changed
#   snapshot.sh base N|final         print the tree a diff starts from (the gate takes it as DELIVERY_BASE)
#   snapshot.sh stat N|final         files and lines of that diff, as git --numstat
#
#   WORKSPACE   the directory of the run's files, outside the checkout
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../delivery-pipeline/scripts/lib/changes.sh"
unset DELIVERY_TREE DELIVERY_BASE

die() {
  echo "snapshot: $1" >&2
  exit 2
}

usage() {
  sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p;}' "$0" >&2
  exit 2
}

action=${1:-}
which=${2:-}
[ -n "$action" ] || usage
[ -n "${WORKSPACE:-}" ] || die "WORKSPACE is not set: it is the directory of the run's files"
[ "$action" = final ] || [[ $which =~ ^([0-9]+|final)$ ]] || usage
mkdir -p "$WORKSPACE"
workspace=$(cd "$WORKSPACE" && pwd)
cd "$(git rev-parse --show-toplevel 2> /dev/null)" || die "not in a git checkout"

# A tree no ref points to is removed by git gc; the ref keeps it until the run stops.
keep() {
  printf '%s\n' "$2" > "$workspace/$1.tree"
  git update-ref "refs/delivery-skills/$1" "$2" 2> /dev/null || true
}

tree_of() {
  [ -f "$workspace/$1.tree" ] || die "no record of $1 in $workspace. Run: snapshot.sh before ${1//[^0-9]/}"
  cat "$workspace/$1.tree"
}

base_of() {
  if [ "$1" = final ]; then
    if [ -f "$workspace/run-before.tree" ]; then cat "$workspace/run-before.tree"; else changes_base; fi
  else
    tree_of "chunk-$1-before"
  fi
}

write_diff() { # NAME BASE [PATH...]
  local name=$1 base=$2 now
  shift 2
  now=$(worktree_tree) || exit 2
  keep "$name" "$now"
  git -c core.quotePath=false diff --no-color --no-ext-diff "$base" "$now" -- "$@" > "$workspace/$name.diff"
  echo "$workspace/$name.diff: $(git diff --shortstat "$base" "$now" -- "$@" | sed 's/^ //;s/^$/no change/')"
}

case $action in
  before)
    [ "$which" != final ] || usage
    tree=$(worktree_tree) || exit 2
    [ -f "$workspace/run-before.tree" ] || keep run-before "$tree"
    if [ -f "$workspace/chunk-$which-before.tree" ]; then
      echo "chunk $which already has a before record; it is kept"
    else
      keep "chunk-$which-before" "$tree"
      echo "recorded the tree before chunk $which"
    fi
    ;;
  after)
    base=$(base_of "$which") || exit 2
    write_diff "chunk-$which" "$base"
    ;;
  part)
    name=${3:-}
    [[ $name =~ ^[a-z0-9-]+$ ]] && [ $# -gt 3 ] || usage
    shift 3
    base=$(base_of "$which") || exit 2
    write_diff "chunk-$which-$name" "$base" "$@"
    ;;
  final) write_diff final "$(base_of final)" ;;
  base) base_of "$which" ;;
  stat)
    base=$(base_of "$which") || exit 2
    now=$(worktree_tree) || exit 2
    git -c core.quotePath=false diff --numstat --no-renames "$base" "$now"
    ;;
  *) usage ;;
esac
