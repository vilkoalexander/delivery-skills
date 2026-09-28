#!/usr/bin/env bash
# Revert check: do the changed tests fail without the change they cover?
#
# Reverses the non-test hunks of a diff in the working tree, runs the test
# files the diff touches, restores the tree, and lists every test file that
# still passed with the code reverted. Those tests do not test the change.
#
#   bash revert-check.sh <diff-file>        # a snapshot from `git diff`
#   git diff | bash revert-check.sh -
#
# Runner is detected from package.json (vitest, jest, node --test, mocha),
# or set TEST_CMD to the command that takes test file paths as arguments.
# The tree is restored on every exit path; it is the same `git apply` the
# delivery loop already uses for redo.
set -uo pipefail

diff="${1:-}"
[ -z "$diff" ] && { echo "usage: revert-check.sh <diff-file | ->" >&2; exit 2; }
tmp=$(mktemp -d)
if [ "$diff" = "-" ]; then cat > "$tmp/all.diff"; else cp "$diff" "$tmp/all.diff"; fi

is_test='(\.(spec|test)\.[cm]?[jt]sx?$|(^|/)(__tests__|test|tests|e2e)/)'
tests=(); src=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [[ "$f" =~ $is_test ]]; then tests+=("$f"); else src+=("$f"); fi
done < <(grep -E '^\+\+\+ b/' "$tmp/all.diff" | sed 's#^+++ b/##')
[ ${#tests[@]} -eq 0 ] && { echo "no test files in the diff — nothing to check"; rm -rf "$tmp"; exit 0; }
[ ${#src[@]} -eq 0 ] && { echo "no non-test files in the diff — nothing to revert"; rm -rf "$tmp"; exit 0; }

# The hunks to reverse: only the non-test paths.
git diff -- "${src[@]}" > "$tmp/src.diff"
[ -s "$tmp/src.diff" ] || { echo "non-test paths have no working-tree diff — is the snapshot current?"; rm -rf "$tmp"; exit 2; }

if [ -z "${TEST_CMD:-}" ]; then
  deps=$(node -e 'const p=require("./package.json");console.log(Object.keys({...p.dependencies,...p.devDependencies}).join(" "))' 2>/dev/null)
  case " $deps " in
    *" vitest "*) TEST_CMD="npx vitest run";;
    *" jest "*)   TEST_CMD="npx jest --runTestsByPath";;
    *" mocha "*)  TEST_CMD="npx mocha";;
    *)            TEST_CMD="node --test";;
  esac
fi

restore() { git apply "$tmp/src.diff" 2>/dev/null || echo "RESTORE FAILED — run: git apply $tmp/src.diff" >&2; }
git apply -R "$tmp/src.diff" || { echo "could not reverse the source hunks" >&2; rm -rf "$tmp"; exit 2; }
trap 'restore' EXIT

still=()
for t in "${tests[@]}"; do
  [ -f "$t" ] || continue                       # test deleted by the diff
  if $TEST_CMD "$t" > "$tmp/out.txt" 2>&1; then still+=("$t"); fi
done

if [ ${#still[@]} -eq 0 ]; then
  echo "revert check: every changed test fails without the change (${#tests[@]} file(s))"
  exit 0
fi
echo "revert check: these tests still PASS with the change reverted — they do not test it:"
printf '  %s\n' "${still[@]}"
exit 1
