---
name: delivery-pipeline
description: Use when executing an implementation plan with subagents, dispatching an implementer or a task reviewer, or setting up a multi-agent run. Read it before dispatching the first task.
---

# Delivery Pipeline

`superpowers:subagent-driven-development` owns the loop: fresh implementer per
task, task review, scoped re-review, ledger, worktree, final whole-branch review.
Follow it. This file adds what it leaves to the project: model per role, binding
constraints, review without commits, and where the second opinion attaches.

Read it once at controller start, before the pre-flight plan scan.

A project's own `delivery-pipeline` skill wins outright; it is this file tuned
to that codebase.

## Model per role

SDD requires an explicit model on every dispatch; an omitted one silently
inherits the session's most expensive. Pick the cheapest that can hold the role.

| Role | Model | Dispatch as | Why |
| --- | --- | --- | --- |
| Controller | Opus 5.5 | the session itself | Holds plan and chunk summaries; Fable 5.1 only on long runs (below) |
| Implementer — mechanical | Haiku 4.5 | `model: haiku` | One or two files against a specified plan |
| Implementer — one-way doors | Opus 5.5 | `subagent_type: delivery-skills:oneway-implementer`, `model: opus` | Schema, auth, money, migrations, public contracts |
| Task reviewer — default | Sonnet 5.5 | `subagent_type: delivery-skills:reviewer`, `model: sonnet` | Reads a diff against rubrics; needs judgement, not the top tier |
| Task reviewer — high risk | Opus 5.5 | `subagent_type: delivery-skills:reviewer`, `model: opus` | Anything on the one-way-door list above |
| Scoped re-review | Haiku 4.5 | `model: haiku` | Small fix diff, findings already written |
| Verifier | Sonnet 5.5 | `subagent_type: delivery-skills:verifier`, `model: sonnet` | Runs the criteria and pastes what it saw; medium and high chunks, then the whole tree |
| Final whole-branch review | Opus 5.5 | `subagent_type: delivery-skills:reviewer`, `model: opus` | SDD mandates the most capable available |

"Dispatch as" is what the Agent tool takes. Short model names resolve to the
current generation; never pass a dated model ID.

A `subagent_type` replaces `general-purpose` in SDD's prompt template for that
seat; the prompt body is unchanged. Those three definitions ship in this plugin's
`agents/` and carry what a call cannot: effort `high`, and for the reviewer no
Edit or Write tool. A row without one stays `general-purpose`; dispatched
that way on Opus 5.5 a review runs shallower than the Sonnet seat.

Tag each plan task with its risk class (next section); the tag picks the model.

Substitutions, in order:

- **Long runs** — over six chunks, or context expected to outgrow what Opus
  holds: controller on Fable 5.1 (1M context, thinking always on). Shorter runs
  stay on Opus 5.5: same coding, about 60% cheaper.
- **Opus 5.5 defaults to `medium` effort**; Sonnet 5.5 and Fable 5.1 default to
  `high`; Haiku 4.5 takes no effort setting. Effort comes from the agent
  definition, not the Agent call, which is why the reviewer and one-way-door
  seats have one.
- **Cost pressure** — lower a role's *effort* before its model: on the Claude 5
  family a cheaper model at high effort is usually worse than the same model at
  lower effort. Implementers and re-reviews run fine at low or medium;
  reviewers stay at high.
- **A newer family member ships** — the short names already point at it.
  Re-check the "Why" column against `MODELS.md` next to this file.

Roles and hand-offs: `diagrams/roles-and-models.svg` in this repository.

## Risk class

Every plan task carries one of three classes; the class picks the models,
whether the chunk gets a review, and the fix-round cap. Classify on what the
task **touches**, not how hard it looks: one matching predicate puts the task
in that row.

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
scripts/risk.sh` — prints each path's class with the rule it hit, then the
class for the set. It sees paths, not content: a floor, never a verdict.
`RISK_HIGH` and `RISK_MEDIUM` take an extra regex each for the project's own
always-high and always-medium paths.

**Who checks the escalators.** The last line of `risk.sh` says.

- `escalators: jev` — `TYPESAFE_API_KEY` was set and `risk.sh` piped the hunks
  through `scripts/risk-content.sh`, which asks TypeSafe's Jev model the
  escalators as yes/no questions per changed file (signature changed, caller
  sees a change, production data path, deletes data, auth or money) and raises
  the class from the probabilities: data, auth or money is high; signature or
  caller is one class up; between `RISK_P_UNSURE` (0.5) and `RISK_P_ACT` (0.7)
  is an `unsure:` line holding the file at medium, only when a yes could still
  raise it. Each file starts from its own path class; a brand-new file skips
  the signature and caller checks; a path floor is never lowered. `unsure:`
  lines go into the chunk list at plan approval for the human to settle; the
  tagged class is otherwise final. About a hundred milliseconds and a fraction
  of a cent per file, same answer every run.
- `escalators: controller` — no key, `RISK_CONTENT=off`, or the content pass
  failed. Read the diff for the escalator bullets yourself and tag from that.

`RISK_DIFF_RANGE=base..head` points the content pass at a range instead of the
working tree. `bash scripts/risk-content.test.sh` checks both scripts against a
fake endpoint and needs no key.

What each class buys:

| Class | Implementer | Chunk review | Verify | Fix rounds | Cross-model |
| --- | --- | --- | --- | --- | --- |
| low | Haiku 4.5 | none — the human reads the diff at the gate, and the whole-tree review at the end covers it | none | 0 | no |
| medium | Haiku 4.5; Sonnet 5.5 when the task touches more than two files | Sonnet 5.5 | Sonnet 5.5 | up to 3 | no |
| high | Opus 5.5 | Opus 5.5 | Sonnet 5.5 | up to 5 | yes |

## Project constraints

Every task reviewer needs the project's non-negotiables. SDD passes them through
the `[GLOBAL_CONSTRAINTS]` placeholder in its task-reviewer prompt, filled from
the plan's `## Global Constraints` section, the only sanctioned route for
project rules to reach a dispatched reviewer.

Build the block once, at controller start, from:

1. The project's `CLAUDE.md` / `AGENTS.md`: invariants described as blocking,
   non-negotiable, or one-way doors.
2. Any review SOP the project keeps (`docs/PR-REVIEW.md`, `CONTRIBUTING.md`).
3. The rules below, which hold everywhere.

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
- Comments: none by default; rename, extract or type it first. One line, and
  only for why this and not the obvious alternative, an outside constraint, a
  warning about what breaks if edited, or a workaround with its removal
  condition. On a constant or an interface field: only units, where a number
  comes from, a domain term, or what null means. Never restate the code,
  describe the change, or name a ticket, PR, date or link. Leave an existing
  comment alone unless the change makes it false.
- A chunk is sized by its closer-look files: ~300 lines, ≤8 files, ≤20 files
  total; a reviewer that sees more reports the overrun as a finding.
- <project invariants, one line each, each stated as a rule a reviewer can check>
```

The comment line is `comment-cleanup`'s `RULES.md` condensed; the two change
together. Keep the block short enough that it stays read. Task-specific
constraints go in that task's text.

## Implementer proof

On a low-risk chunk the implementer's report is the only check before the
human; on the others the human reads it before the diff. Append this to SDD's
implementer `## Report Format`; the report ends with it filled in:

```
## Proof
- ran: <exact command> — <the pass/fail line from its output>
- shows: <path to a screenshot or recording of the change on screen>
  (only when the diff touches a rendered file)
- exercised: <the output itself, pasted — a log line, a response body, a
  CLI result — of the changed path running>   (medium and high risk)
- not verified: <one line per thing you did not run or see, or "nothing">

## Reuse
- reused: <export> from <path>        (one line each, or "nothing")
- searched: <what you looked for> — none found   (one per new helper)
- new shared: <path> — <why nothing above fit>   (or "nothing")
- new dependency: <name> — <plan task that named it>   (or "nothing")
```

The Reuse block is the Global Constraints' search, written down. A `new shared`
line with no `searched` line above it goes back. The controller carries
`new shared` and `new dependency` lines into the chunk report's `Reuse:` line.

A test written but not run is not proof; it goes under `not verified`. A
sentence about what was checked is not proof either: `exercised` holds output,
and "manually verified N cases" goes back for the output. A report missing
either block goes back for the block, not for a second implementation. The
controller condenses Proof into the chunk report's `Proof:` line and routes on
`not verified`: on a high-risk chunk each item becomes a reviewer focus; on a
low-risk chunk the human checks it first.

## Verify seat

Neither Proof nor review runs the change. After a medium- or high-risk chunk's
fix rounds end, dispatch `delivery-skills:verifier` with:

- the chunk's `exercise:` line from the approved chunk list — the request
  or the tap that proves the chunk;
- every plan acceptance criterion the chunk completes, quoted;
- the implementer's Proof block, so each `ran` and `exercised` claim is
  re-run by someone else.

It returns one line per item: `pass` or `FAIL` with the command and pasted
output, or `needs human` with the one tap only a person can do. A `FAIL` is a
finding: a fix round for the implementer, counted against the chunk's cap; only
the failed lines are re-verified. A claim the verifier could not reproduce is a
`FAIL` on the Proof block itself, and the report says so. `needs human` lines go
to the report's `Verified:` line, the first thing the human does with the diff.

The whole tree gets the same seat once more, over every plan acceptance
criterion, before the whole-tree reviewer is dispatched; its lines go into that
dispatch and feed the final report's `Spec:` line. A criterion nobody ran is
not met.

## Static gate

Whatever the toolchain can decide, it decides before a reviewer reads a line.
`bash scripts/static-gate.sh` next to this file has two modes.

**`coverage`, once per run, at controller start.** Prints what the project
enforces (strict flags, type-aware lint, each rubric's rules at error / warn /
absent, prettier, module boundaries, pre-commit) and ends with an `ABSENT:`
list. Two Global Constraints lines come from it:

```
- Enforced by tooling, never a finding: <rules at error>
- Not enforced, reviewers report: <the ABSENT list>
```

A rubric's "Tooling coverage" step reads those lines instead of running
`eslint --print-config` per review. A closing `SETUP:` line means: name a
**tooling chunk** at plan approval, first in the list and marked optional; the
sections it names in `STATIC-SETUP.md` next to this file are the recipe for
each missing piece. Load that file only when the human takes the chunk; its
implementer gets the named sections as the task text. Propose it; never add it
unasked.

**`check <paths>`, after every after-snapshot, before any reviewer, on every
risk class.** Runs the project's typecheck, lint, format, `prisma validate` and
related tests over the changed paths; exits non-zero with the tool output. A
failure goes back to the implementer with that output as **fix round zero**: no
reviewer was dispatched, so it does not count against the review cap. Two
static rounds, then park it and say so. The reviewer only ever sees a diff that
already passes what a machine can check.

When the diff touches tests, `test-review`'s `scripts/revert-check.sh` runs
here too: it reverses the non-test hunks, runs the changed tests, restores the
tree, and names any test that still passed. Each is a finding before a
reviewer reads it.

`check` ends with `reuse-guardrails`' `scripts/reuse-scan.sh` over the same
paths: new files in a shared layer, new exports that already exist elsewhere or
carry a textbook helper's name, dependencies added, hand-roll patterns in the
added lines, and duplicate blocks when the project has `jscpd`. Its flags do
not fail the gate; they go to the reviewer with the snapshot, and on a low-risk
chunk straight into the chunk report's `Reuse:` line. A flag the implementer's
Reuse block already answers is not a finding.

## Implementer dispatch

Add one line to SDD's implementer prompt body:

> If this project has a skill for authoring the kind of file this task
> creates, invoke it before writing the first line. Otherwise follow the
> patterns in the sibling files and say so in one line.

An authoring skill (such as `react-screen-authoring` for a new React screen,
sheet, form or picker) puts the shape in context before generation. Never
inline the skill's rules into the dispatch prompt: they drift within two edits.

**Every implementer dispatch carries an `## Inventory` section.** Once per
chunk, run the inventory script of each rubric the chunk's paths route to
(`react-review`, `nestjs-service-review`, `api-contract-review`, … via
`review-routing`'s table) and paste the output, capped as the script caps it,
under that heading in each implementer prompt. When the plan task names the
helper, the task text names it by export and path as well. The inventory is what the
Global Constraints' "shows none" refers to; an implementer that never saw it cannot be
held to the search. `reuse-guardrails` audits whether a project's own pipeline
copy does this.

## Reviewer dispatch

Add one line to SDD's task-reviewer prompt body:

> If this project has a skill that maps changed paths to review rubrics, invoke
> it first. Otherwise review on general code quality and say so in one line.

Where a project keeps domain review skills, the skill that maps paths to them
(often named `review-routing`) owns the mapping and the single-file-to-diff
adaptation. Never inline that mapping into a dispatch prompt: it drifts within
two edits.

**One reviewer per chunk** is the default, on medium- and high-risk chunks
only, with those rubrics as its checklist; on a backend chunk the routing adds
`observability-review` as a second pass over the backend rows, same seat. Fan
out to a reviewer per rubric only when the diff spans two or more domains *and*
is too large for one reviewer's useful attention. Each fanned-out reviewer gets
only its rubric's slice (`git diff -- <paths> > "$WORKSPACE/chunk-$N-<rubric>.diff"`).
Fan-out costs a full seat each; record why.

**The whole-tree reviewer gets the plan's goal and acceptance criteria** with
the snapshot, the Global Constraints and the whole-tree verifier's lines, and
answers spec before quality: does the tree do what the plan said, then is the
code sound. Chunk reviewers do not get the criteria. When the project has
`jscpd`, its console report over the whole branch goes into the same dispatch
under `## Duplicates`, with the line "every duplicate block here is a finding
unless both copies predate the branch"; a fresh implementer per task never saw
the previous task's helper, so this is the one check that spans tasks.

**Scoped re-reviews get none of this.** No rubric line, no `review-routing`:
the re-reviewer gets the findings list and the fix diff, per SDD's re-review
prompt, and nothing else.

## What the controller reads

The controller never reads a diff snapshot. Its view is the implementer
reports, the reviewer reports and `git diff --stat`; a chunk diff would sit in
the most expensive context for the rest of the run.

## Nothing is ever committed

No subagent and no controller runs `git commit`, `git add`, `git push`, `git
merge`, or opens a PR — not per task, not at the end of a clean run, not to a
worktree branch. Work stays in the working tree for the human to review. This
overrides SDD's implementer-prompt step "Commit your work" and is not
negotiable by a ruling mid-run.

Four of these rules are enforced, not only stated. `chunked-delivery`'s
`scripts/run.sh start` marks the checkout; the plugin's `hooks/guard.sh` then
refuses, with the reason on stderr: any git write (`commit`, `add` without
`-N`, `push`, `merge`,
`rebase`, `stash`, `clean`, `restore`, `reset --hard`, `checkout --`,
`gh pr create`) from the controller or any subagent; a controller read of a
`chunk-*.diff` snapshot; a write from a reviewer seat (redirects, `sed -i`,
`tee`, `rm`, `mv`, installs, `git apply`), run or no run; and a stop by an
implementer whose dispatch named the `## Proof` or `## Reuse` block when the
report lacks it, once. The command checks are best effort on shell text; the
rules still bind where the hook cannot see.

Two pieces of SDD assume commits, so they are replaced:

**Review ranges.** SDD hands reviewers `BASE_SHA..HEAD_SHA`. With no commits,
snapshot the working tree and hand the reviewer the file:

```bash
git add -N .                                   # makes new files visible to diff
git diff > "$WORKSPACE/chunk-$N.diff"
```

`git add -N` records paths only, never content — `git reset` undoes it. It is the
one index touch this process makes; without it new files are invisible to the
reviewer. The reviewer reads the snapshot file, does not re-run git, and stays
read-only.

**Recovery.** SDD's ledger recovers from commit SHAs, which no longer exist.
Snapshot before a chunk as well as after — `chunk-$N-before.diff` and
`chunk-$N.diff`. Those two files are the run's only undo, and `git apply -R` on
the after-snapshot is "redo". When asked to discard work, say there is no cheap
restore point and get it confirmed first.

**Review map.** When the human asks for one (`chunked-delivery` says when and
what), derive it from the snapshots: file rows from the current
`git diff --numstat`, less what `chunk-$N-before.diff` already held. Republish
after each fix round from a fresh numstat, never by editing the old counts. The
published link goes into the chunk's ledger entry, so a resumed run republishes
to the same page.

## Cross-model review

The second opinion is a different model family reading the same diff. It
attaches at two points, never inside the SDD fix loop:

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
not in place of either: it fires on session stop, unrelated to task boundaries.

## Adjudicating two reviews

Cross-model output is a claim, like the implementer's report. It comes to you,
never straight to a fix dispatch.

- **Both flag it** — fix it, normal fix round.
- **Only the cross-model pass flags it** — check it against the Global
  Constraints and the project's rubrics first; it cannot see them, so its findings
  mix genuine cross-family catches with things the project already decided against.
- **Only the rubric reviewer flags it** — fix it. The other model not seeing
  something is not evidence of absence.
- **They contradict** — you rule. Record it as `Ruling: <decision> — <why> —
  <cost if wrong>`, and keep going.

A run that stops to ask which reviewer was right has cost more than the wrong
ruling would have.
