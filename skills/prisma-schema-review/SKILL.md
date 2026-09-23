---
name: prisma-schema-review
description: Use when asked to review a Prisma schema change, a model file, a field addition, or a single migration.sql; when someone asks "is this schema okay"; or when sanity-checking AI-generated Prisma or SQL migration code one file at a time. For a whole diff or PR, go through review-routing instead.
---

# Prisma Schema Review

Structured review of ONE schema change — a `.prisma` model file, a field
addition, or one `migration.sql`. Report and suggest — never edit the file.

Schema decisions are **one-way doors**: a wrong column ships to a live
database and every later fix is a backfill under load. This review is
deliberately stricter than a service review.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the seven categories, and what not to report.
[INVARIANTS.md](INVARIANTS.md) is the generic one-way doors. A diff review
reaches both through `review-routing` and never loads this file.

## Workflow

1. **Target.** A `*.prisma` file, a diff of one, or one
   `migrations/<ts>_*/migration.sql`. None given — ask which.
2. **Project layer.** INVARIANTS.md, then `docs/review/prisma-schema-review.md`
   if the repository has one: tenant key, money conventions, ledger tables,
   reference models, ceilings. If it is absent, derive the same from
   `CLAUDE.md` / `AGENTS.md` and the data-architecture doc, and say so in one
   line. Then the file under review and its sibling model as the consistency
   baseline.
3. **`scripts/inventory.sh [schema-dir-or-file]`** — every model with tenant
   scoping, index leading columns, money fields and FK delete actions.
4. **`scripts/scan.sh <file>`** — mechanical pre-scan, `.prisma` or `.sql`.
   Flags, not a verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/prisma-schema-review/scripts/`. Both read
`TENANT_FIELD` (default `tenantId`) and `LEDGER_TABLES` (`|`-separated,
default empty) from the environment; the project layer says what to set.

## Effort

Default **medium**: 🔴 and 🟡 only, roughly seven findings at most, and
**zero findings is a valid outcome** — say so and stop. **high** adds ⚪ nits,
still ranked.

## Output format

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

Most-severe first. For a schema change the why includes **what the fix costs
once rows exist**. A clean category gets one line.
