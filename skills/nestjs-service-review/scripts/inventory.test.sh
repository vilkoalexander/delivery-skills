#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo project
app=src/app
mkdir -p $app/shared $app/orders/__tests__ $app/users libs/test-utils/src
echo "@Module({}) export class AppModule {}"    > $app/app.module.ts
cat > $app/shared/money.ts <<'TS'
export function toMinor() {}
export const ZERO = 0;
export type Money = number;
TS
echo "const internal = 1;"                      > $app/shared/internal.ts
echo "export const barrel = 1;"                 > $app/shared/index.ts
echo "@Module({}) export class OrdersModule {}" > $app/orders/orders.module.ts
echo "export class OrdersService {}"            > $app/orders/orders.service.ts
echo "@UseGuards(AuthGuard) @UseGuards(AuthGuard) @UseInterceptors(Audit) export class OrdersController {}" > $app/orders/orders.controller.ts
echo "it('x', () => {})"                        > $app/orders/orders.controller.spec.ts
echo "@Module({}) export class UsersModule {}"  > $app/users/users.module.ts
echo "export class UsersService {}"             > $app/users/users.service.ts
echo "it('x', () => {})"                        > $app/orders/__tests__/orders.service.spec.ts
echo "export async function buildApp() {}"      > libs/test-utils/src/app.ts


out=$(bash "$inventory")
eq   "exits 0"                  "$?" 0
sees "finds the app source"     '^app src: src/app$' "$out"

shared=$(under "shared primitives")
sees   "a shared module with its exports"  '^  shared/money.ts +Money,ZERO,toMinor$' "$shared"
misses "skips barrels and export-free files" 'index.ts|internal.ts' "$shared"

modules=$(under "modules")
sees   "counts per module"      '^  orders +services:1 +controllers:1 +specs:2$' "$modules"
sees   "a module with no specs" '^  users +services:1 +controllers:0 +specs:0$' "$modules"
misses "the root module"        '^  app ' "$modules"

eq   "units without a spec"     "$(under 'missing specs' | tr -d ' ')" "users/users.service.ts"
sees "guards by use"            '^ +2 @UseGuards\(AuthGuard\)$' "$(under 'guards / interceptors')"
sees "interceptors"             '^ +1 @UseInterceptors\(Audit\)$' "$(under 'guards / interceptors')"
sees "test-utils exports"       '^  buildApp$' "$(under 'test-utils available to specs (libs/test-utils)')"

echo "# only the files under review"
out=$(REVIEW_FILES="$app/orders/orders.service.ts $app/users/users.service.ts $app/shared/money.ts" bash "$inventory")
sees "heading says so"          '^=== missing specs among REVIEW_FILES' "$out"
eq   "only units are checked"   "$(under 'missing specs' | wc -l | tr -d ' ')" 1
touch $app/users/users.service.spec.ts
out=$(bash "$inventory")
eq   "nothing missing"          "$(under 'missing specs' | tr -d ' ')" "none"

echo "# options"
has "INVENTORY_LIMIT caps a section" 0 '… \+1 more lines \(raise INVENTORY_LIMIT=1' env INVENTORY_LIMIT=1 bash "$inventory"
has "takes a directory"              0 '^app src: src/app/orders$' bash "$inventory" "$tmp/project/src/app/orders"
new_repo bare
has "no app module"                  1 '^app src not found — pass it: inventory.sh <dir>$' bash "$inventory"

finish
