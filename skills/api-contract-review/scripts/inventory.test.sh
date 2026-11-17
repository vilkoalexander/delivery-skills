#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo project
lib=libs/shared
mkdir -p $lib/schemas/src/lib $lib/dto/src/lib $lib/types/src/lib $lib/utils/src/lib $lib/test-utils/src \
         apps/api/src apps/web/src prisma
echo '{ "name": "@acme/schemas" }' > $lib/schemas/package.json
cat > $lib/schemas/src/lib/user.schema.ts <<'TS'
import { z } from 'zod';
export const roleSchema = z.enum(['ADMIN', 'MEMBER']);
TS
cat > $lib/schemas/src/lib/order.schema.ts <<'TS'
import { z } from 'zod/v4';
import { join } from 'path';
TS
echo "export * from './lib/user.schema';" > $lib/schemas/src/index.ts
echo "export class UserDto {}"            > $lib/dto/src/lib/user.dto.ts
echo "export type User = {};"             > $lib/types/src/lib/user.ts
cat > apps/api/src/main.ts <<'TS'
import { Module } from '@nestjs/common';
import { UserDto } from '@acme/dto';
import { roleSchema } from '@acme/schemas';
TS
cat > apps/web/src/main.tsx <<'TS'
import { roleSchema } from '@acme/schemas';
import { UserDto } from '@acme/dto';
import { build } from '@acme/test-utils';
TS
cat > prisma/schema.prisma <<'PRISMA'
enum Role {
  ADMIN
  MEMBER
  OWNER
}
PRISMA


out=$(bash "$inventory")
eq   "exits 0"                       "$?" 0
sees "finds the contract directory"  '^contract dir: libs/shared$' "$out"

echo "# chain"
chain=$(under "chain coverage")
sees "an entity with the whole chain" '^  user +schema:yes  dto:yes +type:yes$' "$chain"
sees "an entity with gaps"            '^  order +schema:yes  dto:NO +type:NO$' "$chain"

echo "# consumption"
use=$(under "consumption per app")
sees "counts imports per app"         '^  @acme/schemas +api:1 web:1$' "$use"
sees "dto in an app without Nest"     '^  @acme/dto .*web:1 <-- dto in a non-Nest app$' "$use"
sees "test-utils in app code"         '^  @acme/test-utils .*web:1 <-- test-utils in app code$' "$use"
misses "dto in the Nest app is fine"  'api:1 <-- dto' "$use"

echo "# the rest"
sees "backend import in a client package" '^  libs/shared/schemas/src/lib/order.schema.ts:2:' "$(under 'backend-only imports')"
eq   "zod entry points"               "$(under 'zod entry points' | wc -l | tr -d ' ')" 2
sees "a file missing from its barrel" '^  schemas/src/lib/order.schema.ts not exported from index.ts$' "$(under 'files missing from a barrel')"
misses "an exported file"             'user.schema.ts not exported' "$out"
drift=$(under "Prisma ↔ schema enum drift")
sees   "a Prisma value in no schema enum" '^  Role.OWNER exists in Prisma but in no schema enum' "$drift"
misses "a mirrored value"                 'Role.ADMIN' "$drift"

echo "# options"
has "INVENTORY_LIMIT caps a section" 0 '… \+1 more lines \(raise INVENTORY_LIMIT=1' env INVENTORY_LIMIT=1 bash "$inventory"
has "takes a directory"              0 '^contract dir: libs/shared$' bash "$inventory" "$tmp/project/libs/shared"
new_repo bare
has "no contract directory"          1 '^contract dir not found — pass it: inventory.sh <dir>$' bash "$inventory"

finish
