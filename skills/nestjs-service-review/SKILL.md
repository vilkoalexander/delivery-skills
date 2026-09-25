---
name: nestjs-service-review
description: Use when asked to review a single NestJS backend file (*.service.ts, *.controller.ts, guard, interceptor, pipe or module), check whether a service or controller is okay, or sanity-check AI-generated NestJS code one file at a time. For a whole diff or PR, go through review-routing instead.
---

# NestJS Service Review

Structured review of ONE NestJS backend file. Report and suggest — never edit
the file.

Most NestJS projects run ESLint **without type-aware rules**, so the unawaited
Prisma call and the outer client used inside a transaction reach production
unchallenged. That is what this review is for.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the eight categories, and what not to report.
[INVARIANTS.md](INVARIANTS.md) is the generic non-negotiables. A diff review
reaches both through `review-routing` and never loads this file.

## Workflow

1. **Target.** One `*.service.ts`, `*.controller.ts`, guard, interceptor,
   pipe or module. None given — ask which.
2. **Project layer.** INVARIANTS.md, then `docs/review/nestjs-service-review.md`
   if the repository has one: tenant model, shared primitives, reference
   implementations, ceilings, deferred features. If it is absent, derive the
   same from `CLAUDE.md` / `AGENTS.md` and say so in one line. Then the file
   under review, **its spec** if one exists, and one sibling of the same kind
   as the consistency baseline.
3. **`scripts/inventory.sh [app-src]`** — shared primitives, module map,
   units missing a spec.
4. **`scripts/scan.sh <file>`** — mechanical pre-scan. Flags, not a verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/nestjs-service-review/scripts/`. `scan.sh`
reads `TENANT_FIELD` (default `tenantId`; `""` for single-tenant) and
`EXEMPT_MODELS` from the environment; the project layer says what to set.

## Effort

Default **medium**: 🔴 and 🟡 only, and **zero findings is a valid outcome**
— say so and stop. **high** adds ⚪ nits, still ranked.

## Output format

```
### <FileName> review

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

Most-severe first. Every finding names the why. Before/after is the two lines
that change. A clean category gets one line.
