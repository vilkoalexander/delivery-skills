# Phase 2: the plan

Read at the start of phase 2. Do the sections in this order:

1. Write the Global Constraints.
2. Ask the questions.
3. Classify the files.
4. Cut the chunks.
5. Give each chunk a risk class.
6. Put the chunks in order.
7. Show the cut and wait.

Script paths start at `skills/` of this plugin.

## 1. The Global Constraints

Each implementer and each task reviewer needs the rules of the project that
have no exceptions. SDD sends them through the `[GLOBAL_CONSTRAINTS]`
placeholder of its task-reviewer prompt. SDD fills the placeholder from the
`## Global Constraints` section of the plan. This is the only approved path
for project rules to a dispatched reviewer.

Write the block one time and put it in the plan file. Its sources are:

1. `CLAUDE.md` or `AGENTS.md` of the project: each rule that the file calls
   blocking, non-negotiable, or a one-way door.
2. A review procedure of the project, if there is one (`docs/PR-REVIEW.md`,
   `CONTRIBUTING.md`).
3. The two lines from `static-gate.sh coverage` (below).
4. If the project has `GLOSSARY.md`, this line: `- A domain thing has the
   name that GLOSSARY.md gives it. A thing with no term there is a BLOCKED
   report, not a new name.`
5. These rules, which apply to all projects:

```
## Global Constraints
- Never run git commit, git add, git push, or open a PR. Work stays uncommitted.
- Names describe behaviour — never a sprint, quarter, wave or ticket number.
- Follow the patterns already in the files being changed, not a better idea.
- A new util, hook, component or service helper only when the shared-layer inventory shows none; the report names the search.
- No new abstraction — interface, generic, base class, wrapper, factory — with fewer than two callers in this diff.
- No new runtime dependency unless the plan task names it.
- A test that still passes with the change reverted is not a test. Assert the
  behaviour the change adds, or leave the test out.
- A test that existed before the run is not edited, skipped or deleted to make
  a change pass, unless the plan task names that test file.
- A check that fails is corrected at its cause. No `eslint-disable`,
  `@ts-ignore`, `as any` or "for now" comment to get past it. A rule that is
  wrong for one line is silenced with the reason on that line, and the report
  names it.
- Comments: none by default; rename, extract or type it first. One line, and
  only for why this and not the obvious alternative, an outside constraint, a
  warning about what breaks if edited, or a workaround with its removal
  condition. On a constant or an interface field: only units, where a number
  comes from, a domain term, or what null means. Never restate the code,
  describe the change, or name a ticket, PR, date or link. Leave an existing
  comment alone unless the change makes it false.
- A chunk is sized by its closer-look files: ~300 lines, ≤8 files, ≤20 files
  total; a reviewer that sees more reports the overrun as a finding.
- Text a person reads (reports, findings, questions, comments, documents) is
  Simplified Technical English: short sentences, one instruction each, active
  voice, the same word for the same thing.
- <project invariants, one line each, each stated as a rule a reviewer can check>
```

- The comment line is a short form of `RULES.md` in `comment-cleanup`. Change
  the two together.
- Keep the block short. A long block is not read.
- A rule for one task goes in the text of that task, not in the block.

### The two lines from `coverage`

Run `bash delivery-pipeline/scripts/static-gate.sh coverage` one time for each
run. It prints what the project enforces: strict flags, type-aware lint, the
rules of each rubric at error, warn or absent, prettier, module boundaries and
pre-commit. It ends with an `ABSENT:` list. Add these two lines to the block:

```
- Enforced by tooling, never a finding: <rules at error>
- Not enforced, reviewers report: <the ABSENT list>
```

The "Tooling coverage" step of a rubric reads these lines. It does not run
`eslint --print-config` for each review.

## 2. Ask the questions

A decision that the planner made alone is a common cause of a bad run. Before
you classify a file or cut a chunk, ask the human about each such decision.
Use `mattpocock-skills:grilling` if it is available. If it is not, obey these
rules:

1. **Make the list of open decisions.** Include each decision in the plan
   that the design document or the conversation did not make: order and cut,
   hardcoded values, bounds and limits, flag or no flag, reuse or new, error
   paths, permitted callers, and what the acceptance criteria do not say. Do
   not ask again about a decision that the human made.
2. **You find facts. The human makes decisions.** A fact is in the repository.
   Dispatch an Explore agent for it. Do not ask the human. A decision that
   depends on a fact waits for the agent.
3. **Ask the full list as one round.** Give each question a number and a
   recommended answer. Write the question so that "yes" accepts your answer.
   The round is the full message. Do not add the chunk list or preflight
   results. The only other line permitted is the number of questions that
   wait for a repository search.
4. **Write each answer into the plan file,** in the task that it changes.
   Then make the list again and ask the next round.
5. **Stop when the list is empty.** Say so in one line. Then classify and cut.
   If the human says `cut` during a round, stop. Write each open question into
   the plan as an `Assumed:` line with your recommended answer. The human sees
   these lines at the approval of the cut, and the whole-tree reviewer sees
   them too.

A question that you can see in the plan before the first dispatch is a round
question, even a small one. A ruling is only for a question that first appears
inside a chunk.

A ruling cannot reverse a decision that the human made or that the plan
states. If you think that such a decision is wrong, stop. Ask one question,
alone in the message. Quote the decision and where it comes from. Do not put
the reversal in a list of calls that the human can overrule.

## 3. Classify the files

Put each file that the plan touches into one of two groups.

| Group | What goes in it |
| --- | --- |
| **Closer look**: a reviewer must think about it | schema and migrations; shared contracts and public types; services and handlers; hooks, builders and view-model logic; components with branches; all that touches money, auth or tenancy |
| **Glance**: a reviewer sees that it exists and continues | specs and fixtures; locale bundles; prop plumbing and barrel exports; generated files; docs; e2e flows; deletions with no callers left |

Only the closer-look files set the size of a chunk. Glance files go with their
chunk and are not a reason for a split.

## 4. Cut the chunks

The size of a chunk comes from how much needs a close read. It does not come
from how much a feature needs to be complete.

- 300 closer-look lines at most, approximately.
- 8 closer-look files at most.
- 20 files in total at most.

These are limits, not targets. The target is a chunk that the human can read
in one sitting.

Split a slice that is larger than a limit, in this order:

1. The data and contract cut: schema, migration, shared types, endpoint, and
   its tests. A request verifies it.
2. The screen cut that uses it. A tap verifies it.

Each half ends in something that the human can exercise. "It only demos as a
whole" is not a reason to go above a limit.

## 5. Give each chunk a risk class

Each plan task has one class. Classify on what the task touches, not on how
difficult it looks. One match puts the task in that row.

| Class | One or more of these | If it is wrong |
| --- | --- | --- |
| **high** | Prisma schema or migration; the shared contract package (`libs/shared`, `packages/contracts`, or the name that the project uses); auth, guards, strategies, sessions; payments, ledger, billing; a delete of data or a drop of a column; env, secrets, CI, deploy; the public API surface | Data is lost or exposed, or consumers break with no error |
| **medium** | NestJS service, controller or module logic; a shared primitive, hook or util (`components/ui`, `hooks`, `lib`, `utils`) with callers outside the chunk; a changed signature that other code calls; state store, data fetching, error handling; a new runtime dependency; more than five files or three hundred lines | A behaviour bug that others depend on. A normal fix round corrects it |
| **low** | Feature-local UI (`features/<x>/…`, a leaf component); styling, copy, i18n; tests, docs, dev-tooling config; additive code with no callers; a rename inside one file; five files or fewer | It is visible and local, and the human sees it |

Rules:

- A chunk gets the highest class of its tasks.
- If two rows match, the higher row wins. Do not average.
- If you are not sure, the class is medium. Low is not a default.
- The human sees the class of each chunk in the chunk list. To raise a class
  needs no reason. To lower a class needs a reason of one line in the plan.

Escalators. A small number of files does not cancel these:

- You cannot name the callers of what changes: medium or higher.
- The change touches the path of production data: high.
- The change alters what a caller gets now, with no flag before it: one
  class up.
- Additive code behind a flag that ships off keeps the class of its paths.

### `risk.sh`

`bash delivery-pipeline/scripts/risk.sh <paths…>` prints the class of each
path with the rule that matched, then the class of the set. You can also send
the paths on stdin. With no paths, it takes each path that differs from
`HEAD` in the working tree, new files included.

- The script sees paths, not content. Its class is a minimum, not a verdict.
- `risk.high` and `risk.medium` in `docs/review/delivery.json` add the paths
  of the project that are always high or always medium.
- A `mixed:` line tells you that a dependency change shares the chunk with
  other paths. Put a version bump in its own chunk. A new dependency stays
  with the code that uses it.
- The last line tells you who examines the escalators:
  - `escalators: controller`: you examine the escalators above yourself. At
    the cut, use the plan text. In the loop, use the implementer reports.
  - `escalators: jev`: the content pass asked them for each file and raised
    the class. Its `unsure:` lines go into the chunk list for the human to
    decide. `references/risk-content.md` tells you how it decides.

## 6. Put the chunks in order

Start with the leaves. A change to what a caller gets now is its own chunk.
Put it as late as the plan permits. Put it behind a flag if the project has
flags. Then the exposure of trunk is one small chunk that the human reads
most carefully.

## 7. Show the cut and wait

Before the first dispatch:

1. Use the output of `coverage` from section 1. Run
   `bash reuse-guardrails/scripts/audit.sh`.
2. If `coverage` ends with a `SETUP:` line, or the lists `ABSENT:` and `MISS:`
   have items, put them into one **tooling chunk**. Put it first in the list
   and mark it optional. Offer it. Do not add it unless the human accepts it.
   If the human accepts it, read the sections of
   `delivery-pipeline/STATIC-SETUP.md` that the `SETUP:` line names. Those
   sections are the task text for its implementer.
3. Show the chunk list. Each chunk has:
   - a name;
   - a risk class;
   - one line that says what it does;
   - its size as `closer-look N files / ~M lines, total F files`, with the
     names of the closer-look files;
   - a `criteria:` line with the acceptance criteria of the plan that it
     completes;
   - an `exercise:` line: the one request or tap that proves it. The verifier
     runs it. When the project has a feature map in `docs/review/features/`,
     the line names the feature by its file name;
   - a `tests:` line: the behaviours that the test author asserts before
     there is code, one for each criterion. Write `none — <reason>` only for
     a task with no behaviour: a rename, config, copy, docs, tooling, or a
     task that is tests only.
4. Add each `unsure:` line and each `Assumed:` line.
   If `bash verify-recipe/scripts/check.sh` does not end with `ok`, add its
   last line. With no recipe, each verifier finds again how to start the
   project. The `verify-recipe` skill writes or corrects the recipe, not
   during a run.
   Add each `DRIFT` line of `bash delivery-pipeline/scripts/stamp.sh check`.
   The code changed after that document was last confirmed, thus a verifier
   or a reviewer that reads it can be wrong.
5. End the list with `Approve: "go" · "long" (no stop after a clean chunk)`.
6. **Wait for the approval.** A list without the sizes and the three lines
   is not ready for approval.

`go` starts the loop with a stop after each chunk. `long` starts long-run
mode: read `references/long-run.md`. The end of the questions and the approval
of the cut are the only approvals for the plan as a whole. After them, the
approval is for each chunk.
