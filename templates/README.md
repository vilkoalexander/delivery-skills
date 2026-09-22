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

## The other way: fork the rubric into the project

When a rubric needs more than a project layer — different checklist rules,
scripts that read project config, severity floors tied to your review SOP —
copy the whole skill directory into `.claude/skills/<name>/` in your
repository and edit it there. A project skill with the same name shadows the
plugin's.
