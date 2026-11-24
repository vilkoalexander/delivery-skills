#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo project
mkdir -p src/test-utils src/factories src/cart node_modules/dep/test-utils
cat > package.json <<'JSON'
{ "scripts": { "test": "vitest run", "test:e2e": "playwright test", "build": "tsc" } }
JSON
echo "export default { test: { setupFiles: ['./src/test-utils/setup.ts'] } }" > vitest.config.ts
cat > src/test-utils/render.tsx <<'TS'
export function renderWithProviders() {}
export const wrapper = 1;
TS
echo "import { setupServer } from 'msw/node'; setupServer();" > src/test-utils/setup.ts
echo "export const createUser = () => ({});"                  > src/factories/user.ts
echo "export function buildCart() {}"                         > src/cart/cart.ts
echo "export function total() {}"                             >> src/cart/cart.ts
echo "it.only('adds', () => {});"                             > src/cart/cart.test.ts
echo "export function hidden() {}"                            > node_modules/dep/test-utils/x.ts


out=$(bash "$inventory")
eq   "exits 0"                    "$?" 0
sees "names the root"             "^root: $tmp/project$" "$out"

echo "# runner"
runner=$(under "Runner and config")
sees   "config file"              '^  vitest.config.ts$' "$runner"
sees   "test scripts"             '^  script test: vitest run$' "$runner"
sees   "e2e scripts"              '^  script test:e2e: playwright test$' "$runner"
misses "other scripts"            'script build' "$runner"
sees   "setup files"              "setupFiles: \['./src/test-utils/setup.ts'\]" "$runner"

echo "# helpers"
helpers=$(under "Helper modules")
sees   "a helper with its exports" '^  src/test-utils/render.tsx +renderWithProviders,wrapper$' "$helpers"
sees   "a factory module"          '^  src/factories/user.ts +createUser$' "$helpers"
sees   "a helper with no exports"  '^  src/test-utils/setup.ts +—$' "$helpers"
misses "node_modules"              'node_modules' "$out"
eq     "builders exported anywhere" "$(under 'Factories and builders exported anywhere' | tr -d ' ' | paste -sd, -)" "buildCart,createUser"
eq     "network fixtures"          "$(under 'Network fixtures (msw, nock)' | tr -d ' ')" "./src/test-utils/setup.ts"
sees   "focused tests"             "^  ./src/cart/cart.test.ts:1:it.only\('adds'" "$(under 'Focused or skipped tests across the suite')"

echo "# a suite with nothing focused"
rm src/cart/cart.test.ts
has "exits 0 when the last section is empty" 0 '^## Focused or skipped tests across the suite$' bash "$inventory"
echo "it.only('adds', () => {});" > src/cart/cart.test.ts

echo "# options"
has "INVENTORY_LIMIT caps a section" 0 '… \+2 more lines \(raise INVENTORY_LIMIT=1' env INVENTORY_LIMIT=1 bash "$inventory"
has "takes a root"                   0 "^root: $tmp/project/src$" bash "$inventory" "$tmp/project/src"
has "a missing root"                 1 '^root not found: nope$'   bash "$inventory" nope

finish
