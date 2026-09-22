---
name: prisma-schema-review
description: Use when asked to review a Prisma schema change, a model file, a field addition, or a single migration.sql; when someone asks "is this schema okay"; or when sanity-checking AI-generated Prisma or SQL migration code one file at a time. For a whole diff or PR, go through review-routing instead.
---

# Prisma Schema Review

Structured review of ONE schema change — a `.prisma` model file, a field
addition, or one `migration.sql`. Report + suggest — never edits the file.

Schema decisions are **one-way doors**. A wrong column ships to a live
database and every later fix is a backfill under load. This review is the
cheapest place to catch that, so it is deliberately stricter than a service
review.

## Workflow

1. **Identify the target.** A `*.prisma` file, a diff of one, or one
   `migrations/<ts>_*/migration.sql`. If none was given, ask which.
2. **Load the project layer** (do not skip):
   - [INVARIANTS.md](INVARIANTS.md) — the generic one-way doors.
   - `docs/review/prisma-schema-review.md` if the repository has one — the
     project's tenant key, money conventions, ledger tables, reference models
     and ceilings. If it is absent, derive the same from `CLAUDE.md` /
     `AGENTS.md` and the project's data-architecture doc, and say in one line
     that you did.
   - The file under review, and its sibling model — the consistency baseline.
3. **Run `scripts/inventory.sh`** — every model with its tenant scoping, index
   leading columns, money fields and FK delete actions. Read it before claiming
   an index or a constraint is missing.
4. **Run `scripts/scan.sh <file>`** — mechanical pre-scan. Works on both
   `.prisma` and `.sql`. Heuristic, not a gate.
5. **Walk [CHECKLIST.md](CHECKLIST.md)** — all 7 categories, in order.
6. **Emit the report** (format below). Do not edit the file.

Scripts live next to this file. Installed as a plugin, that is
`${CLAUDE_PLUGIN_ROOT}/skills/prisma-schema-review/scripts/`. Both scripts
read `TENANT_FIELD` (default `tenantId`) and `LEDGER_TABLES` (a `|`-separated
list, default empty) from the environment; the project layer says what to set.

## Effort scaling

Default is **medium**. The user may say low / medium / high.

- **low / medium** — 🔴 and 🟡 only; roughly 7 findings. **Zero findings is a
  valid outcome.**
- **high** — add ⚪ nits, still ranked.

## Rule confidence

- **[hard]** — never correct. Always report.
- **[prefer]** — the right default. Report unless the file gives a reason.
- **[context]** — depends. Report only with a concrete consequence.

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

## Tooling coverage

`prisma validate` and `prisma migrate diff` catch syntax, relation
well-formedness and drift. **Nothing** checks the rules in this skill: tenant
scoping, index leading column, money types, ledger immutability, or lock
duration. There is no schema linter that knows these.

`prisma generate` must pass after any schema change — it is a build
dependency, not an optional step.

## Output format

Findings ranked most-severe first. Every finding names the WHY, and for a
schema change the WHY includes **what the fix costs once rows exist**.

```
### <file> review

🔴 <file:line> — <one-sentence defect>
   why: <what breaks, and what the fix costs once data exists>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

If a checklist category is clean, say so in one line.

## Version baseline

Read before applying §5 of the checklist:

```bash
node -e 'const p=require("./package.json");for(const k of ["prisma","@prisma/client"])console.log(k,(p.dependencies||{})[k]||(p.devDependencies||{})[k]||"-")'
grep -rE 'provider *= *"' prisma/ --include='*.prisma' | head -2
```

Two things move the rules: the **database provider** (the migration-safety
section is written for PostgreSQL; MySQL and SQLite differ on enum handling,
`ADD COLUMN` rewrites and transactional DDL) and the **Postgres major** — on
PG ≥ 11 `ADD COLUMN ... DEFAULT` does not rewrite the table and several enum
values may be added in one migration; on older majors both are false.
