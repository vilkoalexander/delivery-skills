#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo project
mkdir -p src/components/ui src/hooks src/lib src/features/cart/components src/features/cart/hooks src/pages
cat > src/components/ui/Button.tsx <<'TSX'
/**
 * Primary action button.
 */
export function Button() {}
export type ButtonProps = {};
TSX
cat > src/hooks/useCart.ts <<'TS'
const useCart = () => {};
const helper = 1;
export { useCart, helper };
TS
echo "export default function money() {}" > src/lib/money.ts
echo "const internal = 1;"                > src/lib/internal.ts
echo "export const x = 1;"                > src/lib/index.ts
echo "export const y = 1;"                > src/lib/money.test.ts
echo "export const Page = 1;"             > src/pages/Home.tsx

# exports FILE prints the export column of one row
exports() { printf '%s\n' "$out" | grep -E "^  $1 " | awk '{print $2}'; }

out=$(bash "$inventory")
eq   "exits 0"                        "$?" 0
sees "names the root it found"        '^src root: src$' "$out"
sees "one section per layer"          '^=== components/ui$' "$out"
eq   "function and type exports"      "$(exports Button.tsx)" "Button,ButtonProps"
eq   "an export list"                 "$(exports useCart.ts)" "helper,useCart"
eq   "a default function"             "$(exports money.ts)" "money"
eq   "a module with no exports"       "$(exports internal.ts)" "—"
misses "skips barrels and tests"      'index.ts|money.test.ts' "$out"
misses "skips layers it does not know" 'Home.tsx' "$out"
sees "feature-local folders"          '^  features/cart/components$' "$out"
sees "ends with the question"         '^Reinvention check: ' "$out"

echo "# options"
has "INVENTORY_DOCS adds the doc line" 0 '↳ Primary action button\.$' env INVENTORY_DOCS=1 bash "$inventory"
has "INVENTORY_LIMIT caps a section"   0 '… \+1 more lines \(raise INVENTORY_LIMIT=1' env INVENTORY_LIMIT=1 bash "$inventory"

echo "# where the source is"
new_repo mono
mkdir -p apps/web/src/hooks
echo "export const useA = 1;" > apps/web/src/hooks/useA.ts
has "finds an app in a monorepo" 0 '^src root: apps/web/src$' bash "$inventory"
has "takes a directory"          0 'useA.ts +useA$'           bash "$inventory" apps/web/src
has "a missing directory"        1 '^src root not found — pass it: inventory.sh <src-dir>$' bash "$inventory" nope
new_repo bare
has "no source root"             1 '^src root not found'      bash "$inventory"

finish
