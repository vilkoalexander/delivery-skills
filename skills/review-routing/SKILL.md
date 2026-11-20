---
name: review-routing
description: Use when reviewing a diff, a branch, or a pull request, when dispatched as a task reviewer against a base..head range or a diff snapshot, or when asked "which review skill applies here". For reviewing one named file, invoke that domain rubric directly instead.
---

# Review Routing

Domain review rubrics each review **one file**; a diff touches many. This
routes a diff to its rubrics and says how to apply them without re-reviewing
the repository.

Invoke this before judging any diff. A project's own `review-routing` skill
wins outright: it is this file with the project's real paths filled in.

**A scoped re-review never comes here.** It checks the findings it was handed
against the fix diff. It loads no rubric, runs no script, and reads only the
fix diff and the findings list.

## Routing table

Match every changed path against this table; a diff may hit several rows.
Match on the file's **shape** (suffix, extension, directory role), not on
directory depth: backend units nest.

| Changed path looks like | Rubric |
| --- | --- |
| `*.service.ts`, `*.controller.ts`, `*.module.ts`, `*.guard.ts`, `*.interceptor.ts`, `*.pipe.ts`, `*.filter.ts`, `*.strategy.ts` under a NestJS app | `nestjs-service-review` |
| `schema.prisma`, `prisma/models/*.prisma`, `prisma/migrations/**/*.sql` | `prisma-schema-review` |
| `*Controller.java`, `*Service.java`, `*ServiceImpl.java`, and any other `*.java` under `src/main` of a Spring application that is not in the next row: configuration, filter, listener, handler, aspect, scheduled job. Also `application*.yml` / `application*.properties` | `spring-service-review` |
| `*Entity.java` and any class with `@Entity`, `@MappedSuperclass` or `@Embeddable`; `*Repository.java`, `*Specification.java`; `db/migration/**/*.sql` and any `V<version>__<name>.sql` | `jpa-schema-review` |
| `*Test.java`, `*Tests.java`, `*IT.java`, anything under `src/test`, `src/testFixtures`, `src/integrationTest` of a Java module | `spring-service-review` (its §7 Tests) |
| A shared contract package consumed by more than one app — `libs/shared/**`, `packages/shared/**`, `packages/contracts/**`, `packages/api-types/**`, or whatever the project names it | `api-contract-review` |
| `*.tsx` under a React or React Native app | `react-review` |
| `*.component.ts`, `*.directive.ts`, `*.pipe.ts` with an `@Component`/`@Directive`/`@Pipe` decorator, and their `.html` templates, under an Angular app | `angular-review` |
| `*.spec.ts`, `*.test.ts`, `*.test.tsx`, anything under `__tests__/`, `test/`, `tests/`, `e2e/` | `test-review` |
| Any backend runtime file — the NestJS row above plus `*.gateway.ts`, `*.processor.ts`, `*.consumer.ts`, `*.job.ts`, `*.middleware.ts`, `*.resolver.ts` — **in addition to** its own row | `observability-review` |

The two Java rows are routed by content when the name does not say: open the
first thirty lines and route on `@Entity` or `extends …Repository`. The other
rubrics are written for TypeScript: a Java file is not routed to
`test-review`, `observability-review` or `api-contract-review`. A request or
response class that a TypeScript client mirrors by hand is a contract change
all the same; name the client file that must change with it.

Two rows claim `*.pipe.ts`: an Angular pipe carries `@Pipe`, a NestJS pipe
implements `PipeTransform`. Open the first twenty lines and route on the
decorator.

When `docs/review/delivery.json` has a `stack`, it settles "under a NestJS
app", "under an Angular app" and the like: a row for a framework the stack
does not list is not routed.

No row matched (scripts, config, docs, plain `.ts` utilities) means no domain
rubric applies. Review those on general quality alone, say so in one line, and
do not stretch a rubric to reach them.

A matched row whose rubric you cannot load is a gap to report, not a reason to
skip the category.

## What to load per rubric

A rubric lives at `${CLAUDE_PLUGIN_ROOT}/skills/<rubric>/`, or at
`.claude/skills/<rubric>/` when the project forked it. Read **two files** from
it directly; do not invoke it as a skill, since its `SKILL.md` adds nothing to
a diff review.

- `CHECKLIST.md` — version baseline, tooling coverage, severity floor, the
  rules tagged **[hard]** (always report), **[prefer]** (report unless the
  file gives a reason not to) and **[context]** (report only with a concrete
  consequence in this file), and the do-not-report list.
- `INVARIANTS.md` (backend, schema, contract) or `INVENTORY.md` (UI).

Plus the **project layer** the rubric names, `docs/review/<rubric>.md`, when
the repository has one: this codebase's reference implementations, shared
primitives and ceilings.

## Applying a single-file rubric to a diff

- **The diff is your view of the file.** Do not open a changed file
  separately unless a hunk you must judge is cut off mid-function, and say so
  in your report.
- **One pass per rubric, not per file.** Six changed services get one
  `nestjs-service-review` pass, ranked together.
- **Judge what the change contributed.** A pre-existing violation in untouched
  code is not this diff's finding; one the diff introduces, or leaves standing
  in a block it rewrites, is.
- **Run the mechanical scans, bounded by the diff.** `scripts/scan.sh <file>`
  per changed file the rubric owns, `scripts/inventory.sh` once per rubric
  (capped at `INVENTORY_LIMIT` lines per section, default 40). Pass the
  changed file or root where the script takes one; set `REVIEW_FILES` for the
  NestJS and the Spring one so the missing-test check covers only the files
  under review. Script
  output is flags to judge, never a verdict.
- **Run the reuse scan once over the whole diff.** `bash
  ${CLAUDE_PLUGIN_ROOT}/skills/reuse-guardrails/scripts/reuse-scan.sh` with
  the changed paths (or `REUSE_DIFF_RANGE=base..head`), or read the output the
  dispatch already carries from the static gate. Every flag is a finding
  unless the implementer's `## Reuse` block answers it by name; a
  `searched: … none found` line is an answer only when the inventory agrees.
  Rank a reinvention above a style finding; the human would otherwise catch it
  by hand.
- **Read the escape flags once over the whole diff.** `bash
  ${CLAUDE_PLUGIN_ROOT}/skills/delivery-pipeline/scripts/escape-scan.sh` with
  the changed paths (or `ESCAPE_DIFF_RANGE=base..head`), or read the output
  the dispatch already carries from the static gate. Every flag is a finding
  unless the line silences a rule that is wrong for that line and says why,
  or names a workaround for a cause outside the code with its removal
  condition. The finding names the cause to fix, never a better comment. A
  comment that keeps two copies in sync is a finding for a drift check.
- **Cross-file risk is in scope when you can name it.** A changed service
  method signature, a renamed shared type, an altered delete action: check the
  call sites and name both the risk and the check in your report. Browsing
  for anything else interesting is not that.

## Multi-domain diffs

A diff spanning two or more rows gets one pass per rubric, merged into one ranked
list. No section per rubric; the reader wants severity order.

When the controller fans out one reviewer per rubric, each gets only its
rubric's slice of the diff (`git diff -- <paths>`), not the whole snapshot. A
reviewer handed a full snapshot reads only the hunks its rubric owns.

`test-review` judges the tests against the diff they cover, so it reads the
non-test hunks too; a revert-check result handed to you is the first set of
findings. `observability-review` is a second pass over the backend rows, never
a replacement for `nestjs-service-review`; given its own seat, that reviewer
runs only this row.

A change with an entity or a migration and the service that uses it is a
schema change first. Run `jpa-schema-review` before `spring-service-review`;
if the mapping or the migration is wrong, the service findings are downstream
noise. Pass `MIGRATION_BASE=<base>` to its `scan.sh` so an edited migration is
compared with the base of the diff, not with `HEAD`.

A change crossing the shared contract package and any of its consumers is a
contract change first. Run `api-contract-review` before the others; if the
shape is wrong, consumer findings are downstream noise.

## Effort and severity

Default effort is **medium**: 🔴 and 🟡 only, and zero findings is a valid
outcome. **high** adds ⚪ nits, still ranked.

The rubrics emit 🔴 / 🟡 / ⚪. A diff review reporting under Critical /
Important / Minor headings maps them:

| Rubric | Diff review | Meaning |
| --- | --- | --- |
| 🔴 | Critical | Merge blocker. Ship with this and something is broken or exposed. |
| 🟡 | Important | The change cannot be trusted until it is fixed. |
| ⚪ | Minor | Worth saying once, blocks nothing. |

Each checklist's **severity floor** lists findings that are always 🔴 at any
effort; a project's review SOP may add more, also Critical. Each checklist's **Do NOT
report** list still binds in diff review and excludes out-of-scope
suggestions and restated project instructions.
