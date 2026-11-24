#!/usr/bin/env bash
# Test lock: a test that existed before the change is not weakened to make the
# change pass.
#
#   bash test-lock.sh [path...]              default: every changed path
#   git diff --name-only | bash test-lock.sh
#
# For each test path that exists at the base, fails when the change deleted or
# renamed it, removed or rewrote one of its lines, left it with fewer test
# blocks or assertions once comments are taken out, added a skip / only / todo,
# or added a bare `return;`. New test files and added tests are never flagged.
# A change of indent alone is not a change. Exits 2 when it could not look.
#
#   TEST_LOCK_BASE    tree-ish the tests are locked at (default DELIVERY_BASE, else HEAD)
#   TEST_LOCK_ALLOW   ERE of test paths a plan task names as changing;
#                     those are listed as allowed and do not fail
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "test-lock: not a git repository" >&2
  exit 2
fi
cd "$root"
source "$here/../../delivery-pipeline/scripts/lib/changes.sh"

[ -n "${TEST_LOCK_BASE:-}" ] && export DELIVERY_BASE=$TEST_LOCK_BASE
base=$(changes_base)
allow="${TEST_LOCK_ALLOW:-}"
valid_ere TEST_LOCK_ALLOW "$allow" || exit 2
DELIVERY_TREE=$(worktree_tree) || exit 2
export DELIVERY_TREE
load_paths "" "$@" || exit 2

assertion='(^|[^A-Za-z0-9_$])(expect|assert[A-Za-z]*|verify)[.(]|\.andExpect\('
test_block='(^|[^.A-Za-z0-9_$])(it|test|describe)(\.(each|skip|only|todo))?\(|@(Test|ParameterizedTest|RepeatedTest|TestFactory)([^A-Za-z]|$)'
disabled_test='(^|[^.A-Za-z0-9_$])(it|test|describe)\.(skip|only|todo)\(|(^|[^.A-Za-z0-9_$])x(it|test|describe)\(|(^|[^.A-Za-z0-9_$])f(it|describe)\(|@(Disabled|Ignore)([^A-Za-z]|$)'
not_a_test_line='^[-+][[:space:]]*($|//|/\*|\*|import[[:space:]{]|\}[[:space:]]*from[[:space:]]|(const|let|var)[[:space:]].*=[[:space:]]*require\()'

without_comments() {
  perl -0pe 's{/\*.*?\*/}{}gs; s{^\s*//.*$}{}gm'
}

# count_in TREE PATH REGEX — matching lines of the file at that tree, comments taken out
count_in() {
  git show "$1:$2" 2> /dev/null | without_comments | LC_ALL=C grep -acE -- "$3"
}

# count_lines DIFF SIGN REGEX — how many removed (-) or added (\+) lines of the diff match
count_lines() {
  LC_ALL=C grep -aE "^$2" <<< "$1" | LC_ALL=C grep -acE -- "$3"
}

# Prints why a test file counts as weakened, reasons joined by "; ". Nothing when it was not.
weakening_of() {
  local path=$1 diff reasons=()
  if ! git cat-file -e "$DELIVERY_TREE:$path" 2> /dev/null; then
    echo "deleted or renamed"
    return
  fi

  diff=$(changes_diff "" -w -U0 -- "$path" | LC_ALL=C grep -avE '^(\+\+\+|---|diff --git|index|@@) ?')
  local removed assertions blocks disabled returns
  removed=$(LC_ALL=C grep -aE '^-' <<< "$diff" | LC_ALL=C grep -acvE "$not_a_test_line")
  assertions=$(( $(count_in "$base" "$path" "$assertion") - $(count_in "$DELIVERY_TREE" "$path" "$assertion") ))
  blocks=$(( $(count_in "$base" "$path" "$test_block") - $(count_in "$DELIVERY_TREE" "$path" "$test_block") ))
  disabled=$(count_lines "$diff" '\+' "$disabled_test")
  returns=$(count_lines "$diff" '\+' '^\+[[:space:]]*return;?[[:space:]]*$')

  [ "$removed" -gt 0 ] && reasons+=("$removed line(s) removed or rewritten")
  [ "$assertions" -gt 0 ] && reasons+=("$assertions assertion(s) fewer")
  [ "$blocks" -gt 0 ] && reasons+=("$blocks test block(s) fewer")
  [ "$disabled" -gt 0 ] && reasons+=("$disabled skip/only/todo added")
  [ "$returns" -gt 0 ] && reasons+=("$returns bare return added")
  [ ${#reasons[@]} -gt 0 ] || return 0

  local joined
  joined=$(printf '%s; ' "${reasons[@]}")
  echo "${joined%; }"
}

weakened=()
allowed=()
for path in ${paths[@]+"${paths[@]}"}; do
  is_test_path "$path" || continue
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
