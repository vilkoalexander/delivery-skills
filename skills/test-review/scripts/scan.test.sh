#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

mkdir -p "$tmp/app" && cd "$tmp/app"
cat > cart.test.ts <<'TS'
import { total } from './cart';
import { build } from './test-utils/build';
vi.mock('./cart');
let cache = {};
describe('cart', () => {
  it.only('works', async () => {
    const api: any = vi.fn() as any as Mock;
    expect(true).toBe(true);
    expect(total([])).toBeDefined();
    expect(api).toHaveBeenCalledWith(1);
  });
  it('waits', async () => {
    await new Promise(resolve => setTimeout(resolve, 100));
    await waitFor(() => screen.getByText('x'), { timeout: 5000 });
    const id = Math.random();
    vi.spyOn(service, 'load');
    try {
      await fetch('https://api.example.com/cart');
    } catch (e) {
      console.log(e); // TODO
    }
  });
  it('renders', () => { expect(tree).toMatchSnapshot(); });
  it('is empty', () => {});
  it('is empty too', () => {});
  it('is empty three', () => {});
});
TS
out=$(bash "$scan" cart.test.ts)
eq "exits 0" "$?" 0

echo "# can it fail"
flags "Focused or skipped test left in"
flags "Tautological assertion"
flags "Weak assertion"
flags "Assertion on a mock call"
flags "Assertion inside a condition or catch"
flags "Swallowed act"
flags "Fewer assertions \(4\) than test blocks \(5\)"

echo "# mocking"
flags "Mocks the module under test \(./cart\)"
flags "Mock typed any"
flags "spyOn on the subject's own method"

echo "# determinism"
flags "Real time"
flags "Long waitFor timeout"
flags "Random data without a seed"
flags "Module-level mutable state"
flags "Real network or filesystem in a unit test"

echo "# the rest"
flags "Snapshot"
flags "Test name describes a method or is empty of behaviour"
flags "console.\* in a test"
flags "TODO/FIXME"

echo "# a helper import is not the subject"
cat > helper.test.ts <<'TS'
import { build } from './test-utils/build';
vi.mock('./test-utils/build');
it('adds the item', () => { expect(build().items).toEqual([1]); });
TS
out=$(bash "$scan" helper.test.ts)
unflags "Mocks the module under test"

echo "# localhost is not a real network"
cat > local.test.ts <<'TS'
it('answers', async () => { expect(await call('http://localhost:3000/x')).toEqual({ ok: 1 }); });
TS
has "is clean" 0 '^clean — no mechanical smells$' bash "$scan" local.test.ts

echo "# input"
has "no argument"  1 '^usage: scan.sh <test file>$' bash "$scan"
has "missing file" 1 '^not found: nope.test.ts$'    bash "$scan" nope.test.ts

finish
