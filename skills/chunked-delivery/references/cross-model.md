# Cross-model review

Read before the first cross-model review of a run.

A different model family reads the same diff. It runs at two points, and not
inside the SDD fix loop:

1. **For a chunk, high risk only:** after the chunk review passes, before the
   chunk report.
2. **For the whole working tree, each run:** after the whole-tree review,
   before the handoff.

## The command

With the Codex plugin installed:

```bash
CODEX_ROOT=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ | sort -V | tail -1)
node "${CODEX_ROOT}scripts/codex-companion.mjs" adversarial-review --background --scope working-tree <focus text>
```

These facts are from codex 1.0.4:

- `adversarial-review` takes the focus text by position. Thus a flag that it
  does not know becomes focus text and starts a real review.
- `--help` works only alone (`codex-companion.mjs --help`), not after a
  subcommand.
- `review` is the built-in reviewer and takes no focus text. Use
  `adversarial-review` when you must aim the review.
- `--scope` accepts `auto`, `working-tree` or `branch`. The two subcommands do
  not support staged-only or unstaged-only.

## The focus text

Give the goal of the chunk in one line, then this:

> For each finding, give the command that shows it and the output that it
> printed. Mark a finding that you did not run with `not run`.

A finding with a command is cheap to rule on: run the command. A `not run`
finding is a claim about how the code reads.

The review gate at session stop (`/codex:setup --enable-review-gate`) is a
third, separate layer. It runs when the session stops, not at the end of a
task. It does not replace the two points above.

## A ruling on two reviews

The cross-model output is a claim, as the implementer report is. It comes to
you. Do not send it directly to a fix dispatch.

| Who has the finding | Do |
| --- | --- |
| The two reviews | Correct it in a normal fix round |
| Only the cross-model review | If it has a command, run the command first: output that does not show the failure ends the finding. Then compare it with the Global Constraints and the rubrics of the project first. The other model cannot see them. Some of its findings are real, and some are things that the project decided against |
| Only the rubric reviewer | Correct it. A finding that the other model did not see can still be real |
| The two reviews disagree | You decide. Record `Ruling: <decision> — <why> — <cost if wrong>` and continue |

Do not stop the run to ask which reviewer is correct. That stop costs more
than a wrong ruling.
