# Schema Invariants

The generic one-way doors. `scripts/inventory.sh` is authoritative for what
the schema currently holds; the project layer (`docs/review/prisma-schema-review.md`)
says which of these apply and names the project's own reference models,
tiers, and ceilings. `templates/prisma-schema-review.md` in this repository
is a starting point for writing one.

## The one-way doors

Changing any of these after rows exist means a backfill against live data.
Treat a violation as 🔴 even if nothing is broken yet.

1. **Tenant key at creation.** Never added later. (Multi-tenant schemas only.)
2. **Money as integer minor units + currency.** Never `Float`.
3. **Balance computed, never stored**, wherever a ledger exists.
4. **Ledgers append-only.** Undo is a compensating row; FKs are `Restrict`.
5. **Tenant key leads every index** on a tenant-scoped model.
6. **Applied migrations are immutable.**

## What the project layer must say

A project's `docs/review/prisma-schema-review.md` answers, in this order:

| Question | Why the review needs it |
| --- | --- |
| Tenant key name, or "single-tenant" | Sets `TENANT_FIELD`; decides whether §1 applies at all |
| Which models are deliberately unscoped, and why | Otherwise every `User`-like table is a false 🔴 |
| Ledger tables, by `@@map` name | Sets `LEDGER_TABLES`; drives the append-only checks |
| Money convention — suffix, type, currency placement | Drives §2 |
| Reference models — one plain entity, one ledger, one event | The consistency baseline per pattern |
| Tables that grow without bound | Where lock duration is a real finding |
| Forward hooks — columns with no reader yet | So they are not reported as dead |
| Deferred features | So they are not proposed as gaps |

## Known ceilings — don't recommend past these

- **`CREATE INDEX CONCURRENTLY` cannot run in a Prisma migration.** Migrations
  execute inside a transaction and `CONCURRENTLY` is not allowed there. If a
  table grows large enough to need it, the index is applied out-of-band and
  the migration marked applied. Do not propose it as a normal fix.
- **A new enum value is unusable in the migration that adds it** on
  PostgreSQL. Two migrations, always.
- **`prisma migrate diff` cannot see intent.** It will happily produce a
  `DROP COLUMN` for a rename. A rename is `ALTER TABLE ... RENAME COLUMN` by
  hand.
- **Multi-file schemas merge into one DMMF.** Cross-file relations are fine;
  a duplicated model name across files is a generate-time error, not a
  runtime one.
