---
name: review-routing
description: Use when reviewing a diff, a branch, or a pull request, when dispatched as a task reviewer against a base..head range or a diff snapshot, or when asked "which review skill applies here". For reviewing one named file, invoke that domain rubric directly instead.
---

# Review Routing

Domain review rubrics each cover one slice of a codebase and are written to
review **one file**. A diff review sees many files at once and has no single
target. This routes the diff to the right rubrics and says how to apply them
without re-reviewing the whole repository.

Invoke this before judging any diff. It costs one read and stops a reviewer from
grading backend code against frontend conventions.

A project may ship its own `review-routing` skill. If it does, that one wins
outright — it is this file with the project's real paths filled in.

## Routing table

Match every changed path against this table. A diff may hit several rows.
Match on the file's **shape** (suffix, extension, directory role), not on a
fixed directory depth — backend units nest.

| Changed path looks like | Rubric |
| --- | --- |
| `*.service.ts`, `*.controller.ts`, `*.module.ts`, `*.guard.ts`, `*.interceptor.ts`, `*.pipe.ts`, `*.filter.ts`, `*.strategy.ts` under a NestJS app | `nestjs-service-review` |
| `schema.prisma`, `prisma/models/*.prisma`, `prisma/migrations/**/*.sql` | `prisma-schema-review` |
| A shared contract package consumed by more than one app — `libs/shared/**`, `packages/shared/**`, `packages/contracts/**`, `packages/api-types/**`, or whatever the project names it | `api-contract-review` |
| `*.tsx` under a React or React Native app | `react-review` |
| `*.component.ts`, `*.directive.ts`, `*.pipe.ts` with an `@Component`/`@Directive`/`@Pipe` decorator, and their `.html` templates, under an Angular app | `angular-review` |

Two rows can claim `*.pipe.ts`. An Angular pipe carries `@Pipe`; a NestJS pipe
implements `PipeTransform`. Open the file's first twenty lines and route on the
decorator.

No row matches — tests, scripts, config, docs, plain `.ts` utilities — means no
domain rubric applies. Review those on general quality alone and say so in one
line rather than stretching a rubric to reach them.

A path that matches a row but whose rubric you cannot load is a gap worth
reporting, not a reason to skip the category.

## Applying a single-file rubric to a diff

Each rubric ships `CHECKLIST.md` plus `INVARIANTS.md` (or `INVENTORY.md` for
the UI rubrics). Those two files are the rubric. Load them; they are what the
domain knowledge lives in. Each rubric also names where the **project layer**
comes from — the reference implementations, shared primitives and ceilings that
belong to this codebase and not to the framework. Load that too.

- **The diff is your view of the file.** The diff's context lines are the code.
  Do not open a changed file separately unless a hunk you must judge is cut off
  mid-function — and say in your report when you did.
- **One pass per rubric, not per file.** A diff touching six services gets one
  `nestjs-service-review` pass covering all six, ranked together. Six passes
  produce six reports nobody reads.
- **Judge what the change contributed.** A pre-existing violation in untouched
  code is not this diff's finding. A violation the diff introduces, or leaves
  standing in a block it rewrites, is.
- **Run the mechanical scans, bounded by the diff.** `scripts/scan.sh <file>`
  per changed file the rubric owns, and `scripts/inventory.sh` once. Both are
  cheap and repo-local. Their output is a set of flags to judge, never a
  verdict.
- **Cross-file risk is in scope when you can name it.** A changed service
  method signature, a renamed shared type, an altered delete action — check the
  call sites, and name both the risk and the check in your report. That is not
  crawling the codebase; opening files to see what else might be interesting
  is.

## Multi-domain diffs

When a diff spans two or more rows, run each rubric as its own pass, then merge
the findings into one ranked list. Do not emit a section per rubric — the
reader wants severity order, not a tour of the taxonomy.

A change that crosses the shared contract package and any of its consumers is
a contract change first. Run `api-contract-review` before the others: if the
shape is wrong, findings in the consumers are downstream noise.

## Severity translation

The domain rubrics emit 🔴 / 🟡 / ⚪. A diff review that reports under
Critical / Important / Minor headings maps them:

| Rubric | Diff review | Meaning |
| --- | --- | --- |
| 🔴 | Critical | Merge blocker. Ship with this and something is broken or exposed. |
| 🟡 | Important | The change cannot be trusted until it is fixed. |
| ⚪ | Minor | Worth saying once, blocks nothing. |

Each rubric carries a **severity floor** — findings that are always 🔴 at any
effort level. A project's review SOP may add more; those are Critical too.

Each rubric's own **Do NOT report** section still binds in diff review. It is
what keeps these reports free of out-of-scope feature suggestions and restated
project instructions.
