# Phases 4 and 5: the whole tree, then handoff

Read when the human approves the last chunk. The run is not complete at that
time. Each chunk review saw the diff of one chunk only. Nothing examined the
work as a whole.

Record the phase: `bash chunked-delivery/scripts/mark.sh phase=final`. Record
each step of this pass with a mark that has no `chunk`:
`mark.sh phase=verify`, then `phase=review`, `phase=cross`, `phase=fix`,
`phase=gate`, `phase=report`.

## Do these three steps, one time, in this order

1. **Verify the whole tree.** Dispatch the verifier with each acceptance
   criterion of the plan. In long-run mode, also give it the `exercise:` line
   of each low-risk chunk. Its lines become the `Spec:` line of the report. A
   criterion that nobody ran is not met.
2. **Review the whole tree.** Take a snapshot of all that the run changed:
   `bash chunked-delivery/scripts/snapshot.sh final` writes
   `$WORKSPACE/final.diff`. Dispatch one reviewer
   on Opus 5.5 against it, not against the snapshot of the last chunk. Give it:
   - the snapshot;
   - the goal and the acceptance criteria of the plan;
   - the Global Constraints;
   - the lines of the whole-tree verifier;
   - each `Assumed:` line of the plan;
   - if the project has `jscpd`, its console report for the full branch, below
     the heading `## Duplicates`, with this line: "every duplicate block here
     is a finding unless both copies predate the branch".

   The reviewer answers spec first, then quality: does the tree do what the
   plan said, and then is the code sound. A fresh implementer for each task
   did not see the helper of the task before it. Thus the duplicate report is
   the only check across tasks.
3. **Cross-model review of the whole working tree.** Do it for each run, for
   all risk classes. `references/cross-model.md` has the command and the rules
   for a ruling.

## Findings

A finding or a `FAIL` line gets the same treatment as in a chunk. Tell the
human in one line that fix rounds are in progress. The limit is five rounds,
and `mark.sh` holds it. Run the static gate after each fix round:
`DELIVERY_BASE=$(bash chunked-delivery/scripts/snapshot.sh base final)`.
Then report what stays open.

## The final report

Write one more report in the chunk format. Its name is `Final — whole tree`.
Add one line after `Proof:`:

```
Spec:    met · or one line per acceptance criterion the tree does not meet
```

- A `Spec:` line with gaps is a conversation with the human about the plan.
  It is not a fix round. A tree that is ready for merge is not always ready
  for launch.
- If a step finds something that changes an approved chunk, tell the human
  clearly. Do not open the chunk again without a word. The human approved
  what the report showed.

## Handoff

After the final report, when the human has no `fix` for it, run
`bash chunked-delivery/scripts/run.sh stop`. Git
writes are then permitted again. The working tree belongs to the human: the
human reads it, commits what is correct, and ships it in the way of the
project.

End the handoff with one line: `retro` looks at this run with the `run-retro`
skill. Do not start it unless the human says so.
