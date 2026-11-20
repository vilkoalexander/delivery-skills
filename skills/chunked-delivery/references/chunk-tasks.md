# Chunk tasks

Read when the session has the `TaskCreate` tool. The task list of Claude Code
then shows the chunk list.

- When the human approves the cut, make one task for each chunk. The subject
  is `Chunk N/M — <name> [risk]`.
- Set the task to `in_progress` at step 1 of the chunk.
- Set the task to `completed` after you add the line of the chunk to the run
  log. The hook refuses the completion before that. In long-run mode, this is
  at the final `ok`.
- After a `redo`, the task stays `in_progress`.

The tasks stay after a compaction. They do not replace `mark.sh` or the run
log: a task has no phase and no counts.
