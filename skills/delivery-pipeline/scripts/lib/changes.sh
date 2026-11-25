#!/usr/bin/env bash
# Sourced by the gate scripts: the one answer to "which paths changed", "which
# lines did the change add" and "is this path a test". The caller has already
# cd'ed to the git root. A function that cannot answer returns 2 and says why
# on stderr; no caller reads that as "nothing changed".
#
# The change is always the difference of two trees: the base, and the working
# state as a tree built with a throwaway index. So a deleted file, a staged
# file and a file git does not track yet are all read the same way, and the
# real index is never touched.
#
#   DELIVERY_BASE   tree-ish the change starts from (default HEAD; the delivery
#                   loop sets the tree of the chunk's before-snapshot)
#   DELIVERY_TREE   tree of the working state, when the caller has built it
#
#   worktree_tree                    the working state as a tree id
#   restore_paths TREE PATH...       makes each path in the working tree what it is in TREE
#   changed_paths [RANGE]            NUL-separated paths; without RANGE: base against the working state
#   load_paths RANGE [PATH...]       fills the array `paths` from the arguments, else stdin, else changed_paths
#   added_lines RANGE PATH...        "path:line:text" for each line the change adds
#   is_test_path PATH
#   valid_ere NAME PATTERN           returns 2 when grep -E cannot compile PATTERN
#   config_get KEY                   a value of docs/review/delivery.json; returns 2 when the file is invalid

changes_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# A repository with no commit has no HEAD; the empty tree stands in for it.
changes_base() {
  if [ -n "${DELIVERY_BASE:-}" ]; then
    echo "$DELIVERY_BASE"
  elif git rev-parse -q --verify HEAD > /dev/null 2>&1; then
    echo HEAD
  else
    git hash-object -t tree /dev/null
  fi
}

worktree_tree() {
  if [ -n "${DELIVERY_TREE:-}" ]; then
    echo "$DELIVERY_TREE"
    return
  fi
  local index real tree
  index=$(mktemp)
  real=$(git rev-parse --git-path index)
  # A copy of the real index keeps its stat cache, so only changed files are hashed. It must keep
  # the time of the index too: git hashes again each file that is as new as the index.
  if [ -f "$real" ]; then cp -p "$real" "$index"; else rm -f "$index"; fi
  tree=$(GIT_INDEX_FILE=$index git add -A . > /dev/null 2>&1 && GIT_INDEX_FILE=$index git write-tree 2> /dev/null)
  rm -f "$index" "$index.lock"
  if [ -z "$tree" ]; then
    echo "cannot read the working tree as a git tree (an unfinished merge?)" >&2
    return 2
  fi
  echo "$tree"
}

restore_paths() {
  local tree=$1 index path status=0
  shift
  index=$(mktemp)
  rm -f "$index"
  if ! GIT_INDEX_FILE=$index git read-tree "$tree" 2> /dev/null; then
    echo "cannot read the tree $tree" >&2
    return 2
  fi
  for path in "$@"; do
    if git cat-file -e "$tree:$path" 2> /dev/null; then
      GIT_INDEX_FILE=$index git checkout-index -f -- "$path" || status=2
    else
      rm -f -- "$path"
    fi
  done
  rm -f "$index" "$index.lock"
  return $status
}

# The two ends of the change, as arguments for git diff.
changes_ends() {
  local range=${1:-} tree
  if [ -n "$range" ]; then
    printf '%s\n' "$range"
    return
  fi
  tree=$(worktree_tree) || return 2
  printf '%s\n%s\n' "$(changes_base)" "$tree"
}

# changes_diff RANGE [git diff option...] [-- PATH...]
changes_diff() {
  local range=$1 ends=() end options=()
  shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    options+=("$1")
    shift
  done
  [ $# -gt 0 ] && shift
  while IFS= read -r end; do ends+=("$end"); done < <(changes_ends "$range")
  [ ${#ends[@]} -gt 0 ] || return 2
  git -c core.quotePath=false diff --no-renames --no-color --no-ext-diff ${options[@]+"${options[@]}"} "${ends[@]}" -- "$@"
}

changed_paths() {
  changes_diff "${1:-}" -z --name-only
}

# `git diff --name-only` without -z prints "caf\303\251.ts" for café.ts.
unquote_git_path() {
  local path=$1
  if [[ $path == \"*\" ]]; then
    path=${path#\"}
    path=${path%\"}
    printf '%b' "$path"
  else
    printf '%s' "$path"
  fi
}

load_paths() {
  local range=$1 line listed
  shift
  paths=("$@")
  [ ${#paths[@]} -gt 0 ] && return 0

  # A harness can hand a pipe that never closes; wait one second for each line.
  if [ ! -t 0 ]; then
    while IFS= read -r -t 1 line; do
      [ -n "$line" ] && paths+=("$(unquote_git_path "$line")")
    done
  fi
  [ ${#paths[@]} -gt 0 ] && return 0

  listed=$(mktemp)
  if ! changed_paths "$range" > "$listed" 2> /dev/null; then
    rm -f "$listed"
    echo "cannot list the changed paths${range:+ of $range}" >&2
    return 2
  fi
  while IFS= read -r -d '' line; do
    paths+=("$line")
  done < "$listed"
  rm -f "$listed"
}

added_lines() {
  local range=$1 diff
  shift
  [ $# -gt 0 ] || return 0

  diff=$(changes_diff "$range" -U0 --src-prefix=a/ --dst-prefix=b/ -- "$@" 2> /dev/null) || {
    echo "git diff failed for ${range:-the working tree}" >&2
    return 2
  }

  printf '%s\n' "$diff" | LC_ALL=C awk '
    /^diff --git/ { header = 1; file = ""; next }
    # git ends the header of a path with a space in it with a tab.
    header && /^\+\+\+ b\// { file = substr($0, 7); sub(/\t$/, "", file); next }
    /^@@/         { header = 0; split($3, hunk, /[,+]/); line = hunk[2] - 1; next }
    header        { next }
    /^\+/         { line++; if (file != "" && length($0) > 1) print file ":" line ":" substr($0, 2); next }
    /^-/          { next }
                  { line++ }
  '
}

test_path_ere='[.-](spec|test)\.|(^|/)(__tests__|__mocks__|__fixtures__|__snapshots__|fixtures|testFixtures|tests?|e2e|cypress|playwright)/|(^|/)src/test/|(Tests?|IT)\.(java|kt)$|_test\.go$'

is_test_path() {
  [[ $1 =~ $test_path_ere ]]
}

valid_ere() {
  local status
  printf '' | LC_ALL=C grep -E -- "$2" > /dev/null 2>&1
  status=$?
  [ "$status" -le 1 ] && return 0
  echo "$1 is not a valid pattern (POSIX ERE): $2" >&2
  return 2
}

config_get() {
  node "$changes_lib_dir/../config.mjs" get "$1"
}
