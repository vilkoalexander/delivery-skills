#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
check="$here/revert-check.sh"

# The "runner" is bash and each "test" is a script: it passes when it exits 0.
export TEST_CMD=bash

new_repo project
mkdir test
echo 'echo 1' > price.sh
echo 'old' > gone.txt
commit_all
echo 'echo 2' > price.sh
echo 'echo 3' > "new file.sh"
rm gone.txt
echo '[ "$(bash price.sh)" = 2 ] && [ -f "new file.sh" ] && [ ! -f gone.txt ]' > test/price.sh

tree() {
  (source "$here/../../delivery-pipeline/scripts/lib/changes.sh"; worktree_tree)
}
before=$(tree)

echo "# tests that fail without the change"
has "pass the check" 0 '^revert check: every changed test fails without the change \(1 file\(s\)\)$' bash "$check"
eq  "the tree is as it was: changed, added and deleted files" "$(tree)" "$before"
git add price.sh
has "a staged change is reverted too" 0 'every changed test fails' bash "$check"
git reset -q

echo "# a test that passes either way"
echo 'true' > test/always.sh
before=$(tree)
out=$(bash "$check" 2>&1); code=$?
eq     "fails the check"                "$code" 1
sees   "names the test"                 '^  test/always.sh$' "$out"
misses "not the one that does its job"  '^  test/price.sh$' "$out"
eq     "the tree is as it was"          "$(tree)" "$before"
rm test/always.sh

echo "# a runner that cannot run is not a failing test"
has "the runner fails with the change" 2 'could not check — these tests do not pass with the change' env TEST_CMD=false bash "$check"
has "the runner does not exist"        2 'could not check'                                             env TEST_CMD=no-such-runner bash "$check"
eq  "the tree was not touched"         "$(cat price.sh)" "echo 2"
has "no runner rule: said, not failed" 0 '^revert check: n/a — no runner rule' env -u TEST_CMD bash "$check"

echo "# a test command that breaks the tree"
cat > "$tmp/vandal.sh" <<'EOF'
bash "$1" || { echo junk > stray.txt; exit 1; }
EOF
has "a tree that cannot be put back exits 3" 3 'RESTORE FAILED' env TEST_CMD="bash $tmp/vandal.sh" bash "$check"
rm -f stray.txt

echo "# nothing to check"
has "no changed test"   0 '^revert check: n/a — no changed test file$' bash "$check" price.sh
has "no changed source" 0 '^revert check: n/a — no changed file that is not a test' bash "$check" test/price.sh

echo "# the base"
base=$(tree)
echo 'echo 4' > price.sh
echo '[ "$(bash price.sh)" = 4 ]' > test/later.sh
has "DELIVERY_BASE: only the change after it is reverted" 0 'every changed test fails without the change \(1 file' env DELIVERY_BASE="$base" bash "$check"

finish
