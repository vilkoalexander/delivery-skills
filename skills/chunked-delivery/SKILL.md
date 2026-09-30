---
name: chunked-delivery
description: Use when asked to execute an approved plan with subagents in chunks, build a feature with the agent team, or pause for human review between units instead of running a plan end to end.
---

# Chunked Delivery

Plan together, then build in units small enough to read. After each unit the run
**stops** and hands back a diff. Nothing proceeds until a human says so, and
nothing is ever committed.

This borrows the machinery of `superpowers:subagent-driven-development` —
per-task implementer, task review, scoped re-review, worktree, ledger — and
overrides two of its rules.

> **Override 1.** SDD's continuous-execution rule ("do not pause to check in
> between tasks") does not apply. Stopping at each chunk boundary is the point.
> Every other SDD rule holds, including rulings-not-stalls *within* a chunk:
> mid-chunk ambiguity gets decided, not escalated.
>
> **Override 2.** SDD's implementer step "Commit your work" does not apply.
> Nothing is committed, staged, pushed or merged at any point.

Read `delivery-pipeline` first — model per role, the Global Constraints block,
the snapshot mechanism, and cross-model review points come from there. A project
that ships its own `delivery-pipeline` overrides the global one.

## Preflight

- The controller runs on the model `delivery-pipeline` names for the run's
  length. It holds the plan and every chunk summary for the whole run; a model
  swap mid-run loses that.
- Work happens in place, in the checkout the human is using, on a feature branch
  that is not `main` (create one if needed). Do NOT create or enter a git
  worktree unless the human explicitly asks for one in their message — the
  human reads and tests the diff in their own checkout, and a worktree hides it
  from them and needs its own install and `.env`.
- The plan file exists and carries the Global Constraints block.

## Plan shape

Plans for this skill group their tasks into **chunks**. One chunk is one thing a
human can read in a sitting and judge as a whole — a slice that stands on its
own, not an arbitrary task count. Typically one to three plan tasks.

Each chunk carries a risk class, assigned by the rules in `delivery-pipeline`
(its `scripts/risk.sh` suggests one from the paths, and from the hunks too
when `TYPESAFE_API_KEY` is set; its `unsure:` lines belong in the chunk list
for the human to settle). The class picks the
models, whether the chunk is reviewed at all, and the fix-round cap.

Order chunks leaf first. A change to what an existing caller already gets is
its own chunk, as late as the plan allows, behind a flag when the project has
flags. Trunk exposure is then one small chunk the human reads hardest, not a
slice of every chunk.

Before any dispatch, run `static-gate.sh coverage` per `delivery-pipeline`
and present the chunk list — name, risk, one line each — with any proposed
tooling chunk first, marked as optional. Then **wait for approval**. This is the only plan-level gate; after it, approval is
per chunk.

## The loop

For each approved chunk, in order:

1. **Snapshot first.** Write `chunk-N-before.diff` per `delivery-pipeline`. It is
   the only undo this run has.
2. **Dispatch implementers.** One per task. Parallel only when the chunk's tasks
   touch disjoint files; sequential otherwise. Models per `delivery-pipeline`.
   They leave their work uncommitted and unstaged, and their report ends with
   the Proof block from `delivery-pipeline`; one without it goes back for it.
3. **Snapshot the result** to `chunk-N.diff`, then **run the static gate**
   on the changed paths per `delivery-pipeline` — typecheck, lint, format,
   related tests, and the revert check when tests changed. A failure goes
   back to the implementer with the tool output as fix round zero; nothing
   else happens until it is clean. On a **low-risk chunk stop here** — no
   reviewer, no fix rounds; the human reads the proof and the diff at the
   gate and the whole-tree review at the end covers it. Otherwise dispatch
   the task reviewer against the snapshot — with the line that sends it to
   the project's rubric routing, if the project has one. Do not read the
   snapshot yourself.
4. **Run fix rounds to clean.** Findings go back to the implementer, then a
   scoped re-review that gets the findings and the fix diff, nothing else.
   Say in one line that fix rounds are running. The round counter trips at **three** on a medium-risk chunk and
   **five** on a high-risk one;
   the human reads the chunk next anyway, so a parked finding costs them a
   minute where two more rounds cost two implementer and two re-review seats.
   Park what remains and say so in the report.
5. **Cross-model review** if the chunk is high-risk — `delivery-pipeline` has the
   invocation and the adjudication rules. Its findings are claims you rule on,
   not a fix queue.
6. **Stop and report** in the format below.
7. **Wait.** Do not start the next chunk, do not prepare it, do not read ahead.

## The chunk report

This is what a human reads. It is not the ledger — the ledger is crash recovery
and never appears in a report. The counts come from `git diff --stat`, the
`Files` line from `git diff --name-only | bash scripts/risk.sh`, and the
`Changed` lines from the implementer and reviewer reports. The controller
does not read the diff to write this.

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

Fixed:   <"static: clean" or "static: <n> type/lint/test failures, fixed";
          then one line per finding the review caught and the implementer
          fixed, or "not reviewed — low risk">
Parked:  <one line per finding left standing, each with its reason>
Cross:   <one line verdict, or "not run — low risk">
Rulings: <only decisions that could have gone the other way. Omit if none.>

Read it:  git diff
Next:     "next" · "fix <thing>" · "redo" · "stop"
```

A report longer than the diff it describes has failed at its job.

### The Flow line

A diagram of the chunk, not of its files. Draw one when the `Changed` lines
describe something moving — a request, an event, a job, a row — through
three or more steps, or through a branch. Then a picture is faster to check
than prose. Skip it when the chunk is one place edited, a rename, config,
tests only, tooling, or when the arrows would just restate the file list;
most chunks are one of those. Omit the line entirely rather than draw a
two-box diagram.

The controller draws it from the implementer reports, the same source as
`Changed`, and does not open the diff for it. Plain ASCII, because the
report is read in a terminal and nothing renders there: an indented tree
with `─>` for a step, `├─`/`└─` for a fork, and the outcome on the branch.
No boxes, no mermaid, no alignment across lines beyond the indent. Five to
ten steps, labels are behaviour (`validate`, `enqueue`, `notify`) not paths.
Mark what the chunk added or changed with a suffix such as `(new)` so the
eye lands there. When several sources feed one target, list them under the
target with `<─` instead of forcing a tree. No file in the working tree.

```
Flow:    POST /orders ─> validate ─> reserve stock (new)
         ├─ ok ────> persist ─> enqueue confirm mail
         └─ short ─> 409 + reason (new)
```

## Resuming

| Human says | Do |
| --- | --- |
| `next` | Start the next chunk at step 1 |
| `fix <thing>` | Dispatch a fix implementer plus a scoped re-review, re-report the same chunk |
| `redo` | Confirm first — there are no commits, so discarding is a real loss. On confirmation, `git apply -R` the chunk snapshot, then re-dispatch with the correction as added context |
| `stop` | Halt. Report which chunks are complete and which are untouched |

Anything else is a question about the chunk — answer it and keep waiting. A
question is not approval.

## What never happens without asking

- Starting the next chunk
- Committing, staging, pushing, merging, or opening a PR — at any point, for any
  reason
- Changing the plan. A chunk that proves the plan wrong stops the run and says
  so; the plan is amended with a human, then the loop resumes.

## After the last chunk

Approving the final chunk does not end the run. Per-chunk review only ever saw
one chunk's diff, and low-risk chunks saw no reviewer at all; nothing has yet
judged the work as a whole — where chunk 3 quietly broke what chunk 1
established, or where four clean chunks add up to an incoherent module.

Run both, once, before handing off:

1. **Whole-tree review** — one reviewer against a snapshot of the entire working
   tree, not the last chunk's, with the plan's goal and acceptance criteria as
   input. It answers spec first, then code quality. On the most capable model
   per `delivery-pipeline`.
2. **Cross-model over the whole working tree**, regardless of risk class.

Findings here follow the same rule as a chunk's: one line that rounds are
running, then what survives gets reported. Report once more, in the chunk
format, named `Final — whole tree`, with one extra line after `Proof:`:

```
Spec:    met · or one line per acceptance criterion the tree does not meet
```

Merge-ready is not launch-ready. A `Spec:` line with gaps is a plan
conversation with the human, not a fix round.

If either pass finds something that changes a chunk already approved, say so
plainly rather than quietly re-opening it. Approval was given on what was shown.

## Handing off

After the final report, the working tree is yours: read it, commit what you want,
then ship it however this project ships.
