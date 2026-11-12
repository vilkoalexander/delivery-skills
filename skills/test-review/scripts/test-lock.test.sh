#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/test-lock.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/src" && git -C "$repo" init -q
cd "$repo" || exit 1

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1" "got '$2', wanted '$3'"; fi; }
has() { if grep -q "$2" "$tmp/out"; then ok "$1"; else nok "$1" "no '$2' in: $(cat "$tmp/out")"; fi; }

spec() {
  cat > "$1" <<'EOF'
import { total } from './total';
describe('total', () => {
  it('adds', () => {
    expect(total([1, 2])).toBe(3);
  });
  it('handles empty', () => {
    expect(total([])).toBe(0);
  });
});
EOF
}
reset() { git checkout -q -- . && git clean -qfd; }
run() { bash "$script" "$@" > "$tmp/out" 2>&1; echo $?; }

for f in a b c d e; do spec "src/$f.spec.ts"; done
echo 'export const total = (n) => n.reduce((x, y) => x + y, 0);' > src/total.ts
git add . && git -c user.name=t -c user.email=t@t commit -qm base

eq "untouched tests pass" "$(run src/a.spec.ts src/total.ts)" 0

sed -i.bak 's/toBe(3)/toBe(4)/' src/a.spec.ts && rm src/a.spec.ts.bak
eq "rewritten assertion fails" "$(run src/a.spec.ts)" 1
has "names the rewritten assertion" "src/a.spec.ts — 1 assertion line(s) removed or rewritten"
reset

sed -i.bak "s/it('handles empty'/it.skip('handles empty'/" src/b.spec.ts && rm src/b.spec.ts.bak
eq "added skip fails" "$(run src/b.spec.ts)" 1
has "names the skip" "1 skip/only/todo added"
reset

sed -i.bak '6,8d' src/c.spec.ts && rm src/c.spec.ts.bak
eq "removed test fails" "$(run src/c.spec.ts)" 1
has "names the removed block" "1 test block(s) removed"
reset

rm src/d.spec.ts
eq "deleted test file fails" "$(run src/d.spec.ts)" 1
has "names the deletion" "src/d.spec.ts — deleted"
reset

sed -i.bak "s/^});$/  it('adds three', () => {\n    expect(total([1, 2, 3])).toBe(6);\n  });\n});/" src/e.spec.ts && rm src/e.spec.ts.bak
printf "it('one more', () => { expect(1).toBe(1); });\n" >> src/e.spec.ts
eq "added tests pass" "$(run src/e.spec.ts)" 0
reset

spec src/new.spec.ts
eq "new test file is not locked" "$(run src/new.spec.ts)" 0
reset

sed -i.bak 's/x + y/x - y/' src/total.ts && rm src/total.ts.bak
eq "source changes are ignored" "$(run src/total.ts)" 0
reset

sed -i.bak 's/toBe(3)/toBe(4)/' src/a.spec.ts && rm src/a.spec.ts.bak
eq "allowed path passes" "$(TEST_LOCK_ALLOW='src/a\.spec' run src/a.spec.ts)" 0
has "allowed path is still listed" "allowed by TEST_LOCK_ALLOW"
eq "allow does not cover other paths" "$(TEST_LOCK_ALLOW='src/b\.spec' run src/a.spec.ts)" 1
eq "paths come from stdin too" "$(git diff --name-only | bash "$script" >/dev/null 2>&1; echo $?)" 1
reset

eq "no paths is a usage error" "$(bash "$script" </dev/null >/dev/null 2>&1; echo $?)" 2

echo
echo "passed: $pass  failed: $fail"
[ "$fail" = 0 ]
