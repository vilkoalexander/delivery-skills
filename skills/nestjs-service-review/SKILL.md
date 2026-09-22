---
name: nestjs-service-review
description: Use when asked to review a single NestJS backend file (*.service.ts, *.controller.ts, guard, interceptor, pipe or module), check whether a service or controller is okay, or sanity-check AI-generated NestJS code one file at a time. For a whole diff or PR, go through review-routing instead.
---

# NestJS Service Review

Structured review of ONE NestJS backend file. Report + suggest — never edits
the file. Built for sanity-checking AI-generated backend code one unit at a
time.

Most NestJS projects run ESLint **without type-aware rules**, so a whole class
of async bugs — the unawaited Prisma call, the outer client used inside a
transaction — reaches production unchallenged. That is what this skill is
for.

## Workflow

1. **Identify the target.** One `*.service.ts`, `*.controller.ts`, guard,
   interceptor, pipe, or module. If none was given, ask which.
2. **Load the project layer** (do not skip):
   - [INVARIANTS.md](INVARIANTS.md) — the generic non-negotiables.
   - `docs/review/nestjs-service-review.md` if the repository has one — the
     project's tenant model, shared primitives, reference implementations,
     ceilings and deferred features. If it is absent, derive the same from
     `CLAUDE.md` / `AGENTS.md` and say in one line that you did.
   - The file under review, and **its spec** if one exists.
   - One sibling of the same kind — the consistency baseline.
3. **Run `scripts/inventory.sh [app-src]`** — shared primitives, the module
   map, and the files currently missing a spec.
4. **Run `scripts/scan.sh <file>`** — mechanical pre-scan. Heuristic, not a
   gate.
5. **Walk [CHECKLIST.md](CHECKLIST.md)** — all 8 categories, in order.
6. **Emit the report** (format below). Do not edit the file.

Scripts live next to this file. Installed as a plugin, that is
`${CLAUDE_PLUGIN_ROOT}/skills/nestjs-service-review/scripts/`. `scan.sh`
reads `TENANT_FIELD` (default `tenantId`, set `""` for single-tenant) and
`EXEMPT_MODELS` from the environment; the project layer says what to set.

## Effort scaling

Default is **medium**. The user may say low / medium / high.

- **low / medium** — only findings you would defend out loud in review: 🔴 and
  🟡. Roughly 7 findings max. **Zero findings is a valid, expected outcome.**
- **high** — add ⚪ nits and lower-confidence observations, still ranked.

## Rule confidence

- **[hard]** — never correct. Always report.
- **[prefer]** — the right default. Report unless the file gives a reason not
  to.
- **[context]** — depends. Report only when you can name the concrete
  consequence *in this file*.

## Severity floor

Always 🔴, regardless of effort:

- in a multi-tenant service, a query on a tenant-scoped model without the
  tenant key in its `where`
- anything that answers a cross-tenant miss with 403 instead of 404
- the outer Prisma client used inside a `$transaction` callback
- a Prisma call or `$transaction` that is neither awaited, returned, nor
  assigned

## Do NOT report

- Anything ESLint already **errors** on in this project (see coverage below).
- Restating the project's instructions file as if it were a finding.
- **Missing e2e tests** — this skill reviews one unit. Unit + controller
  delegation spec is the ask; e2e coverage is a PR-level concern.
- Features the project has documented as deferred. Check the project layer;
  do not propose them as gaps.
- Renaming things after sprints or tickets.
- TODO shapes the project mandates.

## Tooling coverage

Do not assume what lint catches. Run once per review:

```bash
npx eslint --print-config <file> | grep -E '"parserOptions"|"project"|no-floating-promises|no-misused-promises|require-await|no-console|no-explicit-any'
```

If `parserOptions.project` is unset there is **no type-aware linting at all**,
and these have zero coverage — squarely this skill's job:

- `no-floating-promises` — an unawaited `prisma.*` call or `$transaction`
  silently resolves after the response is sent
- `no-misused-promises` — an async callback passed where void is expected
- `require-await` / `await-thenable`
- `no-console`

Rules at `"warn"` do not fail the build — still report. `scripts/scan.sh`
targets the commonly absent set.

## Output format

Findings ranked most-severe first. Every finding names the WHY.

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

Keep before/after minimal. If a checklist category is clean, say so in one
line.

## Version baseline

Read before applying §3, §4 and §7 of the checklist:

```bash
node -e 'const p=require("./package.json");for(const k of ["@nestjs/core","@nestjs/common","prisma","@prisma/client","nestjs-zod","zod","class-validator","@nestjs/swagger","jest","vitest"])console.log(k,(p.dependencies||{})[k]||(p.devDependencies||{})[k]||"-")'
```

The switches: **validation library** (`nestjs-zod` vs `class-validator`
changes §4's DTO rules); **Prisma 5+** (`$extends` replaces `$use`; §8);
**NestJS 11** (Express 5 route syntax); **NestJS 12** (ESM, Standard Schema,
Vitest) — do not recommend a version the project has not adopted.
