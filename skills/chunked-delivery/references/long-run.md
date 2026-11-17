# Long-run mode

Read when the human answers the cut with `long`. A different approval keeps
the stop after each chunk.

Long-run mode is one long task, in this checkout, while the human is away. All
steps of the loop run. Only steps 8 and 9 change.

## After step 7: stop or continue

Stop and report as a normal chunk if one of these is true. A `next` from the
human then continues in long-run mode.

- The chunk is high risk.
- A finding is parked, or a `FAIL` line stays after the last fix round.
- The static gate fails after the two static rounds.
- The chunk became larger than the size limit.
- The chunk showed that the plan is wrong.

If none is true, add the entry of the chunk to `$WORKSPACE/long-run-report.md`
and start the next chunk. Write no chunk report in the conversation.

A low-risk chunk has no verify of its own. Add its `exercise:` line to the
list for the whole-tree verify.

## The entry

```
## Chunk N/M — <name>   [risk]   <files> files, <added>/<removed> lines
Changed:  <one or two lines of what it now does>
Criteria: <one line per acceptance criterion: pass with what the verifier saw,
          or "whole-tree verify" on a low-risk chunk>
Needs you: <each "needs human" tap and "not verified" item, or "nothing">
Rulings:  <decisions that could have gone the other way, or "none">
Diff:     diff -u <$WORKSPACE>/chunk-N-before.diff <$WORKSPACE>/chunk-N.diff
```

Snapshots are cumulative. Thus the `Diff:` command is the way to see one chunk
alone.

## After the last chunk

Do `references/final.md` as written, with two changes to the final report:

- Add a `Report:` line with the path of `long-run-report.md`.
- The `Next:` line is `"ok"` · `"fix N <thing>"` · `"stop"`.

You cannot undo one chunk after later chunks are on top of it. Thus a chunk
that the human rejects is a `fix`, not a `redo`. Do the handoff only after
the human says `ok` or `stop`.

Add the run-log line for each chunk at the final `ok`.
