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
| `spring-service-review.md` | `docs/review/spring-service-review.md` |
| `jpa-schema-review.md` | `docs/review/jpa-schema-review.md` |
| `api-contract-review.md` | `docs/review/api-contract-review.md` |
| `test-review.md` | `docs/review/test-review.md` |
| `observability-review.md` | `docs/review/observability-review.md` |
| `security-review.md` | `docs/review/security-review.md` |
| `react-screen-authoring.md` | `docs/review/react-screen-authoring.md` |
| `verify.md` | `docs/review/verify.md` — not a rubric layer: how an agent starts, drives and cleans up the app. The `verify-recipe` skill writes it |
| `verify-feature.md` | `docs/review/features/<feature>.md` — one per user-facing feature, with a `README.md` index beside them |
| `drift.checks` | `docs/review/drift.checks` — not a rubric layer: the drift checks the static gate runs |
| `delivery.json` | `docs/review/delivery.json` — not a rubric layer: the stack, the command each static step runs per workspace, and the project's patterns. `static-gate.sh init` drafts it |

## The `As of:` line

`bash skills/delivery-pipeline/scripts/stamp.sh set <file>` writes ``As of: `<commit>` ``
below the title of a document here: the commit of HEAD, at which somebody
last confirmed the document against the code. Do it after you fill a layer
or read it through again. `stamp.sh check` compares each file and directory
that the document names in backticks with that commit and prints `DRIFT`
for a document whose code changed, and `UNSTAMPED` for one with no line. A
document that names no path never drifts. After a squash or a rebase the
commit is gone; the check then uses the last commit of the document.

## delivery.json

| Key | Read by | Meaning |
| --- | --- | --- |
| `stack` | `review-routing` | frameworks in the repo; a rubric for one not listed is not routed. `spring` and `jpa` are the Java ones |
| `writing` | `chunked-delivery` | `ste100` (default): reports, findings, questions, comments and documents of a run are ASD-STE100 Simplified Technical English. `free` sets it off |
| `workspaces.<dir>.<step>` | `static-gate.sh check` | the command for `typecheck`, `lint`, `format`, `test` or any step you name, run in `<dir>`. A string runs whenever the workspace changed; `{ "run", "files" }` runs only when a changed path matches `files`; `false` says the workspace has none. `{files}` becomes the changed paths that still exist, relative to `<dir>`. A changed path belongs to the longest `<dir>` that contains it; `.` is the root |
| `risk.high`, `risk.medium` | `risk.sh` | patterns for paths that are always that class |
| `secrets.allow` | `secret-scan.sh` | patterns over `path:line:text` for added lines that are not credentials |
| `escapes.allow` | `escape-scan.sh` | patterns over `path:line:text` for added lines that are not escapes: a suppression or a cast the project accepts |
| `deps.allow`, `deps.minAgeDays`, `deps.minVersionDays` | `dep-vet.sh` | package names never vetted (private scopes); youngest package and version an agent may fetch (30, 7) |
| `shared` | `reuse-scan.sh` | patterns for shared-layer directories |

Patterns are POSIX ERE. An environment variable of the matching name
(`RISK_HIGH`, `SECRET_ALLOW`, `ESCAPE_ALLOW`, `DEP_VET_ALLOW`, `REUSE_SHARED`) overrides the
file for one call.

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
| `REVIEW_FILES` | nestjs, spring | space-separated files under review; limits the missing-spec check to them |
| `LOG_CALL`, `SECRETS` | observability | regex for the project's log call; extra field names that must never be logged |
| `INPUT`, `GUARD` | security | extra names that hold outside input; regex for what authorizes a handler or marks it public, `""` when a global guard or URL rules decide |
| `AUTHZ` | spring | regex for the annotations that authorize a handler; `""` when the project authorizes by URL |
| `REMOTE_CALL` | spring | regex for calls that leave the process: HTTP, object store, bot, mail |
| `MIGRATION_BASE` | jpa | git ref a merged migration is compared with (default `HEAD`; the base branch in a branch review) |
| `MIGRATION_NAME` | jpa | regex for a valid migration file name, when the project does not use Flyway's |
| `TEST_CMD` | test `revert-check.sh` | command that runs the test files passed to it, when detection from `package.json` is wrong |
| `STATIC_SKIP` | `static-gate.sh` | steps to skip for one call: `test-lock`, `drift`, `secrets`, `reuse`, `escapes`, or any step name from `delivery.json` |

## The other way: fork the rubric into the project

When a rubric needs more than a project layer — different checklist rules,
scripts that read project config, severity floors tied to your review SOP —
copy the whole skill directory into `.claude/skills/<name>/` in your
repository and edit it there. A project skill with the same name shadows the
plugin's.
