---
name: jpa-schema-review
description: Use when asked to review a single JPA / Hibernate entity (*Entity.java, @Entity), a Spring Data repository or Specification, or a Flyway SQL migration (V1__name.sql), check whether a mapping, a query or a migration is okay, or sanity-check AI-generated persistence code one file at a time. For a whole diff or PR, go through review-routing instead. For a controller or a service, use spring-service-review.
---

# JPA Schema Review

Structured review of ONE entity, repository or SQL migration. Report and
suggest — never edit the file.

Nothing in a Java build looks at this layer. The compiler accepts an EAGER
association, a bulk update that leaves stale entities, and a migration that
blocks every write for the length of an index build. With `ddl-auto: none` a
mapping that does not match its column fails at the first query, in
production.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, settings,
severity floor, the seven categories, and what not to report.
[INVARIANTS.md](INVARIANTS.md) is the generic non-negotiables. A diff review
reaches both through `review-routing` and never loads this file.

## Workflow

1. **Target.** One entity, one repository or specification, or one migration.
   None given — ask which.
2. **Project layer.** INVARIANTS.md, then `docs/review/jpa-schema-review.md`
   if the repository has one: migration rules, deploy model, entity
   conventions, large tables, ceilings. If it is absent, derive the same from
   `CLAUDE.md` / `AGENTS.md` and say so in one line. Then the file under
   review and its counterpart: for an entity the migration that creates its
   table, for a migration the entity it changes, for a repository the entity
   and one caller.
3. **`scripts/inventory.sh [root]`** — settings, base classes, the
   conventions the majority of entities follow, the last migrations.
4. **`scripts/scan.sh <file>`** — mechanical pre-scan. Flags, not a verdict.
5. **Walk CHECKLIST.md** — the sections for this kind of file.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/jpa-schema-review/scripts/`. `scan.sh` reads
`MIGRATION_BASE` (the git ref a merged migration is compared with, default
`HEAD`; in a branch review set it to the base branch) and `MIGRATION_NAME`
(the file-name pattern) from the environment.

## Effort

Default **medium**: 🔴 and 🟡 only, and **zero findings is a valid outcome**
— say so and stop. **high** adds ⚪ nits, still ranked. A short report of
real defects beats an exhaustive one.

## Output format

```
### <file> review

🔴 <file:line> — <one-sentence defect>
   why: <what breaks, concretely>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. One finding per defect. Every finding names the why.
Before/after is the two lines that change. A clean category gets one line.
