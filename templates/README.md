# Project-layer templates

Each review rubric in this plugin is two layers:

1. **The rubric** — `CHECKLIST.md`, `INVARIANTS.md` / `INVENTORY.md` and the
   scripts. Framework knowledge. Ships here, applies to any codebase on that
   framework.
2. **The project layer** — reference implementations, shared primitives,
   known ceilings, deferred features. Codebase knowledge. Lives in **your**
   repository at `docs/review/<rubric-name>.md`, and the rubric loads it at
   step 2 of its workflow.

A rubric without a project layer still works: it reviews against the
framework rules and says in one line that it derived the project conventions
from `CLAUDE.md`. The project layer is what turns "this is a valid pattern"
into "this is the pattern *we* use, and here is the file that shows it".

Copy the template for each rubric you use, fill it in, commit it. Keep it
short — a reviewer that has to read a thousand lines before judging one file
will skim both.

| Template | Goes to |
| --- | --- |
| `react-review.md` | `docs/review/react-review.md` |
| `angular-review.md` | `docs/review/angular-review.md` |
| `nestjs-service-review.md` | `docs/review/nestjs-service-review.md` |
| `prisma-schema-review.md` | `docs/review/prisma-schema-review.md` |
| `api-contract-review.md` | `docs/review/api-contract-review.md` |
| `test-review.md` | `docs/review/test-review.md` |
| `observability-review.md` | `docs/review/observability-review.md` |
| `react-screen-authoring.md` | `docs/review/react-screen-authoring.md` |

## Script variables

The rubric scripts take project-specific names from the environment:

| Variable | Used by | Meaning |
| --- | --- | --- |
| `TENANT_FIELD` | nestjs, prisma | tenant key column; `""` for single-tenant |
| `EXEMPT_MODELS` | nestjs, prisma | models deliberately without the tenant key, `\|`-separated |
| `LEDGER_TABLES` | prisma | append-only tables by `@@map` name, `\|`-separated |
| `CLIENT_LIBS` | api-contract | package dirs that reach a client bundle |
| `INVENTORY_LIMIT` | all `inventory.sh` | lines per section before the output is cut with an overflow count (default 40) |
| `INVENTORY_DOCS` | react, angular | `1` adds each module's first doc-comment line |
| `REVIEW_FILES` | nestjs | space-separated files under review; limits the missing-spec check to them |
| `LOG_CALL`, `SECRETS` | observability | regex for the project's log call; extra field names that must never be logged |
| `TEST_CMD` | test `revert-check.sh` | command that runs the test files passed to it, when detection from `package.json` is wrong |
| `STATIC_SKIP`, `STATIC_TEST` | `static-gate.sh` | steps to skip (`typecheck lint format test prisma`); override for the related-tests command |

## The other way: fork the rubric into the project

When a rubric needs more than a project layer — different checklist rules,
scripts that read project config, severity floors tied to your review SOP —
copy the whole skill directory into `.claude/skills/<name>/` in your
repository and edit it there. A project skill with the same name shadows the
plugin's.
