#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../delivery-pipeline/scripts/lib/changes.sh"
unset DELIVERY_TREE DELIVERY_BASE

allow="${TEST_FIRST_ALLOW:-}"

usage() {
  echo "usage: test-first.sh open <file>     before the test authors: record the tree as it is" >&2
  echo "       test-first.sh lock <file>     after them: fail if a file that is not a test changed; record the tests" >&2
  echo "       test-first.sh check <file>    after the implementers: fail if a recorded test changed" >&2
  echo "       TEST_FIRST_ALLOW   regex of paths that are not tests and that a test author can change" >&2
  exit 2
}

action=${1:-}
record=${2:-}
[ -n "$record" ] || usage
[ -z "$allow" ] || valid_ere TEST_FIRST_ALLOW "$allow" || exit 2
mkdir -p "$(dirname "$record")"
record="$(cd "$(dirname "$record")" && pwd)/$(basename "$record")"
before="$record.before"
tests="$record.paths"
cd "$(git rev-parse --show-toplevel)"

now_tree() {
  worktree_tree || { echo "test-first: cannot read the working tree" >&2; exit 2; }
}

case $action in
  open)
    now_tree > "$before"
    echo "test-first: recorded the tree before the tests"
    ;;
  lock)
    [ -f "$before" ] || { echo "test-first: no record of the tree before the tests. Run open before the test authors." >&2; exit 2; }
    now=$(now_tree)
    # Tests locked before a test author came back stay locked.
    earlier=()
    if [ -f "$tests" ]; then
      while IFS= read -r -d '' path; do
        git cat-file -e "$now:$path" 2> /dev/null && earlier+=("$path")
      done < "$tests"
    fi
    found=$(mktemp)
    [ ${#earlier[@]} -eq 0 ] || printf '%s\0' "${earlier[@]}" > "$found"
    stray=0
    # A rename is a delete and an add here, so a source file moved into a test path is named.
    while IFS= read -r -d '' path; do
      if is_test_path "$path"; then
        git cat-file -e "$now:$path" 2> /dev/null || continue
        printf '%s\0' "$path" >> "$found"
      elif [ -n "$allow" ] && [[ $path =~ $allow ]]; then
        continue
      else
        echo "not a test: $path"
        stray=1
      fi
    done < <(git diff -z --name-only --no-renames "$(cat "$before")" "$now")
    if [ "$stray" = 1 ]; then
      rm -f "$found"
      echo "test-first: a test author writes tests only. Have the file put back, or name it in TEST_FIRST_ALLOW." >&2
      exit 1
    fi
    if [ ! -s "$found" ]; then
      rm -f "$found"
      echo "test-first: no changed test file. The test authors wrote none." >&2
      exit 1
    fi
    LC_ALL=C sort -zu "$found" > "$tests"
    rm -f "$found"
    locked=$(tr -cd '\0' < "$tests" | wc -c | tr -d ' ')
    printf '%s\n' "$now" > "$record"
    echo "test-first: locked $locked test files"
    ;;
  check)
    [ -f "$record" ] && [ -f "$tests" ] || { echo "test-first: no record at $record. Run lock after the test authors." >&2; exit 2; }
    locked=()
    while IFS= read -r -d '' path; do locked+=("$path"); done < "$tests"
    now=$(now_tree)
    changed=0
    while IFS= read -r -d '' path; do
      if git cat-file -e "$now:$path" 2> /dev/null; then echo "changed: $path"; else echo "gone: $path"; fi
      changed=1
    done < <(git diff -z --name-only --no-renames "$(cat "$record")" "$now" -- "${locked[@]}")
    if [ "$changed" = 1 ]; then
      echo "test-first: the implementer does not edit a test. Decide: is the test wrong or is the code wrong?" >&2
      exit 1
    fi
    echo "test-first: the tests are as the test authors left them"
    ;;
  *) usage ;;
esac
