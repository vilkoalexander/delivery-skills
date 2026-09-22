---
name: chunked-delivery
description: Runs an approved plan one human-reviewable chunk at a time — fans out subagents for a chunk, reviews it, then stops and hands the diff back for human review before touching the next chunk. Nothing is ever committed. Use when asked to build a feature with subagents, execute a plan in chunks, or run the agent team; and whenever work should pause for review between units instead of running a plan end to end.
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

- The controller runs on the most capable model available. It holds the plan and every chunk summary for the whole
  run; a model swap mid-run loses that.
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

Each chunk carries a risk class. It picks the implementer and reviewer models,
per `delivery-pipeline`.

Before any dispatch, present the chunk list — name, risk, one line each — and
**wait for approval**. This is the only plan-level gate; after it, approval is
per chunk.

## The loop

For each approved chunk, in order:

1. **Snapshot first.** Write `chunk-N-before.diff` per `delivery-pipeline`. It is
   the only undo this run has.
2. **Dispatch implementers.** One per task. Parallel only when the chunk's tasks
   touch disjoint files; sequential otherwise. Models per `delivery-pipeline`.
   They leave their work uncommitted and unstaged.
3. **Snapshot the result** to `chunk-N.diff`, and dispatch the task reviewer
   against that file — with the line that sends it to the project's rubric
   routing, if the project has one.
4. **Run fix rounds to clean.** Findings go back to the implementer, then a
   scoped re-review. This is agent work — do not surface individual rounds. If
   the round counter trips at five, park what remains and say so in the report.
5. **Cross-model review** if the chunk is high-risk — `delivery-pipeline` has the
   invocation and the adjudication rules. Its findings are claims you rule on,
   not a fix queue.
6. **Stop and report** in the format below.
7. **Wait.** Do not start the next chunk, do not prepare it, do not read ahead.

## The chunk report

This is what a human reads. It is not the ledger — the ledger is crash recovery
and never appears in a report.

```
Chunk N/M — <name>   [risk]
<files> files changed, <added>/<removed> lines

Changed: <three to five lines. What it now does and why — not a file list.>

Fixed:   <one line per finding the review caught and the implementer fixed>
Parked:  <one line per finding left standing, each with its reason>
Cross:   <one line verdict, or "not run — low risk">
Rulings: <only decisions that could have gone the other way. Omit if none.>

Read it:  git diff
Next:     "next" · "fix <thing>" · "redo" · "stop"
```

Keep it under twenty lines. A report longer than the diff it describes has failed
at its job.

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
one chunk's diff; nothing has yet judged the work as a whole — where chunk 3
quietly broke what chunk 1 established, or where four clean chunks add up to an
incoherent module.

Run both, once, before handing off:

1. **Whole-tree review** — one reviewer against a snapshot of the entire working
   tree, not the last chunk's. On the most capable model per `delivery-pipeline`.
2. **Cross-model over the whole working tree**, regardless of risk class.

Findings here follow the same rule as a chunk's: fix rounds run silently, what
survives gets reported. Then report once more, in the chunk format, named
`Final — whole tree`.

If either pass finds something that changes a chunk already approved, say so
plainly rather than quietly re-opening it. Approval was given on what was shown.

## Handing off

After the final report, the working tree is yours: read it, commit what you want,
then ship it however this project ships.
