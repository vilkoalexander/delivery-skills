---
name: review-routing
description: Use when reviewing a diff, a branch, or a pull request, when dispatched as a task reviewer against a base..head range or a diff snapshot, or when asked "which review skill applies here". For reviewing one named file, invoke that domain rubric directly instead.
---

# Review Routing

Domain review rubrics each cover one slice of a codebase and are written to
review **one file**. A diff review sees many files at once. This routes the
diff to the right rubrics and says how to apply them without re-reviewing the
whole repository.

Invoke this before judging any diff. A project may ship its own
`review-routing` skill; if it does, that one wins outright — it is this file
with the project's real paths filled in.

**A scoped re-review never comes here.** It checks the findings it was handed
against the fix diff. It loads no rubric, runs no script, and reads nothing
but the fix diff and the findings list.

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

## What to load per rubric

A rubric lives at `${CLAUDE_PLUGIN_ROOT}/skills/<rubric>/`, or at
`.claude/skills/<rubric>/` when the project forked it. Read **two files** from
it directly. Do not invoke the rubric as a skill: its `SKILL.md` is the
single-file entry point and adds nothing to a diff review.

- `CHECKLIST.md` — version baseline, tooling coverage, severity floor, the
  rules tagged **[hard]** (always report), **[prefer]** (report unless the
  file gives a reason not to) and **[context]** (report only with a concrete
  consequence in this file), and the do-not-report list.
- `INVARIANTS.md` (backend, schema, contract) or `INVENTORY.md` (UI).

Plus the **project layer** the rubric names — `docs/review/<rubric>.md` when
the repository has one. It carries the reference implementations, shared
primitives and ceilings that belong to this codebase, not to the framework.

## Applying a single-file rubric to a diff

- **The diff is your view of the file.** The diff's context lines are the code.
  Do not open a changed file separately unless a hunk you must judge is cut off
  mid-function — and say in your report when you did.
- **One pass per rubric, not per file.** A diff touching six services gets one
  `nestjs-service-review` pass covering all six, ranked together.
- **Judge what the change contributed.** A pre-existing violation in untouched
  code is not this diff's finding. A violation the diff introduces, or leaves
  standing in a block it rewrites, is.
- **Run the mechanical scans, bounded by the diff.** `scripts/scan.sh <file>`
  per changed file the rubric owns, and `scripts/inventory.sh` once per
  rubric. Inventory output is capped at `INVENTORY_LIMIT` lines per section
  (default 40); pass the changed file or root where the script takes one, and
  set `REVIEW_FILES` for the NestJS one so its spec check covers only the
  files under review. Script output is a set of flags to judge, never a
  verdict.
- **Cross-file risk is in scope when you can name it.** A changed service
  method signature, a renamed shared type, an altered delete action — check the
  call sites, and name both the risk and the check in your report. Opening
  files to see what else might be interesting is not that.

## Multi-domain diffs

When a diff spans two or more rows, run each rubric as its own pass, then merge
the findings into one ranked list. Do not emit a section per rubric — the
reader wants severity order, not a tour of the taxonomy.

When the controller fans out one reviewer per rubric, each reviewer gets only
its rubric's slice of the diff (`git diff -- <paths>`), not the whole
snapshot. A reviewer handed a full snapshot reads only the hunks its rubric
owns.

A change that crosses the shared contract package and any of its consumers is
a contract change first. Run `api-contract-review` before the others: if the
shape is wrong, findings in the consumers are downstream noise.

## Effort and severity

Default effort is **medium**: 🔴 and 🟡 only, and zero findings is a valid
outcome. **high** adds ⚪ nits, still ranked.

The rubrics emit 🔴 / 🟡 / ⚪. A diff review that reports under Critical /
Important / Minor headings maps them:

| Rubric | Diff review | Meaning |
| --- | --- | --- |
| 🔴 | Critical | Merge blocker. Ship with this and something is broken or exposed. |
| 🟡 | Important | The change cannot be trusted until it is fixed. |
| ⚪ | Minor | Worth saying once, blocks nothing. |

Each checklist carries a **severity floor** — findings that are always 🔴 at
any effort. A project's review SOP may add more; those are Critical too. Each
checklist's **Do NOT report** list still binds in diff review; it is what
keeps these reports free of out-of-scope suggestions and restated project
instructions.
