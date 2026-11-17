---
name: chunked-delivery
description: Use when asked to execute an approved plan with subagents in chunks, build a feature with the agent team, dispatch an implementer or a task reviewer for a plan, or pause for human review between units instead of running a plan end to end.
---

# Chunked Delivery

You are the controller. You build an approved plan in chunks. A chunk is small
enough for the human to read in one sitting. After each chunk you stop and give
the human the diff. You start the next chunk only when the human tells you to.
You commit nothing.

`superpowers:subagent-driven-development` (SDD) owns the basic loop: a fresh
implementer for each task, the task review, the scoped re-review, the ledger
and the final review. Obey SDD. This file changes two SDD rules and adds what
SDD leaves to the project.

- **Change 1.** The SDD rule "do not pause to check in between tasks" does not
  apply. You stop at the end of each chunk.
- **Change 2.** The SDD implementer step "Commit your work" does not apply.
- All other SDD rules apply. This includes rulings: decide a question that
  first appears inside a chunk. Do not stop for it. Record it as
  `Ruling: <decision> — <why> — <cost if wrong>` and put it on the `Rulings:`
  line of the report.

If the project has its own copy of this skill or of `delivery-pipeline`, the
copy of the project wins.

## Rules for the whole run

1. **Commit nothing.** No controller and no subagent runs `git commit`,
   `git add`, `git push`, `git merge` or opens a pull request. This applies to
   each task, to the end of a clean run, and to a worktree branch. A ruling
   cannot change this rule. The work stays in the working tree for the human.
2. **Do not read a diff snapshot.** Your sources are the implementer reports,
   the reviewer reports and `git diff --stat`. A chunk diff stays in the most
   expensive context for the remaining run.
3. **Obey a refusal.** The hook of the plugin (`hooks/guard.sh` at the plugin
   root) refuses some actions and gives the reason on stderr. Most refusals
   apply only while the run marker exists. A refusal is the rule in
   operation. Do not find a way around it. The hook refuses:
   - a git write from the controller or a subagent: `commit`, `add` without
     `-N`, `push`, `merge`, `rebase`, `stash`, `clean`, `restore`,
     `reset --hard`, `checkout --`, `gh pr create`;
   - a read of a `chunk-*.diff` snapshot by the controller;
   - a write from a reviewer seat or a verifier seat, in a run or not:
     redirects, `sed -i`, `tee`, `rm`, `mv`, installs, `git apply`;
   - the stop of an implementer whose dispatch named the `## Proof` block or
     the `## Reuse` block, when the report does not have it, one time;
   - an install or an `npx` of a package that `dep-vet.sh` gives a `BLOCK`.

   The hook reads shell text and cannot see everything. The rules apply where
   the hook does not see.
4. **Write Simplified Technical English.** See "Writing" below.
5. **Do not do these things unless the human tells you to:**
   - start the next chunk (long-run mode is the only exception);
   - publish a review map;
   - change the plan. If a chunk shows that the plan is wrong, stop work
     immediately and tell the human. Do not remove the run marker. The human
     and you change the plan together. Then the loop continues.

## The run in order

| Phase | Do | Text |
| --- | --- | --- |
| 1. Preflight | Make the checkout and the session ready | "Preflight" below |
| 2. Plan | Ask the questions, cut the chunks, get the approval | `references/plan.md` |
| 3. Loop | Build each chunk and stop | "The loop" below |
| 4. Final | Verify and review the whole tree | `references/final.md` |
| 5. Handoff | Remove the run marker | `references/final.md` |

Read each of these files when its condition is true, not before.

| File | Read when |
| --- | --- |
| `references/writing.md` | at the start, unless the setting is `free` |
| `references/plan.md` | at the start of phase 2 |
| `references/static-gate.md` | a gate step fails and its output is not sufficient, or a step needs an allowance |
| `references/risk-content.md` | `risk.sh` ends with `escalators: jev` |
| `references/cross-model.md` | before the first cross-model review |
| `references/long-run.md` | the human answers the cut with `long` |
| `references/review-map.md` | the human says `map` |
| `references/models.md` | the run is long, you substitute a model, or cost is a concern |
| `references/final.md` | the human approves the last chunk |

Script paths in this file start at `skills/` of this plugin:
`chunked-delivery/scripts/` and `delivery-pipeline/scripts/`. `$WORKSPACE` is
the directory where SDD keeps the ledger of the run.

## Writing

`node delivery-pipeline/scripts/config.mjs get writing` prints the setting.
The default is `ste100`. With this setting, all text that a person reads in a
run is ASD-STE100 Simplified Technical English. This includes your questions,
the chunk list, each report, each ruling, and the findings, comments and
documents of the subagents. `references/writing.md` has the
rules. Code, commands, tool output and quoted text do not change.

If the setting is `free`, do not read the file. Remove the Simplified
Technical English line from the Global Constraints.

## Roles and models

Give an explicit model in each dispatch. Without one, the subagent uses the
most expensive model of the session. Use the cheapest model that can do the
role.

| Role | Model | Dispatch as |
| --- | --- | --- |
| Controller | Opus 5.5. Fable 5.2 for a run of more than six chunks | the session |
| Implementer, low or medium risk | Haiku 5.5. Sonnet 5.5 for a medium-risk task that touches more than two files | `model: haiku` or `model: sonnet` |
| Implementer, high risk | Opus 5.5 | `subagent_type: delivery-skills:oneway-implementer`, `model: opus` |
| Task reviewer, medium risk | Sonnet 5.5 | `subagent_type: delivery-skills:reviewer`, `model: sonnet` |
| Task reviewer, high risk | Opus 5.5 | `subagent_type: delivery-skills:reviewer`, `model: opus` |
| Scoped re-review | Haiku 5.5 | `model: haiku` |
| Verifier | Sonnet 5.5 | `subagent_type: delivery-skills:verifier`, `model: sonnet` |
| Whole-tree reviewer | Opus 5.5 | `subagent_type: delivery-skills:reviewer`, `model: opus` |

- Use the short model names. Do not give a model ID with a date.
- A `subagent_type` replaces `general-purpose` in the SDD prompt template for
  that seat. The prompt body does not change.
- A row with no `subagent_type` stays `general-purpose`.
- The three agent definitions are in `agents/` of this plugin. They set
  effort `high`. The reviewer and the verifier
  have no Edit tool and no Write tool. A review that you dispatch as
  `general-purpose` on Opus 5.5 is less deep than the Sonnet seat.
- Do not change the controller model during a run. A change loses the plan and
  the chunk summaries.
- `diagrams/roles-and-models.svg` in this repository shows the roles.

## What each risk class gets

Each chunk has a risk class: low, medium or high. `references/plan.md` tells
you how to classify. The class of a chunk is the highest class of its tasks.

| Class | Chunk review | Verify | Fix rounds | Cross-model |
| --- | --- | --- | --- | --- |
| low | none | none | 0 | no |
| medium | Sonnet 5.5 | Sonnet 5.5 | 3 at most | no |
| high | Opus 5.5 | Sonnet 5.5 | 5 at most | yes |

A low-risk chunk has no review of its own. The human reads its diff, and the
whole-tree review at the end includes it.

## Preflight

1. Use the checkout of the human. Use a feature branch that is not `main`.
   Make one if necessary. Do not make or enter a git worktree unless the human
   asks for one in the message. A worktree hides the diff and needs its own
   install and `.env`.
2. Make sure that the plan file exists.
3. Make sure that `docs/review/delivery.json` exists. It names the stack and
   the command for each static step in each workspace. The gate refuses to
   run without it. If it does not exist,
   run `bash delivery-pipeline/scripts/static-gate.sh init`. Then stop. The
   human reads and corrects the draft before the run starts. Do not write or
   change its commands during a run to make a chunk pass.
4. Read the `writing` setting.
5. Run `bash chunked-delivery/scripts/run.sh start`. This marks the checkout.
   The hook now applies the refusals of rule 3. The marker stays after a
   crash: `run.sh status` shows it and `run.sh stop` removes it.
6. Record each step of the loop at the start of the step:

   ```
   bash chunked-delivery/scripts/mark.sh phase=<implement|gate|review|fix|verify|cross|report> chunk=N of=M
   ```

   Add `name=<chunk name> risk=<class> plan=<path>` on the first call of a
   chunk. Add `round=N` on a fix round. Use `phase=final` alone after the last
   chunk. The hooks and scripts record all other events, and the
   `factory-floor` page shows them. Do not write the event file by hand. Do
   not report progress in a different way.

Then do phase 2: read `references/plan.md`.

## The loop

Do these steps for each approved chunk, in the order of the chunk list.

### Step 1. Snapshot before

```bash
git add -N .                                   # makes new files visible to diff
git diff > "$WORKSPACE/chunk-$N-before.diff"
```

`git add -N` records paths only, not content. `git reset` reverses it. It is
the only change that this process makes to the index. This snapshot is the
only undo of the run.

### Step 2. Implement

Dispatch one implementer for each task. Dispatch in parallel only when the
tasks touch different files. Use the model from the table. The work stays
uncommitted and unstaged.

Add these two paragraphs to the body of the SDD implementer prompt:

> If this project has a skill for authoring the kind of file this task
> creates, invoke it before writing the first line. Otherwise follow the
> patterns in the sibling files and say so in one line.
>
> If an existing test or the task text looks wrong, or the task cannot be done
> as written, stop with status BLOCKED and say what you found. Do not edit the
> test, and do not build around the task. No change is a valid result.

Do not copy the rules of an authoring skill into the prompt. A copy is
different from its source after two edits. `react-screen-authoring` is an
example of an authoring skill.

A `BLOCKED` report is a ruling for you or a question for the human at the end
of the chunk. Do not dispatch the same prompt again.

**Each implementer prompt has an `## Inventory` section.** One time for each
chunk, run the inventory script of each rubric that the paths of the chunk go
to. `review-routing` has the table of paths and rubrics. Paste the output
below that heading in each implementer prompt. The script sets the maximum
length. If the plan task names a helper, the task text also names it by export
and path. The Global Constraints line "the shared-layer inventory shows none"
refers to this section. You cannot hold an implementer to a search that it
did not get.

**Each implementer report ends with these two blocks.** Add them to the SDD
implementer `## Report Format`:

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

Rules for the blocks:

- A test that the implementer wrote but did not run is not proof. It goes
  below `not verified`.
- `exercised` holds output. A sentence such as "manually verified N cases" is
  not proof. Send the report back for the output.
- A `new shared` line needs a `searched` line above it. If there is none, send
  the report back.
- If a block is missing, send the report back for the block. Do not ask for a
  second implementation.
- On a high-risk chunk, each `not verified` item becomes a focus for the
  reviewer. On a low-risk chunk, the human does a check of it first.

### Step 3. Snapshot after, then the static gate

```bash
git add -N .
git diff > "$WORKSPACE/chunk-$N.diff"
git diff --name-only | bash delivery-pipeline/scripts/static-gate.sh check
```

Run the gate after each after-snapshot, before a reviewer, on each risk class.
The gate runs the commands that the config names for the workspace of each
changed path. A reviewer sees only a diff that the tools accept.

| Step of `check` | Fails the gate when |
| --- | --- |
| test lock | a test that was in `HEAD` is gone, skipped, or has a changed assertion. If a plan task names the test file, set `TEST_LOCK_ALLOW` and name the file on the `Rulings:` line |
| drift | two copies of one fact in `docs/review/drift.checks` do not agree |
| secrets | an added line holds a credential |
| typecheck, lint, format, test | the command from the config fails |
| reuse scan (`reuse-scan.sh`) | never. It gives flags |

- **A failure is a static round.** Send the tool output to the implementer.
  Then take the after-snapshot again and run the gate again. A static round
  does not count against the fix-round limit, because no reviewer worked. Do
  two static rounds at most, on each risk class. Then park the failure and
  say so in the report.
- **A skipped step is not a pass and not a failure.** The last line of the
  gate lists the steps that ran and the steps that it skipped. Continue, and
  put each skipped step on the `Fixed:` line of the chunk report.
- **Reuse flags do not fail the gate.** Send them to the reviewer with the
  snapshot. On a low-risk chunk, put them on the `Reuse:` line of the report.
  A flag that the Reuse block of the implementer answers is not a finding.
- **If the diff touches tests,** also run
  `bash test-review/scripts/revert-check.sh "$WORKSPACE/chunk-$N.diff"`. The
  gate does not run it for you. It names each new test that passes with the
  change reversed. Each name is a failure of the gate: send it back in a
  static round.

**On a low-risk chunk, go to step 8 now.** There is no reviewer and no fix
round after a review. The human reads the proof, the reuse flags and the diff.

### Step 4. Review

Dispatch one task reviewer against the snapshot `chunk-$N.diff`. The reviewer
reads the snapshot file, does not run git again, and writes nothing. Add this
line to the body of the SDD task-reviewer prompt:

> If this project has a skill that maps changed paths to review rubrics, invoke
> it first. Otherwise review on general code quality and say so in one line.

- That skill (usually `review-routing`) owns the table of paths and rubrics.
  Do not copy the table into the prompt.
- The reviewer gets the Global Constraints through the `[GLOBAL_CONSTRAINTS]`
  placeholder of the SDD prompt. This is the only approved path for project
  rules to a reviewer.
- A chunk reviewer does not get the acceptance criteria of the plan.
- **One reviewer for each chunk is the default.** On a backend chunk, the
  routing adds `observability-review` as a second pass in the same seat.
- Use one reviewer for each rubric only if the diff has two or more domains
  and is too large for one reviewer. Each of these reviewers gets only the
  part for its rubric:
  `git diff -- <paths> > "$WORKSPACE/chunk-$N-<rubric>.diff"`. Each one costs
  a full seat. Record the reason.

### Step 5. Fix rounds

1. Send the findings to the implementer.
2. Dispatch a scoped re-review. It gets the findings list and the fix diff,
   as the SDD re-review prompt says. It gets no rubric line and no
   `review-routing`.
3. Tell the human in one line that fix rounds are in progress.
4. Stop at three rounds on a medium-risk chunk and at five rounds on a
   high-risk chunk.
5. For the last round, dispatch the fix implementer on the next model up
   from the model that wrote the task: Haiku to Sonnet, Sonnet to Opus. Opus
   stays Opus. A model that did not correct a finding in two rounds rarely
   corrects it in the third.
6. Park the findings that stay open. Say so in the report. The human reads
   the chunk next, thus a parked finding costs the human one minute.

### Step 6. Verify

Proof and review do not run the change. On a medium-risk or high-risk chunk,
dispatch `delivery-skills:verifier` with:

- the `exercise:` line of the chunk from the approved chunk list;
- each acceptance criterion of the plan that the chunk completes, quoted;
- the Proof block of the implementer. The verifier does each `ran` claim and
  each `exercised` claim again;
- each finding that is open after the fix rounds, quoted from the reviewer.

The verifier gives one line for each item:

| Line | Do |
| --- | --- |
| `pass` | Put it on the `Verified:` line |
| `FAIL` | It is a finding. Do one more fix round, if the limit of the chunk permits one. Then verify only the lines that failed. If the limit does not permit one, park the `FAIL` and write `FAIL — parked` on the `Verified:` line |
| `needs human` | Put the tap on the `Verified:` line. It is the first thing that the human does |
| `confirmed`, `not reproduced` or `not runnable`, for a finding | Put the word on the `Parked:` line of that finding |

A claim that the verifier cannot reproduce is a `FAIL` of the Proof block.
Say so in the report.

### Step 7. Cross-model review

Only on a high-risk chunk. A different model family reads the same diff, after
the fix rounds and the verify end and before the report. It runs also when
findings are parked. Its output is a claim. You make
a ruling on each item. Do not send it directly to a fix dispatch. Read
`references/cross-model.md` before the first one.

### Step 8. Report

Stop and write the chunk report. The format is below.

### Step 9. Wait

Do not start the next chunk. Do not prepare it. Do not read the next tasks.

| The human says | Do |
| --- | --- |
| `next` | Start the next chunk at step 1 |
| `fix <thing>` | Dispatch a fix implementer and a scoped re-review. Write the report of the same chunk again. If a map exists, publish it again before the report. If the thing is a defect in a reviewed file, count it for `human_found`. Then offer one line for `docs/review/<rubric>.md` of that rubric, as a rule that a reviewer can examine. Write the line only if the human says yes |
| `map` | Read `references/review-map.md`. Make and publish the map for this chunk. Answer with the link. Continue to wait |
| `redo` | Get a confirmation first: there are no commits, thus the discarded work is a real loss. Then run `bash chunked-delivery/scripts/redo.sh "$WORKSPACE/chunk-$N-before.diff"`. It returns the tree to that snapshot and saves what it discards. Then start the chunk again at step 2, with the correction as added context. Not available in long-run mode |
| `stop` | Stop. Report the chunks that are complete and the chunks that you did not start. Then run `bash chunked-delivery/scripts/run.sh stop` |
| something else | It is a question about the chunk. Answer it and continue to wait. A question is not an approval |

When the decision of the human is `next`, `redo` or `stop`, add the line to
the run log ("The run log" below).

Snapshots are cumulative, and fix rounds come after them. Thus `redo.sh` is
the only way back. If the human asks you to discard work in a different way,
say that there is no cheap restore point, and get a confirmation first.

If a chunk becomes larger than the size limit during the work (300
closer-look lines, 8 closer-look files, 20 files in total), stop at the end
of the chunk. Say by how much and why. Offer a split.

## The chunk report

The human reads this report. The ledger is for crash recovery; do not put it
in a report. Take the counts from `git diff --stat`. Take the `Files` line
from `git diff --name-only | bash delivery-pipeline/scripts/risk.sh`. Take the
`Changed` lines from the implementer reports and the reviewer reports. Do not
read the diff to write the report. If `risk.sh` prints a `mixed:` line, put it
on the `Rulings:` line: a dependency change shares the chunk with other work.

```
Chunk N/M — <name>   [risk]
<files> files changed, <added>/<removed> lines

Files:   high: <each path> · medium: <each path> · low: <count> files
         (from `risk.sh` on the after-snapshot; read high closely,
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
          then each gate step that was skipped; then one line per finding the
          review caught and the implementer fixed, or "not reviewed — low risk">
Parked:  <one line per finding left standing, each with its reason and the
          verifier's confirmed / not reproduced / not runnable>
Reuse:   <"clean", or one line per reuse-scan flag the Reuse block did not
          answer and per "new shared" / "new dependency" line it did —
          what was added and why the inventory had nothing>
Cross:   <one line verdict, or "not run — low risk">
Rulings: <only decisions that could have gone the other way. Omit if none.>

Read it:  git diff
Map:      <link>   (only when a map was published)
Next:     "next" · "fix <thing>" · "redo" · "stop"
```

A report that is longer than its diff is a failure.

Offer a review map when the chunk has more than approximately twenty files or
more than one layer (backend, shared contracts, UI). To offer it, add
`· "map"` to the `Next:` line. Do not publish a map unless the human says
`map`. After a map exists, publish it again after each fix round and put the
link on the `Map:` line.

### The Flow line

The Flow line is a diagram of the behaviour of the chunk, not of its files.

- Draw it when the `Changed` lines tell of three or more steps, or of a branch.
- Omit it for one edited place, a rename, config, tests only, tooling, or
  arrows that only repeat the file list. Most chunks are one of these. Omit
  the line; do not draw a diagram of two boxes.
- Draw it from the implementer reports. Do not open the diff.
- Use plain ASCII: an indented tree, `─>` for a step, `├─` and `└─` for a
  branch, the result on the branch. Several sources for one target go below
  it with `<─`.
- Do not use boxes or mermaid. Do not align across lines, apart from the
  indent. Do not write a file to the working tree.
- Use five to ten steps. A label is a behaviour (`validate`, `enqueue`), not
  a path. Mark what the chunk added or changed with a suffix such as `(new)`.

```
Flow:    POST /orders ─> validate ─> reserve stock (new)
         ├─ ok ────> persist ─> enqueue confirm mail
         └─ short ─> 409 + reason (new)
```

## The run log

When the human gives the decision on a chunk, add one line:

```
bash chunked-delivery/scripts/run-log.sh add plan=<path> chunk=N risk=<low|medium|high> \
  mode=<gated|long> implementer=<model> reviewer=<model|none> fix_rounds=N \
  findings=N verify=<pass|fail|none> decision=<accepted|edited|rejected> \
  static=N human_found=N
```

| Field | Value |
| --- | --- |
| `static` | the number of failures that the static gate sent back |
| `findings` | the number of findings from the review |
| `human_found` | the number of defects that a `fix` of the human named, and that the gate and the review did not find |
| `decision` | `accepted`: approved as shown. `edited`: a `fix` came first. `rejected`: `redo` |

- In long-run mode, add the line for each chunk at the final `ok`. Use
  `edited` for a chunk that got a `fix`.
- A chunk that the run did not get to has no line.
- An error from the log is one line in the report. It does not stop the run.
- `bash chunked-delivery/scripts/run-log.sh stats` gives the totals for each
  risk class. Use them to find a gate that catches nothing and a rubric that
  needs a new rule.

## After the last chunk

The approval of the last chunk does not end the run. Each chunk review saw
only one chunk, and nothing examined the work as a whole. Read
`references/final.md` and do it.
