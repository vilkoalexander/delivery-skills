#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
check="$here/revert-check.sh"

# The "runner" is bash and each "test" is a script: it passes when it exits 0.
export TEST_CMD=bash

new_repo project
mkdir test
echo 'echo 1' > price.sh
commit_all
echo 'echo 2' > price.sh
echo '[ "$(bash price.sh)" = 2 ]' > test/price.sh
git add -N test

echo "# tests that fail without the change"
git diff > "$tmp/change.diff"
has "pass the check"                   0 '^revert check: every changed test fails without the change \(1 file\(s\)\)$' bash "$check" "$tmp/change.diff"
eq  "the change is back in the tree"   "$(cat price.sh)" "echo 2"
has "the diff can come on stdin"       0 'every changed test fails' bash -c "git diff | bash '$check' -"

echo "# a test that passes either way"
echo 'true' > test/always.sh
git add -N test
git diff > "$tmp/change.diff"
out=$(bash "$check" "$tmp/change.diff" 2>&1); code=$?
eq     "fails the check"               "$code" 1
sees   "names the test"                '^  test/always.sh$' "$out"
misses "not the one that does its job" '^  test/price.sh$' "$out"
eq     "the change is back in the tree" "$(cat price.sh)" "echo 2"

echo "# nothing to check"
git diff -- price.sh > "$tmp/source-only.diff"
has "a diff with no tests"             0 '^no test files in the diff — nothing to check$' bash "$check" "$tmp/source-only.diff"
git diff -- test > "$tmp/tests-only.diff"
has "a diff with no source"            0 '^no non-test files in the diff — nothing to revert$' bash "$check" "$tmp/tests-only.diff"

echo "# a stale snapshot"
git checkout -q price.sh
has "refuses when the tree no longer has the change" 2 'non-test paths have no working-tree diff — is the snapshot current\?' bash "$check" "$tmp/change.diff"

echo "# input"
has "no argument" 2 '^usage: revert-check.sh <diff-file \| ->$' bash "$check"

finish
