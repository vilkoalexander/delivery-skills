---
name: chunked-delivery
description: Use when asked to execute an approved plan with subagents in chunks, build a feature with the agent team, or pause for human review between units instead of running a plan end to end.
---

# Chunked Delivery

Plan together, then build in units small enough to read. After each unit the run
**stops** and hands back a diff. Nothing proceeds until a human says so, and
nothing is ever committed.

Built on `superpowers:subagent-driven-development` with two overrides:

> **Override 1.** SDD's continuous-execution rule ("do not pause to check in
> between tasks") does not apply; stopping at each chunk boundary is the point.
> Every other SDD rule holds, including rulings-not-stalls *within* a chunk:
> mid-chunk ambiguity gets decided, not escalated.
>
> **Override 2.** SDD's implementer step "Commit your work" does not apply.
> Nothing is committed, staged, pushed or merged at any point.

Read `delivery-pipeline` first. A project's own copy wins over the global one.

## Preflight

- The controller runs on the model `delivery-pipeline` names for the run's
  length and stays on it: a swap loses the plan and chunk summaries.
- Work in place, in the human's checkout, on a feature branch that is not
  `main` (create one if needed). Do NOT create or enter a git worktree unless
  the human explicitly asks for one in their message: it hides the diff and
  needs its own install and `.env`.
- The plan file exists and carries the Global Constraints block.
- Run `bash scripts/run.sh start` (next to this skill). It marks the checkout
  mid-run; the plugin's hooks then refuse every git write in this session,
  refuse the controller a read of any chunk snapshot, keep reviewer seats
  read-only and hold an implementer report that lacks its Proof block. A
  refusal is the rule working, not an obstacle to route around. The marker
  survives a crash: `run.sh status` shows it, `run.sh stop` clears it.

## Grill the plan

Decisions the planner made alone are where runs go wrong. Before any file is
classified or chunk cut, put them to the human in the shape of
`mattpocock-skills:grilling`. Without that skill, the contract is:

1. **Seed the frontier** with every call the plan makes that the design doc
   or conversation did not settle: order and cut, what is hardcoded, bounds
   and limits, flag or no flag, reuse or new, error paths, who may call it,
   what the acceptance criteria leave unsaid. A call the human already made
   is never asked again.
2. **Facts are yours, decisions are theirs.** A fact lives in the repo:
   dispatch an Explore agent for it, never the human. A decision that waits
   on a fact waits for the agent.
3. **Ask the whole frontier as one round**, numbered, each with a
   recommended answer worded so "yes" accepts it. The round is the entire
   message: no chunk list, no preflight findings, nothing else, except one
   line saying how many questions wait on a repo lookup still running.
4. **Fold each answer into the plan file**, in the task it changes, then
   recompute the frontier and ask the next round.
5. **Exit when the frontier is empty**, say so in one line, and go on to
   classify and cut. On `cut` mid-round, stop and write every open question
   into the plan as an `Assumed:` line with your recommended answer, visible
   at cut approval and to the whole-tree reviewer.

Rulings-not-stalls starts at dispatch: a question visible in the plan
beforehand is a round question, however small; a ruling is for one that
first appears inside a chunk.

## Plan shape

Plans group tasks into **chunks**, sized by how much needs a close read, not
by how much a feature needs to be whole.

### Classify before you cut

Before cutting, sort every file the plan will touch into two piles:

- **Closer look** — anything a reviewer must reason about: schema and
  migrations, shared contracts and public types, services and handlers,
  hooks, builders and view-model logic, components with branches, anything
  that touches money, auth or tenancy.
- **Glance** — anything a reviewer confirms exists and moves on: specs and
  fixtures, locale bundles, prop plumbing and barrel exports, generated
  files, docs, e2e flows, deletions whose callers are gone.

Glance files ride along with their chunk and are never a reason to split.
Only closer-look files set the size.

### Size limits

A chunk holds at most about **300 closer-look lines** across at most
**8 closer-look files**, and stays under **20 files in total**: ceilings, not
targets; a chunk that fits in a sitting is the goal.

A slice over the ceiling is split, in this order:
1. the data and contract cut (schema, migration, shared types, endpoint,
   its tests) — verifiable with a request;
2. the screen cut that consumes it — verifiable with a tap.
Each half still ends in something the human can exercise; "it only demos as
a whole" is no reason to exceed the ceiling.

### Risk and order

Each chunk carries a risk class per `delivery-pipeline` (its `scripts/risk.sh`
suggests one from the paths, and from the hunks too when `TYPESAFE_API_KEY`
is set; its `unsure:` lines go in the chunk list for the human to settle).
The class picks the models, whether the chunk is reviewed at all, and the
fix-round cap.

Order chunks leaf first. A change to what an existing caller already gets is
its own chunk, as late as the plan allows, behind a flag when the project has
flags, so trunk exposure is one small chunk the human reads hardest.

### Present the cut

Before any dispatch, run `static-gate.sh coverage` per `delivery-pipeline`
and `reuse-guardrails`' `scripts/audit.sh`; fold their `ABSENT:` and `MISS:`
lists into one optional tooling chunk, listed first and marked optional.
Then present the chunk list and **wait for approval**. Each chunk gets a
name, a risk class, one line of what it does, its size as
`closer-look N files / ~M lines, total F files` with the closer-look files
named, and an `exercise:` line: the one request or tap that proves it works,
which the verify seat will run. A list without those numbers and that line is
not ready to approve. Grilling exit and cut approval are the only plan-level
gates; after them, approval is per chunk.

If a chunk grows past the ceiling while being built, stop at the boundary,
say by how much and why, and offer a split before continuing.

## The loop

For each approved chunk, in order:

1. **Snapshot first.** Write `chunk-N-before.diff` per `delivery-pipeline`; it
   is the only undo this run has.
2. **Dispatch implementers.** One per task; parallel only when the tasks
   touch disjoint files; models per `delivery-pipeline`. Work stays
   uncommitted and unstaged; each report ends with the Proof block from
   `delivery-pipeline` or goes back for it.
3. **Snapshot the result** to `chunk-N.diff`, then **run the static gate**
   on the changed paths per `delivery-pipeline`: typecheck, lint, format,
   related tests, and the revert check when tests changed. A failure goes
   back to the implementer with the tool output as fix round zero; nothing
   else happens until it is clean. The gate ends with the reuse scan, whose
   flags never fail the gate but ride along to the reviewer and the report's
   `Reuse:` line. On a **low-risk chunk stop here**: no reviewer, no fix
   rounds; the human reads the proof, the reuse flags and the diff at the gate,
   and the whole-tree review covers it.
   Otherwise dispatch the task reviewer against
   the snapshot, with the line that sends it to the project's rubric routing
   if there is one. Do not read the snapshot yourself.
4. **Run fix rounds to clean.** Findings go back to the implementer, then a
   scoped re-review that gets the findings and the fix diff, nothing else.
   Say in one line that rounds are running. The counter trips at **three**
   on a medium-risk chunk and **five** on a high-risk one; the human reads
   the chunk next anyway, so a parked finding costs them a minute. Park what remains and say so in the report.
5. **Verify** on a medium- or high-risk chunk: dispatch the verify seat per
   `delivery-pipeline` with the chunk's `exercise:` line, the acceptance
   criteria it completes and the implementer's Proof block. A `FAIL` is one
   more fix round under the same cap, then the failed lines are re-run.
6. **Cross-model review** if the chunk is high-risk; `delivery-pipeline` has
   the invocation and adjudication rules. Its findings are claims you rule
   on, not a fix queue.
7. **Stop and report** in the format below.
8. **Wait.** Do not start the next chunk, do not prepare it, do not read ahead.

## The chunk report

The human reads this; the ledger is crash recovery and never appears in a
report. Counts come from `git diff --stat`, the `Files` line from
`git diff --name-only | bash scripts/risk.sh`, the `Changed` lines from the
implementer and reviewer reports; the controller does not read the diff to
write it.

```
Chunk N/M — <name>   [risk]
<files> files changed, <added>/<removed> lines

Files:   high: <each path> · medium: <each path> · low: <count> files
         (from `scripts/risk.sh` on the after-snapshot; read high closely,
          skim medium, take low on its proof)

Changed: <three to five lines. What it now does and why — not a file list.>

Flow:    <an ASCII flow, or omit the line — see below>

Proof:   <one line per task — ran · shows · exercised, condensed from the
          implementer's block — then "not verified: <items>" or
          "not verified: nothing">

Verified: <one line per criterion and claim from the verify seat — pass with
          what it saw, FAIL fixed in round N, or "needs human: <tap>" — or
          "not run — low risk">

Fixed:   <"static: clean" or "static: <n> type/lint/test failures, fixed";
          then one line per finding the review caught and the implementer
          fixed, or "not reviewed — low risk">
Parked:  <one line per finding left standing, each with its reason>
Reuse:   <"clean", or one line per reuse-scan flag the Reuse block did not
          answer and per "new shared" / "new dependency" line it did —
          what was added and why the inventory had nothing>
Cross:   <one line verdict, or "not run — low risk">
Rulings: <only decisions that could have gone the other way. Omit if none.>

Read it:  git diff
Map:      <link>   (only when a map was published)
Next:     "next" · "fix <thing>" · "redo" · "stop"
```

A report longer than the diff it describes has failed at its job.

### The Flow line

A diagram of the chunk, not its files. Draw one when the `Changed` lines
describe something moving through three or more steps or a branch. Skip it
for one place edited, a rename, config, tests only, tooling, or arrows that
would restate the file list; most chunks are one of those. Omit the line
rather than draw a two-box diagram.

Draw it from the implementer reports, as with `Changed`, without opening the
diff. Plain ASCII, since the report is read in a terminal: an indented tree,
`─>` for a step, `├─`/`└─` for a fork, the outcome on the branch. No boxes,
no mermaid, no alignment across lines beyond the indent. Five to ten steps;
labels are behaviour (`validate`, `enqueue`, `notify`), not paths. Mark what
the chunk added or changed with a suffix such as `(new)`. Several sources
feeding one target go under it with `<─`. No file in the working tree.

```
Flow:    POST /orders ─> validate ─> reserve stock (new)
         ├─ ok ────> persist ─> enqueue confirm mail
         └─ short ─> 409 + reason (new)
```

## The review map

Optional, and only on request. Once a chunk is reported, the human can say
`map` and get a private page that sorts the chunk's files into read
carefully, skim and trust, walks them in data-flow order, and lists what
only they can decide. `references/review-map.md` specifies the page; load it
when the human asks, not before.

Offer it, never publish it unasked: over roughly twenty files, or more than
one layer (backend, shared contracts, UI), add `· "map"` to the report's
`Next:` line. Once a map exists, republish it after every fix round and link
it on the `Map:` line. It never replaces the reviewer dispatch or the diff
snapshot.

## Resuming

| Human says | Do |
| --- | --- |
| `next` | Start the next chunk at step 1 |
| `fix <thing>` | Dispatch a fix implementer plus a scoped re-review, re-report the same chunk. If a map exists, republish it before the report |
| `map` | Build and publish the review map for this chunk, answer with the link, keep waiting |
| `redo` | Confirm first — there are no commits, so discarding is a real loss. On confirmation, `git apply -R` the chunk snapshot, then re-dispatch with the correction as added context |
| `stop` | Halt. Report which chunks are complete and which are untouched, then `bash scripts/run.sh stop` |

Anything else is a question about the chunk: answer it and keep waiting. A
question is not approval.

## What never happens without asking

- Starting the next chunk
- Publishing a review map
- Committing, staging, pushing, merging, or opening a PR, at any point, for
  any reason; while the run marker exists the plugin hook refuses these
  outright.
- Changing the plan. A chunk that proves the plan wrong stops the run and says
  so; the plan is amended with a human, then the loop resumes.

## After the last chunk

Approving the final chunk does not end the run: per-chunk review only ever
saw one chunk's diff, and nothing has yet judged the work as a whole. Run
all three, once, before handing off:

1. **Verify the whole tree** — the verify seat over every acceptance
   criterion in the plan. Its lines are the `Spec:` line below; a criterion
   it did not run is not met.
2. **Whole-tree review** — one reviewer against a snapshot of the entire
   working tree, not the last chunk's, with the plan's goal, acceptance
   criteria and the verifier's lines as input. Spec first, then code quality.
   On the most capable model per `delivery-pipeline`.
3. **Cross-model over the whole working tree**, regardless of risk class.

Findings and `FAIL` lines follow the chunk rule: one line that rounds are
running, then what survives is reported. Report once more, in the chunk
format, named `Final — whole tree`, with one extra line after `Proof:`:

```
Spec:    met · or one line per acceptance criterion the tree does not meet
```

Merge-ready is not launch-ready: a `Spec:` line with gaps is a plan
conversation with the human, not a fix round. If either pass finds something
that changes an approved chunk, say so plainly rather than quietly re-opening it; approval
was given on what was shown.

## Handing off

After the final report, run `bash scripts/run.sh stop` so git writes are
allowed again. The working tree is yours: read it, commit what you want, then
ship it however this project ships.
