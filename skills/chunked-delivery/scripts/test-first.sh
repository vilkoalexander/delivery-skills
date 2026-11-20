#!/usr/bin/env bash
set -euo pipefail

test_path='(\.(spec|test)\.[cm]?[jt]sx?$|(Test|Tests|IT)\.(java|kt)$|(^|/)(__tests__|test|tests|e2e)/)'
allow="${TEST_FIRST_ALLOW:-}"

usage() {
  echo "usage: test-first.sh open <file>     before the test authors: record the tree as it is" >&2
  echo "       test-first.sh lock <file>     after them: fail if a file that is not a test changed; record the tests" >&2
  echo "       test-first.sh check <file>    after the implementers: fail if a recorded test changed" >&2
  echo "       TEST_FIRST_ALLOW   regex of paths that are not tests and that a test author can change" >&2
  exit 2
}

state_of() {
  if [ -f "$1" ]; then git hash-object -- "$1"; else echo gone; fi
}

# hash and path of each file that differs from HEAD, new files included
changed_files() {
  local path
  git add -N . > /dev/null
  git diff --name-only HEAD | while IFS= read -r path; do
    printf '%s\t%s\n' "$(state_of "$path")" "$path"
  done
}

action=${1:-}
record=${2:-}
[ -n "$record" ] || usage
mkdir -p "$(dirname "$record")"
record="$(cd "$(dirname "$record")" && pwd)/$(basename "$record")"
before="$record.before"
cd "$(git rev-parse --show-toplevel)"

case $action in
  open)
    changed_files > "$before"
    echo "test-first: recorded $(wc -l < "$before" | tr -d ' ') changed files before the tests"
    ;;
  lock)
    [ -f "$before" ] || { echo "test-first: no record of the tree before the tests. Run open before the test authors." >&2; exit 2; }
    now=$(changed_files)
    : > "$record"
    stray=0
    while IFS=$'\t' read -r hash path; do
      [ -n "$path" ] || continue
      if [[ $path =~ $test_path ]]; then
        [ "$hash" = gone ] || printf '%s\t%s\n' "$hash" "$path" >> "$record"
      elif [ -n "$allow" ] && [[ $path =~ $allow ]]; then
        continue
      elif ! grep -qxF "$hash"$'\t'"$path" "$before"; then
        echo "not a test: $path"
        stray=1
      fi
    done <<< "$now"
    # A file that was changed before the tests and is clean now was put back to HEAD by a test author.
    while IFS=$'\t' read -r hash path; do
      [[ $path =~ $test_path ]] && continue
      grep -qF $'\t'"$path" <<< "$now" || { echo "not a test: $path"; stray=1; }
    done < "$before"
    if [ "$stray" = 1 ]; then
      echo "test-first: a test author writes tests only. Have the file put back, or name it in TEST_FIRST_ALLOW." >&2
      exit 1
    fi
    if [ ! -s "$record" ]; then
      echo "test-first: no changed test file. The test authors wrote none." >&2
      exit 1
    fi
    echo "test-first: locked $(wc -l < "$record" | tr -d ' ') test files"
    ;;
  check)
    [ -f "$record" ] || { echo "test-first: no record at $record. Run lock after the test authors." >&2; exit 2; }
    changed=0
    while IFS=$'\t' read -r hash path; do
      now=$(state_of "$path")
      [ "$now" = "$hash" ] && continue
      if [ "$now" = gone ]; then echo "gone: $path"; else echo "changed: $path"; fi
      changed=1
    done < "$record"
    if [ "$changed" = 1 ]; then
      echo "test-first: the implementer does not edit a test. Decide: is the test wrong or is the code wrong?" >&2
      exit 1
    fi
    echo "test-first: the tests are as the test authors left them"
    ;;
  *) usage ;;
esac
