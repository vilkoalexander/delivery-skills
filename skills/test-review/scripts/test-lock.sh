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
is_test='(\.(spec|test)\.[cm]?[jt]sx?$|(^|/)(__tests__|test|tests|e2e)/)'
assertion='\b(expect|assert)[.(]'
block='\b(it|test|describe)(\.(each|skip|only|todo))?\('
disabled='\b(it|test|describe)\.(skip|only|todo)\(|\bx(it|test|describe)\(|\bf(it|describe)\('

paths=("$@")
if [ ${#paths[@]} -eq 0 ]; then while IFS= read -r l; do [ -n "$l" ] && paths+=("$l"); done; fi
[ ${#paths[@]} -eq 0 ] && { echo "usage: test-lock.sh <path>... (or paths on stdin)" >&2; exit 2; }

count() { grep -E "^$1" <<<"$diff" | grep -vE '^(\+\+\+|---) ' | grep -cE "$2"; }

weakened=(); allowed=()
for p in "${paths[@]}"; do
  [[ "$p" =~ $is_test ]] || continue
  git cat-file -e "$base:$p" 2>/dev/null || continue
  why=()
  if [ ! -f "$p" ]; then
    why+=("deleted")
  else
    diff=$(git diff "$base" -- "$p")
    n=$(count - "$assertion"); [ "$n" -gt 0 ] && why+=("$n assertion line(s) removed or rewritten")
    n=$(( $(count - "$block") - $(count '\+' "$block") )); [ "$n" -gt 0 ] && why+=("$n test block(s) removed")
    n=$(count '\+' "$disabled"); [ "$n" -gt 0 ] && why+=("$n skip/only/todo added")
  fi
  [ ${#why[@]} -eq 0 ] && continue
  line="$p — $(IFS=';'; echo "${why[*]}" | sed 's/;/; /g')"
  if [ -n "$allow" ] && [[ "$p" =~ $allow ]]; then allowed+=("$line"); else weakened+=("$line"); fi
done

[ ${#allowed[@]} -gt 0 ] && { echo "test lock: allowed by TEST_LOCK_ALLOW"; printf '  %s\n' "${allowed[@]}"; }
if [ ${#weakened[@]} -eq 0 ]; then
  echo "test lock: no existing test was weakened"
  exit 0
fi
echo "test lock: ${#weakened[@]} existing test file(s) weakened"
printf '  %s\n' "${weakened[@]}"
echo "Restore them, or stop with BLOCKED and say why the test is wrong."
exit 1
