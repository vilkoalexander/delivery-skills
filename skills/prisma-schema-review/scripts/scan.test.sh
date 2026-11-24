#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

mkdir -p "$tmp/app" && cd "$tmp/app"

echo "# a schema"
cat > schema.prisma <<'PRISMA'
model Order {
  id        String   @id @default(cuid())
  tenantId  String
  amount    Int
  rate      Float
  balance   Int
  dueDate   DateTime
  createdAt DateTime
  user      User     @relation(fields: [userId], references: [id])
  @@index([status])
  @@unique([tenantId, number])
}

model Entry {
  id        String   @id @default(uuid())
  delta     Int
  updatedAt DateTime @updatedAt
  @@map("ledger_entries")
}
PRISMA
out=$(bash "$scan" schema.prisma)
eq "exits 0" "$?" 0
flags "Float/Decimal in the schema"
flags "A stored balance column"
flags "A money-ish field without a minor-unit suffix"
flags "Tenant scoping"
sees  "a model without the tenant key"       '^  model Entry has no tenantId — must be a documented exemption$' "$out"
sees  "an index that does not lead with it"  '^  model Order: index \(\[status\]\) does not lead with tenantId$' "$out"
misses "a unique key is not held to that"    'model Order: index \(unique\)' "$out"
flags "@relation without an explicit onDelete"
flags "Ledger-looking model \(delta field\)"
flags "A calendar date stored as a full timestamp"
misses "a timestamp named …At is fine"       '^8: ' "$out"
flags "More than one id strategy in this file"
unflags "@updatedAt in a file holding a ledger model"

echo "# schema settings"
has   "LEDGER_TABLES names append-only tables" 0 '^## @updatedAt in a file holding a ledger model' env LEDGER_TABLES=ledger_entries bash "$scan" schema.prisma
lacks "EXEMPT_MODELS drops the exemption"      'model Entry has no tenantId' env EXEMPT_MODELS='Entry|Other' bash "$scan" schema.prisma
has   "another tenant key"                     0 'model Order has no orgId'  env TENANT_FIELD=orgId bash "$scan" schema.prisma
lacks "an empty key skips scoping"             '^## Tenant scoping'          env TENANT_FIELD= bash "$scan" schema.prisma

echo "# a tidy schema"
cat > tidy.prisma <<'PRISMA'
model Invoice {
  id          String   @id @default(cuid())
  tenantId    String
  totalMinor  Int
  issuedOn    DateTime @db.Date
  tenant      Tenant   @relation(fields: [tenantId], references: [id], onDelete: Restrict)
  lines       Line[]   @relation("lines")
  @@index([tenantId, issuedOn])
}
PRISMA
has "is clean" 0 '^clean — no mechanical smells$' bash "$scan" tidy.prisma

echo "# a migration"
cat > migration.sql <<'SQL'
CREATE TABLE "notes" ("id" TEXT NOT NULL, "tenantId" TEXT NOT NULL);
CREATE UNIQUE INDEX "notes_key" ON "notes"("tenantId", "slug");
ALTER TABLE "orders" ADD COLUMN "rate" DOUBLE PRECISION;
ALTER TABLE "orders" ADD COLUMN "state" TEXT NOT NULL
ALTER TABLE "orders" DROP COLUMN "legacy";
ALTER TABLE "orders" DROP CONSTRAINT "orders_user_fkey";
ALTER TABLE "orders" ADD CONSTRAINT "orders_user_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id");
ALTER TABLE "orders" DROP CONSTRAINT "orders_old_check";
CREATE INDEX CONCURRENTLY "orders_status_idx" ON "orders"("status");
CREATE UNIQUE INDEX "orders_number_key" ON "orders"("tenantId", "number");
ALTER TYPE "Status" ADD VALUE 'ARCHIVED';
UPDATE "orders" SET "status" = 'ARCHIVED';
DELETE FROM "ledger_entries" WHERE "id" = '1';
SQL
out=$(bash "$scan" migration.sql)
flags "Float/numeric column"
flags "NOT NULL added without a DEFAULT"
flags "Destructive statement"
sees   "a dropped column"                     '^5: ' "$out"
sees   "a constraint dropped for good"        '^8: ' "$out"
misses "a constraint dropped and re-added"    '^6: ' "$out"
flags "CONCURRENTLY"
flags "UNIQUE added to a pre-existing table"
sees   "the old table"                        '^10: CREATE UNIQUE INDEX "orders_number_key"' "$out"
misses "not a table this migration creates"   '^2: CREATE UNIQUE INDEX "notes_key"' "$out"
flags "An enum value is used in the same migration that adds it"
flags "Index whose leading column is not tenantId"
unflags "UPDATE/DELETE on a ledger table"
has "LEDGER_TABLES guards the ledger" 0 '^## UPDATE/DELETE on a ledger table' env LEDGER_TABLES=ledger_entries bash "$scan" migration.sql

echo "# model names with digits and underscores"
printf '%s\n' 'model OAuth2Token {' '  id String @id' '}' '' 'model Audit_Log {' '  id String @id' '  tenantId String' '  @@index([kind])' '}' > odd.prisma
out=$(bash "$scan" odd.prisma)
sees   "a name with a digit is checked"        '^  model OAuth2Token has no tenantId' "$out"
sees   "a name with an underscore is checked"  '^  model Audit_Log: index \(\[kind\]\) does not lead with tenantId$' "$out"
misses "a scoped model is not called unscoped" 'model Audit_Log has no tenantId' "$out"

echo "# a migration as Prisma writes it"
cat > generated.sql <<'SQL'
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL
);
CREATE UNIQUE INDEX "User_email_key" ON "User"("tenantId", "email");
CREATE TABLE IF NOT EXISTS "public"."AuditLog" ("id" TEXT NOT NULL);
CREATE UNIQUE INDEX "AuditLog_key" ON "public"."AuditLog"("tenantId");
ALTER TABLE "Order" ADD COLUMN "state" TEXT NOT NULL;
ALTER TABLE "Order" ADD COLUMN "count" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "kind" TEXT NOT NULL,
ADD COLUMN "note" TEXT;
SQL
out=$(bash "$scan" generated.sql)
unflags "UNIQUE added to a pre-existing table"
not_null=$(under 'NOT NULL added without a DEFAULT')
sees   "a NOT NULL line that ends with ;"      '^8:' "$not_null"
sees   "a NOT NULL line that ends with ,"      '^10:' "$not_null"
misses "a NOT NULL with a DEFAULT"             '^9:' "$not_null"
misses "a nullable column"                     '^11:' "$not_null"
misses "a column of a new table"               '^[23]:' "$not_null"

echo "# input"
has "no argument"  1 '^usage: scan.sh <file.prisma\|migration.sql>$' bash "$scan"
has "missing file" 1 '^not found: nope.prisma$'                     bash "$scan" nope.prisma

finish
