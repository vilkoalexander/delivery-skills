#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
script="$here/test-first.sh"

new_repo project
mkdir -p src/orders
echo "export const total = 0" > src/orders/total.ts
echo "it('old', () => expect(1).toBe(1))" > src/orders/old.spec.ts
commit_all
record="$tmp/chunk-1-tests.lock"
locked() { tr '\0' '\n' < "$record.paths"; }

echo "# bad input"
has "no arguments prints usage"       2 "usage: test-first.sh open"          bash "$script"
has "unknown action"                  2 "usage: test-first.sh open"          bash "$script" freeze "$record"
has "check with no record"            2 "no record at"                       bash "$script" check "$record"
has "lock with no open"               2 "Run open before the test authors"   bash "$script" lock "$record"

echo "# open, then the test authors"
echo "export const earlier = 1" > src/orders/earlier.ts
has "open records the tree"           0 "recorded the tree before the tests"         bash "$script" open "$record"
has "no test written is an error"     1 "no changed test file"               bash "$script" lock "$record"
echo "it('sums', () => expect(total([1, 2])).toBe(3))" > src/orders/total.spec.ts
mkdir -p src/orders/__tests__ && echo "export const order = {}" > src/orders/__tests__/fixture.ts
mkdir -p api/src/test/java/shop api/src/main/java/shop
echo "class OrderServiceTest { @Test void sums() { assertEquals(3, total); } }" > api/src/test/java/shop/OrderServiceTest.java
echo "class RefundIT {}" > api/src/main/java/shop/RefundIT.java
has "locks the new test files"        0 "locked 4 test files"                bash "$script" lock "$record"
eq  "a Java test in src/test is locked"   "$(locked | grep -c 'src/test/java/shop/OrderServiceTest.java')" 1
eq  "a Java test by its name is locked"   "$(locked | grep -c 'RefundIT.java')" 1
eq  "an untouched old test is not in the record" "$(locked | grep -c old.spec)" 0
eq  "nor is the file from an earlier chunk" "$(locked | grep -c earlier.ts)" 0

echo "# a test author that writes code"
echo "export const total = () => 3" > src/orders/total.ts
has "a changed source file is named"  1 "not a test: src/orders/total.ts"    bash "$script" lock "$record"
has "the reason says what to do"      1 "a test author writes tests only"    bash "$script" lock "$record"
has "unless the path is allowed"      0 "locked 4 test files"                env TEST_FIRST_ALLOW='orders/total\.ts$' bash "$script" lock "$record"
git checkout -q -- src/orders/total.ts
echo "export const earlier = 2" > src/orders/earlier.ts
has "an earlier file that changed is named" 1 "not a test: src/orders/earlier.ts" bash "$script" lock "$record"
rm src/orders/earlier.ts
has "an earlier file that was removed is named" 1 "not a test: src/orders/earlier.ts" bash "$script" lock "$record"
echo "export const earlier = 1" > src/orders/earlier.ts
has "the tree as it was locks again"  0 "locked 4 test files"                bash "$script" lock "$record"

echo "# a source file moved into a test path"
git mv -k src/orders/total.ts src/orders/total.test.ts 2>/dev/null || mv src/orders/total.ts src/orders/total.test.ts
has "the source file that left is named" 1 "not a test: src/orders/total.ts" bash "$script" lock "$record"
mv src/orders/total.test.ts src/orders/total.ts
git reset -q
has "a bad allow pattern is refused"  2 "TEST_FIRST_ALLOW is not a valid pattern" env TEST_FIRST_ALLOW='(' bash "$script" lock "$record"
eq  "the real index is not touched"   "$(git diff --cached --name-only)" ""

echo "# check"
echo "export const total = (xs: number[]) => xs.reduce((a, b) => a + b, 0)" > src/orders/total.ts
has "code changes pass"               0 "tests are as the test authors left them" bash "$script" check "$record"
has "works from a subdirectory"       0 "tests are as"                       bash -c "cd src/orders && bash '$script' check '$record'"
echo "it('sums', () => expect(total([1, 2])).toBe(4))" > src/orders/total.spec.ts
has "an edited test fails the check"  1 "changed: src/orders/total.spec.ts"  bash "$script" check "$record"
rm api/src/test/java/shop/OrderServiceTest.java
has "a deleted test file is named"    1 "gone: api/src/test/java/shop/OrderServiceTest.java" bash "$script" check "$record"
has "the reason is a decision"        1 "is the test wrong or is the code wrong" bash "$script" check "$record"

echo "# lock again after the test author corrects a test"
has "code from the implementer blocks a new lock" 1 "not a test: src/orders/total.ts" bash "$script" lock "$record"
has "open again, then the new state is the lock" 0 "locked 3 test files"     bash -c "bash '$script' open '$record' >/dev/null && bash '$script' lock '$record'"
has "and the check passes"            0 "tests are as"                       bash "$script" check "$record"

finish
