---
name: delivery-pipeline
description: Controller-side settings for running subagent-driven development — which model fills each role, where project constraints come from, how review works without commits, and where cross-model review attaches. Use when executing an implementation plan with subagents, dispatching an implementer or a task reviewer, or setting up a multi-agent run. Read it before dispatching the first task.
---

# Delivery Pipeline

`superpowers:subagent-driven-development` owns the loop: fresh implementer per
task, task review, scoped re-review, ledger, worktree, final whole-branch review.
Follow it. This supplies the four things it leaves to the project — model per
role, where the binding constraints come from, how review works when nothing is
committed, and where the second opinion attaches.

Read this once at controller start, before the pre-flight plan scan.

A project may ship its own `delivery-pipeline` skill. If it does, that one wins
outright — it is this file tuned to that codebase, not a supplement to it.

## Model per role

SDD requires an explicit model on every dispatch; an omitted one silently
inherits the session's most expensive. Pick the cheapest that can hold the role.

| Role | Model | Dispatch as | Why |
| --- | --- | --- | --- |
| Controller | Fable 5.1 | the session itself | Holds plan and chunk summaries across the whole run |
| Implementer — mechanical | Haiku 4.5 | `model: haiku` | One or two files against a specified plan |
| Implementer — one-way doors | Opus 5.5 | `model: opus` | Schema, auth, money, migrations, public contracts |
| Task reviewer — default | Sonnet 5 | `model: sonnet` | Reads a diff against rubrics; needs judgement, not the top tier |
| Task reviewer — high risk | Opus 5.5 | `model: opus` | Anything on the one-way-door list above |
| Scoped re-review | Haiku 4.5 | `model: haiku` | Small fix diff, findings already written |
| Final whole-branch review | Opus 5.5 | `model: opus` | SDD mandates the most capable available |

"Dispatch as" is the `model` value the Agent tool takes. The short names
resolve to the current generation of that family, so the table stays right
when a point release ships. Never pass a dated model ID.

Tag each task in the plan with its risk class, and let the tag pick the model.
A judgement made fresh at dispatch time drifts toward whatever is cheapest.

### The lineup this table assumes (22 September 2026)

| Family | Current | API ID | Tier |
| --- | --- | --- | --- |
| Fable | Fable 5.1 | `claude-fable-5-1` | most capable; 1M context; thinking always on |
| Opus | Opus 5.5 (Opus 5 and 4.8 still served) | `claude-opus-5-5` | one-way doors, final review, high-risk review |
| Sonnet | Sonnet 5 (Sonnet 5.5 announced, not yet shipped) | `claude-sonnet-5` | default task review |
| Haiku | Haiku 4.5 (Haiku 5.5 announced, not yet shipped) | `claude-haiku-4-5` | mechanical implementers, scoped re-review |

Substitutions, in order:

- **No Fable on the plan** — controller runs on Opus 5.5. Nothing else changes.
  Opus 5.5 beats Fable 5.1 on many coding benchmarks and costs about 40% less
  to run; Fable stays the default controller only because Anthropic still
  positions it for the longest-horizon agentic runs.
- **Opus 5.5 defaults to `medium` effort.** Every other current model defaults
  to `high`. Pass effort explicitly on Opus 5.5 reviewer and one-way-door
  dispatches, or its reviews run shallower than the Sonnet ones.
- **Cost pressure** — lower the *effort* of a role before lowering its model.
  Implementers and re-reviews run fine at low or medium effort; reviewers stay
  at high. On the Claude 5 family, a cheaper model at high effort is usually
  worse than the same model at lower effort.
- **A newer family member ships** — the short dispatch names already point at
  it. Re-check only the "Why" column: does the new Haiku hold a mechanical
  implementer, does the new Sonnet still need Opus above it for high risk.

The roles and how they hand work to each other: `diagrams/roles-and-models.svg`
in this repository.

## Project constraints

Every task reviewer needs the project's non-negotiables. SDD passes them through
the `[GLOBAL_CONSTRAINTS]` placeholder in its task-reviewer prompt, filled from
the plan's `## Global Constraints` section. That placeholder is the only
sanctioned route for project rules to reach a dispatched reviewer — a plan
without that section produces reviews graded on generic quality alone.

Build the block once, at controller start, from what the project already states:

1. The project's `CLAUDE.md` / `AGENTS.md` — invariants described as blocking,
   non-negotiable, or one-way doors.
2. Any review SOP the project keeps (`docs/PR-REVIEW.md`, `CONTRIBUTING.md`).
3. The rules below, which hold everywhere.

```
## Global Constraints
- Never run git commit, git add, git push, or open a PR. Work stays uncommitted.
- Names describe behaviour — never a sprint, quarter, wave or ticket number.
- Follow the patterns already in the files being changed, not a better idea.
- <project invariants, one line each, each stated as a rule a reviewer can check>
```

Keep it short enough that it stays read. Constraints specific to one task belong
in that task's text; this block is what binds every task.

## Reviewer dispatch

Add one line to SDD's task-reviewer prompt body:

> If this project has a skill that maps changed paths to review rubrics, invoke
> it first. Otherwise review on general code quality and say so in one line.

Many projects keep domain review skills — one per layer, each written for a
single file. Where such a skill exists (often named `review-routing`), it owns
the mapping and the single-file-to-diff adaptation. Never inline that mapping
into a dispatch prompt: it drifts from the skill within two edits.

**One reviewer per task** is the default, with those rubrics as its checklist.
Fan out to a reviewer per rubric only when a task's diff spans two or more
domains *and* is large enough that one reviewer would read past its useful
attention. Fan-out costs a full review seat each and leaves you merging and
de-duplicating findings. When you do it, record why.

## Nothing is ever committed

No subagent and no controller runs `git commit`, `git add`, `git push`, `git
merge`, or opens a PR — not per task, not at the end of a clean run, not to a
worktree branch. Work stays in the working tree. The human reviews it there and
decides what becomes a commit. This overrides SDD's implementer-prompt step
"Commit your work", and it is not negotiable by a ruling mid-run.

Two pieces of SDD assume commits, so they are replaced:

**Review ranges.** SDD hands reviewers `BASE_SHA..HEAD_SHA`. With no commits,
snapshot the working tree and hand the reviewer the file:

```bash
git add -N .                                   # makes new files visible to diff
git diff > "$WORKSPACE/chunk-$N.diff"
```

`git add -N` records paths only, never content — `git reset` undoes it. It is the
one index touch this process makes, and without it every newly created file is
invisible to the reviewer. The rest of the review flow is unchanged: the reviewer
reads the snapshot file, does not re-run git, and stays read-only.

**Recovery.** SDD's ledger recovers from commit SHAs, which no longer exist.
Snapshot before a chunk as well as after — `chunk-$N-before.diff` and
`chunk-$N.diff`. Those two files are the run's only undo, and `git apply -R` on
the after-snapshot is what "redo" means now. Say so plainly when asked to discard
work: there is no cheap restore point, so discarding is a real loss and gets
confirmed first.

## Cross-model review

The second opinion is a different model family reading the same diff. It attaches
at two points, never inside the SDD fix loop:

1. **Per task, high-risk only** — after the task review passes, before marking
   the task complete.
2. **Whole working tree, always** — after the final whole-branch review, before
   handing off.

With the Codex plugin installed:

```bash
CODEX_ROOT=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ | sort -V | tail -1)
node "${CODEX_ROOT}scripts/codex-companion.mjs" adversarial-review --background --scope working-tree <focus text>
```

Gotchas, both verified:

- `adversarial-review` takes focus text positionally, so an **unrecognised flag
  becomes focus text**. There is no `--help`; passing one starts a real review.
- `review` is the built-in reviewer and takes no focus text. Use
  `adversarial-review` whenever you need to aim it.
- `--scope` accepts `auto`, `working-tree` or `branch`. Staged-only and
  unstaged-only are unsupported by both subcommands.

The stop-time review gate (`/codex:setup --enable-review-gate`) sits under both,
not in place of either — it fires on session stop, which has no relationship to
task boundaries.

## Adjudicating two reviews

Cross-model output is a claim, exactly like the implementer's report. It comes to
you, never straight to a fix dispatch.

- **Both flag it** — fix it, normal fix round.
- **Only the cross-model pass flags it** — check it against the Global
  Constraints and the project's rubrics first. It cannot see them, so it produces
  genuine cross-family findings *and* suggestions for things the project has
  already decided against.
- **Only the rubric reviewer flags it** — fix it. The other model not seeing
  something is not evidence of absence.
- **They contradict** — you rule. Record it as `Ruling: <decision> — <why> —
  <cost if wrong>`, and keep going.

A run that stops to ask which reviewer was right has cost more than the wrong
ruling would have.
