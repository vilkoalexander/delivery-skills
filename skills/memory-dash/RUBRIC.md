# Memory audit rubric

What the audit calls a defect, and what it never flags. The score table at
the bottom is the only place the weights live; `render.py` copies it.

## Read everything

The audit reads every memory file of the project in full, plus `MEMORY.md`.
Descriptions alone are not enough: two files with different descriptions can
state the same fact, and two with the same description can disagree. The
dashboard prints files read next to files on disk; a gap is a defect in the
audit, not in the memory.

## Definitions

**Duplicate, confirmed.** Both files state the same fact and one body adds
nothing the other lacks (a subset, or a rewording). `keep` is the richer or
more recent one. Only a confirmed duplicate gets a `merge` or `delete` action.

**Duplicate, plausible.** Same subject, overlapping content, but each file has
something the other does not. Gets a `resolve` action that asks the user, or a
`merge` action whose `edit` carries the combined content, never a bare delete.

**Conflict.** Two files give different values for one fact: a different
number, date, owner, decision, or rule. A newer mtime does not settle it; the
newer file may be the one that is wrong. `resolution` names the winner only
when one file itself says it replaces the other, or when a third file settles
it. Otherwise `resolution: unknown` and a `resolve` action.

**Superseded.** The newer file explicitly or obviously replaces the older one
(a re-plan, a new address, a decision reversed) and the older file carries no
other fact worth keeping. Gets a `delete` of the older file or a `rewrite` of
the newer one that absorbs any remaining detail.

**Stale.** A project memory whose subject has concluded, a date that has
passed, a plan the user has since replaced elsewhere in memory, a relative
date ("next week") with no anchor. Gets `rewrite` (make it a fact about what
happened) or `delete`.

**Task-like.** Reads as a todo, a plan step or a status update rather than a
durable fact: "need to", "next: ", "waiting on". Memory is for what is true,
not what is pending. Listed for the user; gets `rewrite` only when a durable
fact can be extracted, otherwise `delete`.

**Quality 1–5**, per file. 5: one fact, precise, with why and how to apply,
indexed, typed. 4: minor gap. 3: several facts in one file or missing the why.
2: vague, or a narrative. 1: not a fact at all. Quality below 3 may produce a
`rewrite` action but never a delete on its own.

## Never flagged

- A memory that is merely old. Age is a signal only with another defect.
- A `user` or `feedback` memory for being long; those earn their length.
- Non-English content, mixed languages, informal wording.
- The same fact across two different projects. Cross-project duplication is
  intentional: each project loads only its own memory.
- Anything in a project that was not audited this run.

## Next actions

At most 7, numbered, ordered: conflicts, confirmed duplicates, superseded,
reindex, stale, rewrite. Each one has `kind`, `files`, a one-line imperative
`text`, and for `merge` and `rewrite` the complete resulting file content in
`edit`, frontmatter included. `apply.py` is mechanical; the judgment is all in
`edit`.

Deterministic defects from the inventory (`not_indexed`, `dangling_index`,
`broken_link`) become `reindex` actions without reading the file.

## Score

Start at 100. Per project. Each line is a penalty per item with a cap.

| Defect | Per | Cap | Source |
| --- | --- | --- | --- |
| not_indexed | 3 | 15 | inventory |
| dangling_index | 3 | 15 | inventory |
| broken_link | 2 | 10 | inventory |
| no_type | 2 | 10 | inventory |
| no_description | 2 | 10 | inventory |
| relative_date | 1 | 5 | inventory |
| thin | 1 | 5 | inventory |
| unresolved conflict | 8 | 24 | audit |
| confirmed duplicate | 5 | 20 | audit |
| superseded pair | 3 | 12 | audit |
| stale | 1 | 5 | audit |

Without an audit the last four lines are skipped and the score is labelled
"stats only". The previous score of the same label is shown as a delta.
