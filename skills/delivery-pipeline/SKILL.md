---
name: delivery-pipeline
description: Use when executing an implementation plan with subagents, dispatching an implementer or a task reviewer, or setting up a multi-agent run. Read it before dispatching the first task.
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
| Controller | Opus 5.5 | the session itself | Holds plan and chunk summaries; Fable 5.1 only on long runs (below) |
| Implementer — mechanical | Haiku 4.5 | `model: haiku` | One or two files against a specified plan |
| Implementer — one-way doors | Opus 5.5 | `model: opus` | Schema, auth, money, migrations, public contracts |
| Task reviewer — default | Sonnet 5.5 | `model: sonnet` | Reads a diff against rubrics; needs judgement, not the top tier |
| Task reviewer — high risk | Opus 5.5 | `model: opus` | Anything on the one-way-door list above |
| Scoped re-review | Haiku 4.5 | `model: haiku` | Small fix diff, findings already written |
| Final whole-branch review | Opus 5.5 | `model: opus` | SDD mandates the most capable available |

"Dispatch as" is the `model` value the Agent tool takes. The short names
resolve to the current generation of that family, so the table stays right
when a point release ships. Never pass a dated model ID.

Tag each task in the plan with its risk class (next section), and let the tag
pick the model. A judgement made fresh at dispatch time drifts toward whatever
is cheapest.

Substitutions, in order:

- **Long runs** — a plan over six chunks, or one whose context you expect to
  outgrow what Opus holds, runs the controller on Fable 5.1 (1M context,
  thinking always on). On anything shorter Fable pays for reasoning the plan
  does not need: Opus 5.5 matches it on coding and costs about 60% less.
- **Opus 5.5 defaults to `medium` effort**; Sonnet 5.5 and Fable 5.1 default to
  `high`, and Haiku 4.5 takes no effort setting. The Agent tool takes no effort
  per call — it comes from the agent definition (`.claude/agents/<role>.md`
  frontmatter). Give the Opus 5.5 reviewer and one-way-door roles a definition
  with effort `high`, or their reviews run shallower than the Sonnet ones.
- **Cost pressure** — lower the *effort* of a role before lowering its model.
  Implementers and re-reviews run fine at low or medium effort; reviewers stay
  at high. On the Claude 5 family, a cheaper model at high effort is usually
  worse than the same model at lower effort.
- **A newer family member ships** — the short dispatch names already point at
  it. Re-check the "Why" column against `MODELS.md` next to this file, which
  holds the lineup this table was written against.

The roles and how they hand work to each other: `diagrams/roles-and-models.svg`
in this repository.

## Risk class

Every plan task carries one of three classes. The class picks the models
above, whether the chunk gets a review at all, and the fix-round cap. Classify
on what the task **touches**, not on how hard it looks: any one predicate in a
row puts the task in that row.

| Class | Any of these | Wrong means |
| --- | --- | --- |
| **high** | Prisma schema or migration; the shared contract package (`libs/shared`, `packages/contracts`, or whatever the project calls it); auth, guards, strategies, sessions; payments, ledger, billing; deletes data or drops a column; env, secrets, CI, deploy; public API surface | Data lost or exposed, or consumers broken with no error |
| **medium** | NestJS service, controller or module logic; a shared primitive, hook or util (`components/ui`, `hooks`, `lib`, `utils`) with callers outside the chunk; a changed signature anything else calls; state store, data fetching, error handling; a new runtime dependency; more than five files or three hundred lines | A behaviour bug others depend on, fixable in a normal fix round |
| **low** | Feature-local UI (`features/<x>/…`, a leaf component); styling, copy, i18n; tests, docs, dev-tooling config; additive code with no callers yet; a rename inside one file; five files or fewer | Visible, local, and the human sees it at the gate |

- **A chunk takes the highest class of its tasks.**
- **Two rows match — the higher wins.** No averaging.
- **Unsure is medium.** Low is never the default.
- **Escalators.** Cannot name the callers of what changes: at least medium.
  Touches the path production data takes: high. Changes what an existing
  caller already gets, with no flag in front of it: one class up. Additive
  code behind a flag that ships off stays where its paths put it. A small
  file count lowers none of these.
- The human sees each chunk's class in the chunk list at plan approval.
  Raising it needs no reason; lowering it gets a one-line reason recorded in
  the plan.

`bash scripts/risk.sh <paths…>` — or `git diff --name-only | bash
scripts/risk.sh` — prints the class the path shapes suggest, one line per
path with the rule it hit, then the class for the set. It sees paths, not
content: it cannot know a signature changed or a caller exists. A floor to tag
from, never a verdict. `RISK_HIGH` and `RISK_MEDIUM` take an extra regex each
for the project's own always-high and always-medium paths.

**Who checks the escalators.** The last line of `risk.sh` says.

- `escalators: jev` — `TYPESAFE_API_KEY` was set, so `risk.sh` piped the
  hunks through `scripts/risk-content.sh`. That script sends each changed
  file's diff to TypeSafe's Jev model with the escalators above as literal
  yes/no questions (signature changed, caller sees a change, production data
  path, deletes data, auth or money) and raises the class in code from the
  probabilities: a data, auth or money hit is high; a signature or caller hit
  is one class up; anything the model puts between `RISK_P_UNSURE` (0.5) and
  `RISK_P_ACT` (0.7) lands on an `unsure:` line and holds the file at medium,
  but only when a yes could still raise that file.
  Each file starts from its own path class; a brand-new file skips the
  signature and caller checks, since nothing called it before. It never
  lowers a path floor. The `unsure:` lines go into the chunk list
  at plan approval for the human to settle; the tagged class is otherwise
  final. About a hundred milliseconds and a fraction of a cent per file, and
  the same answer every run — which is the point: a class that drifts between
  runs moves review seats and fix rounds with it.
- `escalators: controller` — no key, `RISK_CONTENT=off`, or the content pass
  failed. Read the diff for the escalator bullets yourself and tag from that,
  as before. Nothing else changes.

`RISK_DIFF_RANGE=base..head` points the content pass at a range instead of the
working tree. `bash scripts/risk-content.test.sh` checks both scripts against
a fake endpoint and needs no key.

What each class buys:

| Class | Implementer | Chunk review | Fix rounds | Cross-model |
| --- | --- | --- | --- | --- |
| low | Haiku 4.5 | none — the human reads the diff at the gate, and the whole-tree review at the end covers it | 0 | no |
| medium | Haiku 4.5; Sonnet 5.5 when the task touches more than two files | Sonnet 5.5 | up to 3 | no |
| high | Opus 5.5 | Opus 5.5 | up to 5 | yes |

A low-risk chunk skipping review is the deliberate trade: the review seat and
its fix rounds cost more than the human spends reading a small local diff, and
nothing in that class is expensive to fix after the fact.

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
- A test that still passes with the change reverted is not a test. Assert the
  behaviour the change adds, or leave the test out.
- Comments: none by default; rename, extract or type it first. One line, and
  only for why this and not the obvious alternative, an outside constraint, a
  warning about what breaks if edited, or a workaround with its removal
  condition. On a constant or an interface field: only units, where a number
  comes from, a domain term, or what null means. Never restate the code,
  describe the change, or name a ticket, PR, date or link. Leave an existing
  comment alone unless the change makes it false.
- <project invariants, one line each, each stated as a rule a reviewer can check>
```

The comment line is `comment-cleanup`'s `RULES.md` condensed; the two change
together. Keep it short enough that it stays read. Constraints specific to one task belong
in that task's text; this block is what binds every task.

## Implementer proof

On a low-risk chunk the implementer's report is the only check before the
human; on the others it is what the human reads before the diff. SDD's
implementer prompt already asks for test results, which is one kind of proof.
Append this to its `## Report Format`, and the report file ends with it filled
in:

```
## Proof
- ran: <exact command> — <the pass/fail line from its output>
- shows: <path to a screenshot or recording of the change on screen>
  (only when the diff touches a rendered file)
- exercised: <the output itself, pasted — a log line, a response body, a
  CLI result — of the changed path running>   (medium and high risk)
- not verified: <one line per thing you did not run or see, or "nothing">
```

A test written but not run is not proof; it goes under `not verified`. A
sentence about what was checked is not proof either: `exercised` holds
output, and "manually verified N cases" goes back for the output. A report
that arrives without the block goes back for the block, not for a second
implementation. The controller condenses the block into the chunk
report's `Proof:` line and routes on `not verified`: on a high-risk chunk each
item there becomes a reviewer focus, on a low-risk chunk it is what the human
checks first.

## Static gate

Whatever the toolchain can decide, it decides before a reviewer reads a line.
`bash scripts/static-gate.sh` next to this file has two modes.

**`coverage`, once per run, at controller start.** It prints what the
project enforces — strict flags, type-aware lint, the rules each rubric cares
about at error / warn / absent, prettier, module boundaries, pre-commit — and
ends with an `ABSENT:` list. Two lines of the Global Constraints block come
from it:

```
- Enforced by tooling, never a finding: <rules at error>
- Not enforced, reviewers report: <the ABSENT list>
```

A rubric's own "Tooling coverage" step then reads those lines instead of
running `eslint --print-config` per review; that is one invocation per run
in place of one per reviewer. When the report ends with a `SETUP:` line,
name a **tooling chunk** at plan approval, first in the list and marked
optional: the sections it names in `STATIC-SETUP.md` next to this file are
the strict recipe for each missing piece — what to install, the config, and
the script that makes warnings fail. Load that file only when the human
takes the chunk; its implementer gets the named sections as the task text.
One chunk of config removes that class of finding from every review after
it. Propose it; never add it unasked.

**`check <paths>`, after every after-snapshot, before any reviewer, on every
risk class.** It runs the project's typecheck, lint, format, `prisma
validate` and related tests over the changed paths and exits non-zero with
the tool output. A failure goes back to the implementer with that output as
**fix round zero**: no reviewer has been dispatched, so it does not count
against the review cap. Two static rounds, then park it and say so. The
reviewer only ever sees a diff that already passes what a machine can check.

When the diff touches tests, `test-review`'s `scripts/revert-check.sh` runs
here too: it reverses the non-test hunks, runs the changed tests, restores
the tree, and names any test that still passed. Each one is a finding
before a reviewer reads it, and it is the check behind the Global
Constraints line about tests that survive reversion.

## Implementer dispatch

Add one line to SDD's implementer prompt body:

> If this project has a skill for authoring the kind of file this task
> creates, invoke it before writing the first line. Otherwise follow the
> patterns in the sibling files and say so in one line.

Lint catches the wrong shape after the file exists; an authoring skill
(such as `react-screen-authoring` for a new React screen, sheet, form or
picker) puts the shape in context before generation, so the static gate and
the reviewer see fewer round trips. As with review, never inline the skill's
rules into the dispatch prompt: they drift within two edits.

## Reviewer dispatch

Add one line to SDD's task-reviewer prompt body:

> If this project has a skill that maps changed paths to review rubrics, invoke
> it first. Otherwise review on general code quality and say so in one line.

Many projects keep domain review skills — one per layer, each written for a
single file. Where such a skill exists (often named `review-routing`), it owns
the mapping and the single-file-to-diff adaptation. Never inline that mapping
into a dispatch prompt: it drifts from the skill within two edits.

**One reviewer per chunk** is the default, on medium- and high-risk chunks
only (see Risk class), with those rubrics as its checklist; on a backend
chunk the routing adds `observability-review` as a second pass over the
backend rows, in the same seat. Fan out to a
reviewer per rubric only when a chunk's diff spans two or more
domains *and* is large enough that one reviewer would read past its useful
attention. Each fanned-out reviewer gets only its rubric's slice of the diff
(`git diff -- <paths> > "$WORKSPACE/chunk-$N-<rubric>.diff"`). Fan-out costs a
full review seat each and leaves you merging and de-duplicating findings. When
you do it, record why.

**The whole-tree reviewer gets the plan's goal and acceptance criteria**
alongside the snapshot and the Global Constraints, and answers spec before
quality: does the tree do what the plan said, then is the code sound. Chunk
reviewers do not get the criteria; one chunk cannot meet a spec on its own.

**Scoped re-reviews get none of this.** No rubric line, no `review-routing`:
the re-reviewer receives the findings list and the fix diff, per SDD's
re-review prompt, and nothing else. Re-loading the rubrics for a twenty-line
fix costs more than the original review did.

## What the controller reads

The controller never reads a diff snapshot. Its view of the work is the
implementer reports, the reviewer reports and `git diff --stat`. Reading a
chunk diff puts the whole change into the most expensive context on the plan
and keeps it there for the rest of the run; the reviewer has already read it
once, on a cheaper model, and reported what matters.

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

1. **Per chunk, high-risk only** — after the chunk review passes, before the
   chunk report.
2. **Whole working tree, always** — after the final whole-branch review, before
   handing off.

With the Codex plugin installed:

```bash
CODEX_ROOT=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ | sort -V | tail -1)
node "${CODEX_ROOT}scripts/codex-companion.mjs" adversarial-review --background --scope working-tree <focus text>
```

Gotchas, verified against codex 1.0.4:

- `adversarial-review` takes focus text positionally, so an **unrecognised flag
  becomes focus text** and starts a real review. `--help` works only bare
  (`codex-companion.mjs --help`), never after a subcommand.
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
