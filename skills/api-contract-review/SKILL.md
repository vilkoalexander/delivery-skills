---
name: api-contract-review
description: Use when a shared contract package changes — a zod or other validation schema, a DTO, a shared TypeScript type, a field added to an API response — or when someone asks "will this break the app" or "is this backward compatible". For backend logic use nestjs-service-review, for the database use prisma-schema-review.
---

# API Contract Review

Structured review of ONE change to a shared contract package — the schemas,
DTOs and types more than one app consumes. Report and suggest — never edit
the file.

What makes this different: **a client on a separate release train.** A
backend deploy reaches users in minutes; a mobile app reaches them when they
take the update, which may be never; a cached web bundle sits in between.
Every contract change is evaluated twice — **new server + old client** and
**old server + new client**.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the six categories, and what not to report.
[INVARIANTS.md](INVARIANTS.md) is the compatibility matrix and the generic
chain. A diff review reaches both through `review-routing` and never loads
this file.

## Workflow

1. **Target.** A file under the shared contract package, or a diff of one.
   None given — ask which.
2. **Project layer.** INVARIANTS.md, then `docs/review/api-contract-review.md`
   if the repository has one: the contract chain, which packages reach which
   bundle, release trains, shared primitives, ceilings. If it is absent,
   derive the same from `CLAUDE.md` / `AGENTS.md` and the package graph, and
   say so in one line. Then the file under review **and its whole chain** — a
   schema change implies the inferred type and, for a request/response shape,
   the DTO — and its consumers: `grep` the exported symbol across every app
   before judging anything.
3. **`scripts/inventory.sh [contract-dir]`** — chain per entity, consumers
   per package, barrel gaps, Prisma ↔ schema enum drift.
4. **`scripts/scan.sh <file-or-dir>`** — mechanical pre-scan. Flags, not a
   verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/api-contract-review/scripts/`. `scan.sh` reads
`CLIENT_LIBS` (`|`-separated package dir names that reach a client bundle,
default `schemas|types|utils`) from the environment.

## Effort

Default **medium**: 🔴 and 🟡 only, roughly seven findings at most, and
**zero findings is a valid outcome** — say so and stop. **high** adds ⚪ nits,
still ranked.

## Output format

```
### <file> review

🔴 <file:line> — <one-sentence defect>
   why: <which combination breaks and what the user sees>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. For a contract the why names **which side breaks**. A clean
category gets one line.
