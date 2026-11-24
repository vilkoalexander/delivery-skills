#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
script="$here/test-lock.sh"

spec() {
  cat > "$1" <<'EOF'
import { total } from './total';
describe('total', () => {
  it('adds', () => {
    expect(total([1, 2])).toBe(3);
  });
  it('handles empty', () => {
    expect(
      total([]),
    ).toBe(0);
  });
});
EOF
}

java_test() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
class OrderServiceTest {
  @Test
  void adds() {
    assertEquals(3, service.total(List.of(1, 2)));
  }
  @Test
  void savesTheOrder() {
    verify(repository).save(order);
    mvc.perform(get("/orders"))
      .andExpect(status().isOk());
  }
}
EOF
}

new_repo project
mkdir -p src
for f in a b c d e; do spec "src/$f.spec.ts"; done
echo 'export const total = (n) => n.reduce((x, y) => x + y, 0);' > src/total.ts
java_test api/src/test/java/shop/OrderServiceTest.java
java_test api/src/main/java/shop/RefundIT.java
commit_all

reset() {
  git reset -q --hard && git clean -qfd
}

# edit FILE PERL — rewrites the file in place
edit() {
  perl -0pi -e "$2" "$1"
}

clean="no existing test was weakened"
spec=src/a.spec.ts
junit=api/src/test/java/shop/OrderServiceTest.java

echo "# what passes"
has "untouched tests" 0 "$clean" bash "$script" $spec src/total.ts
edit $spec 's/^\}\);$/  it("adds three", () => {\n    expect(total([1, 2, 3])).toBe(6);\n  });\n});/m'
has "added tests" 0 "$clean" bash "$script" $spec
reset
edit $spec 's/^import .*/import { total, other } from ".\/total";/'
has "a changed import" 0 "$clean" bash "$script" $spec
reset
{ echo "describe('outer', () => {"; sed 's/^/  /' $spec; echo "});"; } > "$tmp/wrapped" && cp "$tmp/wrapped" $spec
has "a change of indent alone" 0 "$clean" bash "$script" $spec
reset
spec src/new.spec.ts
has "a new test file" 0 "$clean" bash "$script" src/new.spec.ts
reset
echo 'const r = model.fit(data);' >> $spec
has "model.fit( is not a focused test" 0 "$clean" bash "$script" $spec
reset
edit src/total.ts 's/x \+ y/x - y/'
has "a source change" 0 "$clean" bash "$script" src/total.ts
reset

echo "# what fails"
edit $spec 's/toBe\(3\)/toBe(4)/'
has "a rewritten assertion" 1 "$spec — 1 line\(s\) removed or rewritten" bash "$script" $spec
has "the same, from the changed paths" 1 "$spec" bash "$script"
has "the same, with paths on stdin" 1 "$spec" bash -c "git diff --name-only | bash '$script'"
has "an allowed path passes and is listed" 0 "allowed by TEST_LOCK_ALLOW" env TEST_LOCK_ALLOW='src/a\.spec' bash "$script" $spec
has "allow does not cover other paths" 1 "weakened" env TEST_LOCK_ALLOW='src/b\.spec' bash "$script" $spec
reset
edit $spec 's/total\(\[\]\),/total([0]),/'
has "a changed value on a continuation line" 1 "1 line\(s\) removed or rewritten" bash "$script" $spec
reset
edit $spec "s/it\('handles empty'/it.skip('handles empty'/"
has "an added skip" 1 "1 skip/only/todo added" bash "$script" $spec
reset
edit $spec 's/  it\(.handles empty.*?\n  \}\);\n//s'
has "a removed test" 1 "1 test block\(s\) fewer" bash "$script" $spec
reset
edit $spec "s/  it\('handles empty'/  \/*\n  it('handles empty'/; s/^\}\);\$/  *\/\n});/m"
has "a test inside a block comment" 1 "1 test block\(s\) fewer" bash "$script" $spec
reset
edit $spec "s/it\('adds', \(\) => \{\n/it('adds', () => {\n    return;\n/"
has "a bare return at the top of a test" 1 "1 bare return added" bash "$script" $spec
reset
rm $spec
has "a deleted test file" 1 "$spec — deleted or renamed" bash "$script" $spec
has "the same, from the changed paths" 1 "$spec — deleted or renamed" bash "$script"
reset
git mv $spec src/a.ts
has "a test file renamed out of its test name" 1 "$spec — deleted or renamed" bash "$script"
reset

echo "# JUnit"
edit $junit 's/assertEquals\(3,/assertEquals(4,/'
has "a rewritten assertion" 1 "OrderServiceTest.java — 1 line\(s\) removed or rewritten" bash "$script" $junit
reset
edit $junit 's/\n      \.andExpect\(status\(\)\.isOk\(\)\);/;/'
has "a removed andExpect" 1 "1 assertion\(s\) fewer" bash "$script" $junit
reset
edit $junit 's/  \@Test\n  void savesTheOrder.*?\n  \}\n//s'
has "a removed test method" 1 "1 test block\(s\) fewer" bash "$script" $junit
reset
edit $junit 's/  void adds/  \@Disabled void adds/'
has "an added \@Disabled" 1 "1 skip/only/todo added" bash "$script" $junit
reset
named=api/src/main/java/shop/RefundIT.java
edit $named 's/assertEquals\(3,/assertEquals(4,/'
has "a Java test outside a test directory is locked by its name" 1 "RefundIT.java" bash "$script" $named
reset

echo "# the base"
edit $spec 's/toBe\(3\)/toBe(4)/'
base=$(source "$here/../../delivery-pipeline/scripts/lib/changes.sh"; worktree_tree)
has "TEST_LOCK_BASE: a change before the base is not this change's" 0 "$clean" env TEST_LOCK_BASE="$base" bash "$script" $spec
has "DELIVERY_BASE does the same" 0 "$clean" env DELIVERY_BASE="$base" bash "$script" $spec
reset

echo "# it says so when it cannot look"
has "an allow pattern that does not compile" 2 "TEST_LOCK_ALLOW is not a valid pattern" env TEST_LOCK_ALLOW='(' bash "$script" $spec
mkdir -p "$tmp/plain" && cd "$tmp/plain"
has "outside git" 2 "not a git repository" env GIT_CEILING_DIRECTORIES="$tmp" bash "$script" a.spec.ts

finish
