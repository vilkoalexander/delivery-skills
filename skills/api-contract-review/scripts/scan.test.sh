#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

new_repo project
schemas=libs/shared/schemas/src/lib
mkdir -p "$schemas" libs/shared/types/src/lib libs/shared/dto/src/lib
cat > "$schemas/user.schema.ts" <<'TS'
import { z } from 'zod';
import { z as z4 } from 'zod/v4';
import { Injectable } from '@nestjs/common';
import { money } from './money.js';
export const userSchema = z.object({
  id: z.string(),
});
export const createUserSchema = z.object({
  amount: z.number(),
  priceMinor: z.number().int(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  bornAt: z.date(),
  limit: z.number().int().max(100),
});
export const userResponseSchema = z.object({
  /** @deprecated */
  id: z.string(),
}).strict();
export function schemas(): string { return 'schemas'; }
TS
cat > libs/shared/types/src/lib/user.ts <<'TS'
export interface User {
  id: string;
}
export type Plan = {
  id: string;
};
TS

echo "# a schema file"
out=$(bash "$scan" "$schemas/user.schema.ts")
eq "exits 0" "$?" 0
flags "Backend-only import in a package that reaches a client bundle"
flags "zod imported from more than one entry point"
flags "Relative import with a .js suffix"
flags "Generator stub"
flags "Request/response schema strictness"
sees  "a request schema that is not strict" "user.schema.ts:8: request schema createUserSchema is not .strict\(\)" "$out"
sees  "a response schema that is strict"    "user.schema.ts:15: response schema userResponseSchema is .strict\(\)" "$out"
misses "a plain schema is neither"          "schema userSchema is" "$out"
flags "Money field without .int\(\)"
flags "Currency regex inline"
flags "Unbounded integer on a request field"
flags "z.date\(\) in a schema"
flags "limit capped in the schema"
flags "Deprecation marker"
sees  "paths are relative to the repository" "^libs/shared/schemas/src/lib/user.schema.ts:3:" "$out"

echo "# a hand-written twin"
out=$(bash "$scan" libs/shared/types/src/lib/user.ts)
flags "Hand-written shape that mirrors an existing schema"
sees   "names the type"                 'User duplicates a schema of the same name' "$out"
misses "a type with no schema is fine"  'Plan duplicates' "$out"

echo "# which packages reach a client"
cp "$schemas/user.schema.ts" libs/shared/dto/src/lib/user.dto.ts
out=$(bash "$scan" libs/shared/dto/src/lib/user.dto.ts)
unflags "Backend-only import"
has "CLIENT_LIBS names them" 0 '^## Backend-only import' env CLIENT_LIBS=dto bash "$scan" libs/shared/dto/src/lib/user.dto.ts
rm libs/shared/dto/src/lib/user.dto.ts

echo "# a directory"
echo "export const idSchema = z.string();" > "$schemas/id.schema.ts"
echo "it('x', () => { z.date() })"          > "$schemas/id.schema.spec.ts"
out=$(bash "$scan" libs/shared/schemas)
flags  "z.date\(\) in a schema"
misses "spec files are skipped" 'id.schema.spec.ts' "$out"
has "one tidy file is clean" 0 '^clean — no mechanical smells$' bash "$scan" "$schemas/id.schema.ts"

echo "# double quotes, a spaced directory, another working directory"
new_repo "double quoted"
spaced="packages/my schemas/src/lib"
mkdir -p "$spaced"
cat > "$spaced/order.schema.ts" <<'TS'
import { z } from "zod";
import { z as z4 } from "zod/v4";
import { Injectable } from "@nestjs/common";
import { money } from "./money.js";
import { pathToRegexp } from "path-to-regexp";
export const orderSchema = z.object({ bornAt: z.date() });
TS
out=$(CLIENT_LIBS='my schemas' bash "$scan" "$spaced/order.schema.ts")
flags "Backend-only import in a package that reaches a client bundle"
misses "a package whose name starts like a backend one" 'path-to-regexp' "$(under 'Backend-only import')"
flags "zod imported from more than one entry point"
flags "Relative import with a .js suffix"
flags "z.date\(\) in a schema"
out=$(bash "$scan" "packages/my schemas")
sees "a directory with a space is scanned" '^## z.date\(\) in a schema' "$out"
out=$(cd / && bash "$scan" "$tmp/double quoted/$spaced/order.schema.ts")
sees "paths are relative to the target's repository" '^packages/my schemas/src/lib/order.schema.ts:6:' "$out"
cd "$tmp/project" || exit 1

echo "# input"
mkdir empty
has "no argument"     1 '^usage: scan.sh <file-or-dir>$' bash "$scan"
has "missing target"  1 '^not found: nope$'              bash "$scan" nope
has "empty directory" 1 '^no .ts files under empty$'     bash "$scan" empty

finish
