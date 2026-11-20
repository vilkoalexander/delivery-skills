#!/usr/bin/env bash
# Test lock: a test that existed before the run is not weakened to make a
# change pass.
#
#   bash test-lock.sh <path>...
#   git diff --name-only | bash test-lock.sh
#
# For each test path that exists at the base ref, fails when the working tree
# deleted it, removed or rewrote an assertion line, removed a test block, or
# added a skip / only / todo. New test files and added tests are never flagged.
#
#   TEST_LOCK_BASE    ref the tests are locked at (default HEAD)
#   TEST_LOCK_ALLOW   regex of test paths a plan task names as changing;
#                     those are listed as allowed and do not fail
set -uo pipefail

base="${TEST_LOCK_BASE:-HEAD}"
allow="${TEST_LOCK_ALLOW:-}"
test_path='(\.(spec|test)\.[cm]?[jt]sx?$|(Test|Tests|IT)\.(java|kt)$|(^|/)(__tests__|test|tests|e2e)/)'
assertion='\b(expect|assert[A-Za-z]*|verify)[.(]'
test_block='\b(it|test|describe)(\.(each|skip|only|todo))?\(|@(Test|ParameterizedTest|RepeatedTest|TestFactory)\b'
disabled_test='\b(it|test|describe)\.(skip|only|todo)\(|\bx(it|test|describe)\(|\bf(it|describe)\(|@(Disabled|Ignore)\b'

paths=("$@")
if [ ${#paths[@]} -eq 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && paths+=("$line")
  done
fi
if [ ${#paths[@]} -eq 0 ]; then
  echo "usage: test-lock.sh <path>... (or paths on stdin)" >&2
  exit 2
fi

# count_lines DIFF SIGN REGEX — how many removed (-) or added (\+) lines of the diff match
count_lines() {
  grep -E "^$2" <<< "$1" | grep -vE '^(\+\+\+|---) ' | grep -cE "$3"
}

# Prints why a test file counts as weakened, reasons joined by "; ". Nothing when it was not.
weakening_of() {
  local path=$1 diff reasons=()
  if [ ! -f "$path" ]; then
    echo "deleted"
    return
  fi

  diff=$(git diff "$base" -- "$path")
  local assertions_removed blocks_removed disabled_added
  assertions_removed=$(count_lines "$diff" - "$assertion")
  blocks_removed=$(( $(count_lines "$diff" - "$test_block") - $(count_lines "$diff" '\+' "$test_block") ))
  disabled_added=$(count_lines "$diff" '\+' "$disabled_test")

  [ "$assertions_removed" -gt 0 ] && reasons+=("$assertions_removed assertion line(s) removed or rewritten")
  [ "$blocks_removed" -gt 0 ] && reasons+=("$blocks_removed test block(s) removed")
  [ "$disabled_added" -gt 0 ] && reasons+=("$disabled_added skip/only/todo added")
  [ ${#reasons[@]} -gt 0 ] || return 0

  local joined
  joined=$(printf '%s; ' "${reasons[@]}")
  echo "${joined%; }"
}

weakened=()
allowed=()
for path in "${paths[@]}"; do
  [[ $path =~ $test_path ]] || continue
  git cat-file -e "$base:$path" 2> /dev/null || continue

  reasons=$(weakening_of "$path")
  [ -n "$reasons" ] || continue

  if [ -n "$allow" ] && [[ $path =~ $allow ]]; then
    allowed+=("$path — $reasons")
  else
    weakened+=("$path — $reasons")
  fi
done

if [ ${#allowed[@]} -gt 0 ]; then
  echo "test lock: allowed by TEST_LOCK_ALLOW"
  printf '  %s\n' "${allowed[@]}"
fi
if [ ${#weakened[@]} -eq 0 ]; then
  echo "test lock: no existing test was weakened"
  exit 0
fi
echo "test lock: ${#weakened[@]} existing test file(s) weakened"
printf '  %s\n' "${weakened[@]}"
echo "Restore them, or stop with BLOCKED and say why the test is wrong."
exit 1
