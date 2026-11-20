---
name: run-retro
description: Use when asked for a retro or retrospective of a delivery run, what a chunked-delivery run got wrong, why the human had to fix or redo chunks, or which check or rubric line would have caught a defect. Not for a weekly "what did we ship" summary.
---

# Run Retro

Looks back at one finished delivery run and proposes changes to what the next
run starts with: a check, a rubric line, a question asked earlier, a fix in
this plugin. It changes nothing until the human picks.

## Workflow

1. **Sources.** `bash scripts/sources.sh list`, then
   `bash scripts/sources.sh <run>`; the newest run when none is named. It
   prints the chunks, the decisions, what the human typed, the refusals, the
   gate failures, the failed tool calls and the transcript paths.
2. **Human turns first.** They are the review comments of the run. Skip the
   approvals. Each of the others is one of:
   - a `fix` or `redo`: a defect that passed the gate and the review;
   - a design question or a correction in the middle of the run: a decision
     that nobody asked before the plan was approved;
   - a question about a report: the report did not say it.
3. **Then the machine side.** A chunk with two or more fix marks, a gate step
   that failed, a refusal that repeats, failed tool calls, a compaction, an
   agent transcript far longer than its neighbours.
4. **Find the cause, not the symptom.** For each candidate that needs it,
   dispatch one Explore reader on one transcript with one question, such as
   "what did this implementer try before the third fix round, and what did it
   not know". Give the path and the time. Do not read a transcript yourself:
   the controller's is thousands of lines.
5. **Give each cause one destination** from the table below.
6. **Report** in the format below, worst first, ten items at most. Write
   nothing.
7. **On a pick, do that item** and show the diff. An issue is drafted, and
   filed only on a yes.

## Destinations

| The cause is | It goes to |
| --- | --- |
| A mechanical pattern: a banned API, an import shape, a file location, a syntax form | A deterministic check: a rule in the project's linter, a line in `docs/review/drift.checks`, or a step in `docs/review/delivery.json`. Where the codebase already breaks it, ratchet: fail on a count above today's |
| A judgement call that the reviewer did not make | One line in `docs/review/<rubric>.md`, written as a rule a reviewer can examine |
| A word that meant two things, or two words for one thing | `GLOSSARY.md` |
| A decision made in the middle of the run that had a real alternative | An ADR in `docs/adr/`; if it has no exceptions, also one invariant line for the Global Constraints |
| An implementer that could not find what exists | A pointer in `CLAUDE.md` or `AGENTS.md`, or the rubric's inventory script |
| A document that teaches the rejected pattern | That document |
| The pipeline: a refusal on a legitimate action, an instruction no seat followed, a report the human could not read | An issue on this plugin |

- A check beats a sentence. If a script can decide it, do not write a rule.
- One cause, one destination. The same cause behind five symptoms is one item.
- No evidence, no item: each item names its chunk, its time and a quote or a
  count from the sources.
- One occurrence is an item only when the human named it.

## Report

```
Retro — <run>   <project>
<chunks> chunks · <n> human fixes · <n> fix rounds · <n> refusals

1. <what went wrong, one line>
   seen:  chunk N · <time> · "<quote>" or <count>
   cause: <one line>
   do:    <destination> — <the exact rule, line or check>

Not worth a change: <one line each, with the reason>
Next: "do 1 3" · "issue 4" · "skip"
```
