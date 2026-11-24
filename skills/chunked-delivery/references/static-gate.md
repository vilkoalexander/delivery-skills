# The steps of `static-gate.sh check`

Read when a gate step fails and its output does not tell you what to do, or
when a step needs an allowance. Script paths start at `skills/` of this plugin.

The gate runs all the steps below. `STATIC_SKIP` skips steps for one call.
The change is the difference between `DELIVERY_BASE` and the working tree:
the loop sets `DELIVERY_BASE` to the tree before the chunk, and without it
the gate uses `HEAD`.

Each step ends with one status in the summary: `ok`, `flags`, `FAIL`,
`could not run`, skipped, or `n/a`. A step that could not run fails the gate,
also a scan that only gives flags: a config that is not valid, a pattern that
does not compile and a range that git does not know are not a pass. Exit 0
is clean, 1 is a failure, 2 means that the gate could not start.

## 1. Test lock

`test-review/scripts/test-lock.sh` examines each test file that was there
before the change. It fails on:

- a deleted or renamed file;
- a removed test;
- a removed or changed assertion;
- an added `skip`, `only` or `todo`;
- an added bare `return` in a test.

Added tests and new test files pass.

If a plan task names a test file as a file to change, set `TEST_LOCK_ALLOW` to
a regex of those paths for the gate of that chunk. The gate lists them as
permitted. Name them on the `Rulings:` line of the chunk report.

## 2. Drift

`delivery-pipeline/scripts/drift.sh check` runs when the project has
`docs/review/drift.checks`. Each line of that file names two copies of one
fact and the command that fails when they do not agree. Examples: the schema
and the migrations, the API and its generated client, the native dependencies
and the SDK.

Only a check whose `when` regex matches a changed path runs. `coverage` lists
the pairs that the project has and does not examine, as `drift:<name>` in the
`ABSENT:` list.

## 3. The steps from the config

For each changed path, the gate finds the workspace in
`docs/review/delivery.json` with the longest matching directory. It runs the
commands of that workspace in the workspace directory. `{files}` in a command
becomes the changed paths that exist.

- A step with no command is `skipped`. A skipped step goes in the chunk
  report. It is not a pass.
- A step that the config sets to `false` is off for that workspace.
- Do not change a command during a run to make a chunk pass.

## 4. Revert check

`test-review/scripts/revert-check.sh` runs when the change touches tests and
source files. It runs the changed tests with the change: they must pass. Then
it puts the source files back to what they were before the change, runs the
tests again, and restores the tree. It names each test file that passed with
the change reversed. Each name is a failure of the gate. Send it back in a
static round. Set `TEST_CMD` when it cannot find the test runner; a runner
that it cannot find is `could not run`, not a pass.

## 5. Reuse scan

`reuse-guardrails/scripts/reuse-scan.sh` runs last, on the same paths. It
gives flags and does not fail the gate. It flags:

- a new file in a shared layer;
- a new export that exists in a different file, or has the name of a common
  helper;
- an added dependency;
- a hand-made version of a common helper in the added lines;
- duplicate blocks, when the project has `jscpd`.

The gate does not vet dependencies. The hook does it before an install or an
`npx` during a run, with `delivery-pipeline/scripts/dep-vet.sh`, and refuses
on `BLOCK`: the registry does not know the name or has no published version,
the package is less than 30 days old, the version is less than 7 days old, or
a malware advisory exists. Put private scopes in `deps.allow` in
`docs/review/delivery.json`.

The flags go to the reviewer with the snapshot. On a low-risk chunk they go
directly to the `Reuse:` line of the chunk report. A flag that the Reuse block
of the implementer answers is not a finding.

## What the gate leaves to other tools

- Credentials: the CI of the project.
- A silenced checker, a cast to `any`, a comment that defers the fix, a
  function that is too complex: the lint step. `delivery-pipeline/STATIC-SETUP.md`
  has the ESLint rules, and `static-gate.sh coverage` names each one that is
  absent. A lint rule fails the gate; it is not a flag.
