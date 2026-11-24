#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo project
mkdir -p prisma/migrations/20240101_init prisma/migrations/20240202_orders
touch prisma/migrations/migration_lock.toml
cat > prisma/schema.prisma <<'PRISMA'
model Order {
  id          String   @id
  tenantId    String
  totalMinor  Int
  currency    String
  updatedAt   DateTime @updatedAt
  tenant      Tenant   @relation(fields: [tenantId], references: [id], onDelete: Restrict)
  user        User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  buyer       User     @relation(fields: [buyerId], references: [id], onDelete: Cascade)
  @@index([tenantId, status])
  @@unique([number])
  @@map("orders")
}

model Audit {
  id String @id
}

enum Role {
  ADMIN
}
PRISMA

# model NAME prints the block describing one model
model() { printf '%s\n' "$out" | awk -v name="$1" 'NF == 0 {on = 0} $1 == name {on = 1} on'; }

out=$(bash "$inventory")
eq   "exits 0"                  "$?" 0
sees "finds the schema"         '^schema: prisma/schema.prisma$' "$out"

order=$(model Order)
sees "table name"               '^Order  \(orders\)$' "$order"
sees "tenant key and mutability" '^  tenant:   tenantId   \(\+@updatedAt: mutable\)$' "$order"
sees "money fields"             '^  money:    totalMinor currency$' "$order"
sees "delete actions, counted"  '^  onDelete: Restrict×1 Cascade×2$' "$order"
sees "index"                    '^      I \[tenantId,status\]$' "$order"
sees "unique key"               '^      U \[number\]$' "$order"

audit=$(model Audit)
sees "a model with no table name" '^Audit  \(no @@map\)$' "$audit"
sees "a model with no tenant key" '^  tenant:   NONE — must be a documented exemption   \(no @updatedAt\)$' "$audit"

sees   "keys that do not lead with the tenant" '@@unique\(\[number\]\)' "$(under 'indexes whose leading column is not tenantId')"
misses "keys that do"                          'tenantId, status' "$(under 'indexes whose leading column is not tenantId')"
eq   "enums"                    "$(under 'enums' | tr -s ' ')" " enum Role {"
eq   "migrations, oldest first, no lock file" "$(under 'migrations' | tr -d ' ' | paste -sd, -)" "20240101_init,20240202_orders"

echo "# options"
out=$(TENANT_FIELD= bash "$inventory")
sees   "single-tenant: mutability only" '^  mutable:  yes \(@updatedAt\)$' "$out"
misses "single-tenant: no tenant lines" 'tenant:|leading column' "$out"
has "another tenant key"        0 '^  tenant:   NONE'           env TENANT_FIELD=orgId bash "$inventory"
has "INVENTORY_LIMIT caps the models" 0 '… \+1 more models \(raise INVENTORY_LIMIT=1' env INVENTORY_LIMIT=1 bash "$inventory"
has "takes a file"              0 '^schema: prisma/schema.prisma$' bash "$inventory" "$tmp/project/prisma/schema.prisma"
has "takes a directory"         0 '^schema: prisma/schema.prisma$' bash "$inventory" "$tmp/project/prisma"

echo "# model names with digits and underscores"
new_repo "odd [names]"
mkdir prisma
printf '%s\n' 'model OAuth2Token {' '  id String @id' '  tenantId String' '}' '' 'model Audit_Log{' '  id String @id' '}' > prisma/schema.prisma
out=$(bash "$inventory")
sees "a name with a digit"       '^OAuth2Token  \(no @@map\)$' "$out"
sees "a name with an underscore" '^Audit_Log  \(no @@map\)$' "$out"
sees "a root with regex characters is cut from the path" '^schema: prisma/schema.prisma$' "$out"

new_repo bare
has "no schema"                 1 '^no .prisma files found — pass a dir or file$' bash "$inventory"

finish
