# Prisma Schema Review Checklist

Seven categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). Name the consequence, and for a
schema change the consequence includes *what the fix costs once rows exist*.

`<tenant>` below stands for the project's tenant key (`TENANT_FIELD`, e.g.
`tenantId`, `orgId`, `accountId`). Skip §1 entirely on a single-tenant
schema and say so in one line.

## Before you start

### Version baseline

Read before applying §5 below:

```bash
node -e 'const p=require("./package.json");for(const k of ["prisma","@prisma/client"])console.log(k,(p.dependencies||{})[k]||(p.devDependencies||{})[k]||"-")'
grep -rE 'provider *= *"' prisma/ --include='*.prisma' | head -2
```

Two things move the rules: the **database provider** (the migration-safety
section is written for PostgreSQL; MySQL and SQLite differ on enum handling,
`ADD COLUMN` rewrites and transactional DDL) and the **Postgres major** — on
PG ≥ 11 `ADD COLUMN ... DEFAULT` does not rewrite the table and several enum
values may be added in one migration; on older majors both are false.

### Tooling coverage

`prisma validate` and `prisma migrate diff` catch syntax, relation
well-formedness and drift. **Nothing** checks the rules in this skill: tenant
scoping, index leading column, money types, ledger immutability, or lock
duration. There is no schema linter that knows these.

`prisma generate` must pass after any schema change — it is a build
dependency, not an optional step.

## Severity floor

Always 🔴, regardless of effort:

- in a multi-tenant schema, a tenant-scoped model without the tenant key, or
  an index on one whose leading column is not the tenant key
- money stored as anything but integer minor units, or an amount without a
  currency
- a stored / denormalised balance column next to a ledger that already
  answers the question
- a ledger row made mutable or deletable (a cascading FK, `@updatedAt`, or a
  migration that UPDATEs / DELETEs ledger rows)
- an applied migration edited in place

## 1. Tenant scoping — one-way door

- **[hard] Every new tenant-owned model carries `<tenant>`** from creation,
  not added later. Adding it afterwards is a nullable-column → backfill → NOT
  NULL → index migration against live data.
- **[hard] `<tenant>` is the LEADING column of every index** on a
  tenant-scoped model. `@@index([status, <tenant>])` cannot serve a
  tenant-scoped scan; the planner needs the tenant first.
- **[hard] Every compound `@@unique` on a tenant-scoped model includes
  `<tenant>`** — otherwise the constraint is global and one tenant's row
  blocks another's. `@@unique([<tenant>, email])` is the pattern.
- **[context] A child whose parent FK already pins the tenant** may be
  deliberately tenant-free (`@@unique([parentId, position])`). The project layer
  lists these; do not "fix" them.
- **[hard] A new model is classified** — scoped (default), globally unscoped
  (`User`, an auth table), or pure child reached only through its parent. The
  project layer keeps the list; an unclassified model is a finding because
  whatever enforces scoping at query time will guess.
- **[prefer] An index that serves an `onDelete: Restrict` FK check** — the
  child side needs an index on the FK column or every parent delete does a
  sequential scan.

## 2. Money & ledger — one-way door

Skip §2 when the schema holds no money and no ledger, and say so.

- **[hard] Money is `Int` minor units** with a suffix that says so
  (`amountMinor`, `priceCents`). **Never `Float`, never `Decimal`** unless the
  project layer says the domain needs sub-cent precision and has chosen
  `Decimal` with a fixed scale. A `Float` money column is unrecoverable
  without re-deriving every downstream sum.
- **[hard] Every amount has a `currency String`** (ISO 4217) beside it, or the
  model is single-currency by documented design. A count (sessions, seats) has
  no currency and no money suffix.
- **[hard] Balance is never a column** when a ledger exists. The balance is
  `SUM(ledger.delta)`. A cached `balance` column beside a ledger is the single
  most damaging change to a financial schema: two sources of truth that will
  disagree.
- **[hard] Ledger rows are append-only** — every FK from a ledger model is
  `onDelete: Restrict`, and there is no `@updatedAt`. A ledger model with
  `@updatedAt` is a contradiction.
- **[hard] Undo is a compensating row**, never an UPDATE or DELETE. A new
  ledger model needs a `reversalOfId` self-relation and a `REVERSAL` kind, or
  a note saying why it cannot be reversed.
- **[prefer] Price / currency snapshots on the event row** — a financial
  event copies the price at the time it happened. Reading it through a
  relation later silently rewrites history when the price changes.
- **[context] A retryable write needs `idempotencyKey` +
  `@@unique([<tenant>, idempotencyKey])`** — clients retry after a dropped
  response.

## 3. Field-level conventions

The project layer says which id strategy, timestamp names and table-name
scheme the schema uses. The rule is consistency with the siblings.

- **[hard] Id strategy matches every existing model** — `uuid()`, `cuid()`,
  autoincrement, whichever; a second strategy in one schema is a finding.
- **[hard] Timestamps are UTC `DateTime`.** A calendar date with no time is
  `@db.Date`; anything else is a timestamp. Timezone rendering is the
  client's job.
- **[prefer] `createdAt DateTime @default(now())` on every model**;
  `updatedAt DateTime @updatedAt` on mutable models only.
- **[prefer] One table-naming scheme** — `@@map` to snake_case plural, or no
  `@@map` anywhere. Mixed is the finding.
- **[prefer] Enums over free-text status columns**, values SCREAMING_SNAKE.
- **[hard] Every non-obvious column carries a why-comment** (`///`). A new
  column with a non-obvious purpose and no comment is a finding. The project
  layer names the model that sets the bar.
- **[context] Nullable vs required** — a nullable column is a permanent branch
  in every consumer. Required-with-default is usually the better default.

## 4. Relations & delete behaviour

Every relation must state `onDelete` deliberately.

| Intent | Action |
| --- | --- |
| Child is meaningless without the parent | `Cascade` |
| Financial / audit history must outlive the parent | `Restrict` |
| Optional assignment that should just detach | `SetNull` |

- **[hard] No implicit default.** Prisma's default for a required relation is
  `Restrict` (`NoAction` on some providers), but relying on it hides intent.
  State it.
- **[hard] A `Cascade` that can reach a ledger or audit row is a 🔴.** Trace
  the path from the root entity; it must break at `Restrict` before any
  financial table.
- **[prefer] Named relations** when two FKs point at the same model.
- **[context] A deliberate FK-less link** is a forward hook, documented as
  such in the project layer. Do not add the FK.

## 5. Migration safety (PostgreSQL)

`prisma migrate deploy` applies each migration file as one transaction.

- **[hard] Never edit an applied migration.** The checksum is recorded; editing
  makes `migrate deploy` fail on every environment that already ran it. Write
  a new migration. Always 🔴.
- **[hard] Adding a required column to a populated table is four steps**, in
  order: nullable column → backfill → `SET NOT NULL` → index. A single
  `ADD COLUMN ... NOT NULL` with no default fails outright.
- **[hard] A new enum value cannot be used in the same migration that adds
  it** — Postgres will not let a value be referenced (as a `DEFAULT`, in an
  `UPDATE`) until the adding transaction commits. Split into two migrations.
- **[prefer] Destructive statements need an explicit decision** — `DROP
  COLUMN`, `DROP TABLE`, a type narrowing, or a `UNIQUE` added to a populated
  column that may hold duplicates. Prisma marks these; do not wave them
  through.
- **[context] Lock duration.** On PG ≥ 11 `ADD COLUMN ... DEFAULT` is instant
  and `SET NOT NULL` still scans the table under an ACCESS EXCLUSIVE lock. On
  a table of thousands of rows that is milliseconds — **do not cargo-cult
  zero-downtime ceremony onto small tables.** Flag it on tables that grow
  without bound; the project layer names them.
- **[hard] A data migration that touches ledger rows** (`UPDATE` / `DELETE`
  on a `LEDGER_TABLES` table) breaks append-only. Insert compensating rows.
- **[prefer] Migration folder name says what it does** —
  `add_invoice_ledger`, `restrict_tenant_fk_on_ledger`. Not `update_schema`,
  never a ticket number.

## 6. Query support

A schema is wrong if the queries it must serve cannot use an index.

- **[hard] Every list endpoint's sort has a matching index.** A keyset sort of
  `(createdAt asc, id asc)` needs `@@index([<tenant>, createdAt, id])` — with
  the filter column in between for a filtered list.
- **[hard] Every `SUM(delta)` read path has an index** covering the grouping
  key, e.g. `@@index([<tenant>, accountId, currency, createdAt])`.
- **[prefer] A new filterable column gets an index with `<tenant>` leading.**
- **[context] Do not add an index per column.** Every index costs write
  throughput and only the leading columns are usable. Name the query it
  serves, in a comment, or do not add it.

## 7. Consistency & downstream

- **[hard] `prisma generate` after any schema change** — the client is a build
  dependency.
- **[prefer] A new model has a seed entry** if the project seeds a dev / test
  database.
- **[prefer] A new model or field is documented** wherever the project keeps
  its data-architecture doc.
- **[prefer] Model files are grouped by domain** in a multi-file schema, not
  one file per model and not one giant file.
- **[context] A new response field means a contract change** — a shared type
  or schema package, and any client on a separate release train. An existing
  field's type must not change shape under an installed client.

---

## Do NOT report

- Restating the project's instructions or data-architecture doc as if it were
  a finding.
- `varchar(n)` length limits when the project caps lengths at the API boundary
  on purpose — check the project layer.
- Forward hooks the project documents as intentionally unused (a nullable
  column with no reader yet, a FK-less id kept for portability).
- Demanding `CREATE INDEX CONCURRENTLY` — it cannot run inside a Prisma
  migration transaction (see INVARIANTS.md ceilings).
- Zero-downtime ceremony on small tables. Name the table size before flagging
  lock duration.
- Naming anything after a sprint, quarter or ticket.
