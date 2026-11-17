#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/reuse-scan.sh"

new_repo project
mkdir -p src/utils src/cart
echo "export function formatTotal() {}"       > src/utils/format.ts
echo "export const cart = 1;"                 > src/cart/cart.ts
echo '{ "dependencies": { "zod": "3.0.0" } }' > package.json
commit_all


has "nothing changed" 0 '^REUSE: 0 flags$' bash "$scan"

echo "# a change with something to question"
cat > src/utils/timing.ts <<'TS'
export function debounce() {}
export const FormatTotal = 1;
TS
cat >> src/cart/cart.ts <<'TS'
const copy = JSON.parse(JSON.stringify(cart));
const wait = new Promise(r => setTimeout(r, 10));
const price = total.toFixed(2);
const age = Date.now() - start.getTime();
const ids = [...new Set(all)];
const empty = Object.keys(map).length === 0;
const res = await fetch('/api/cart');
TS
echo '{ "dependencies": { "zod": "3.0.0", "lodash": "4.0.0" }, "devDependencies": { "vitest": "1.0.0" } }' > package.json
echo "export function debounce() {}" > src/cart/cart.test.ts
out=$(bash "$scan")
eq   "exits 0 by default"             "$?" 0
sees "new file in a shared layer"     '^src/utils/timing.ts — new file in a shared layer' "$(under 'New shared files (1)')"
sees "an export that already exists"  '^src/utils/timing.ts:2 FormatTotal — already exported from src/utils/format.ts' "$(under 'New exports that already exist (1)')"
sees "a textbook helper"              '^src/utils/timing.ts:1 debounce — a textbook helper' "$(under 'New exports named like a textbook helper (1)')"
eq   "added dependencies, by name"    "$(under 'Dependencies added (2)' | cut -d' ' -f1,2 | paste -sd, -)" "package.json: lodash,package.json: vitest"
patterns=$(under 'Hand-roll patterns in added lines (7)')
sees "deep clone via JSON"            '^src/cart/cart.ts:2:.* — deep clone via JSON' "$patterns"
sees "sleep via setTimeout"           '^src/cart/cart.ts:3:.* — sleep via setTimeout' "$patterns"
sees "money via toFixed"              '^src/cart/cart.ts:4:.* — money formatted with toFixed\(2\)' "$patterns"
sees "date arithmetic"                '^src/cart/cart.ts:5:.* — date arithmetic on getTime\(\)' "$patterns"
sees "uniq via Set"                   '^src/cart/cart.ts:6:.* — uniq via Set spread' "$patterns"
sees "isEmpty via Object.keys"        '^src/cart/cart.ts:7:.* — isEmpty via Object.keys' "$patterns"
sees "direct fetch"                   '^src/cart/cart.ts:8:.* — fetch called directly' "$patterns"
misses "test files are not scanned"   'cart.test.ts' "$out"
sees "totals the flags"               '^REUSE: 12 flags$' "$out"

echo "# options"
has   "REUSE_STRICT fails on a flag"     1 '^REUSE: 12 flags$' env REUSE_STRICT=1 bash "$scan"
has   "a path limits the scan"           0 '^REUSE: 2 flags$'  bash "$scan" package.json
has   "paths on stdin"                   0 '^REUSE: 2 flags$'  bash -c "echo package.json | bash '$scan'"
lacks "REUSE_SHARED moves the shared layer" 'New shared files' env REUSE_SHARED='(^|/)kit/' bash "$scan"
has   "and finds files in it"            0 '^src/cart/extra.ts — new file in a shared layer' bash -c "echo 'export const a = 1;' > src/cart/extra.ts; REUSE_SHARED='(^|/)cart/' bash '$scan' src/cart/extra.ts"

echo "# a commit range"
commit_all change
has "the tree is clean again"            0 '^REUSE: 0 flags$'  bash "$scan"
has "REUSE_DIFF_RANGE scans the commit"  0 '^REUSE: 12 flags$' env REUSE_DIFF_RANGE=HEAD~1..HEAD bash "$scan"

mkdir -p "$tmp/plain" && cd "$tmp/plain"
has "outside git" 2 '^reuse-scan: not a git repository$' env GIT_CEILING_DIRECTORIES="$tmp" bash "$scan"

finish
