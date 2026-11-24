# The steps of `static-gate.sh check`

Read when a gate step fails and its output does not tell you what to do, or
when a step needs an allowance. Script paths start at `skills/` of this plugin.

The gate runs steps 1, 2, 3, 4, 6 and 7 in this order. You run step 5.
`STATIC_SKIP` skips steps for one call.

## 1. Test lock

`test-review/scripts/test-lock.sh` examines each test file that was in `HEAD`.
It fails on:

- a deleted file;
- a removed test;
- a removed or changed assertion;
- an added `skip`, `only` or `todo`.

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

## 3. Secrets

`delivery-pipeline/scripts/secret-scan.sh` runs on each chunk. It fails when
an added line holds a credential:

- a key in the format of a vendor, in all files;
- a password in a URL, a long literal on a key with a secret name, or a value
  in a committed `.env` file. These three rules skip tests, fixtures and docs.

It prints `path:line — rule` and does not print the value. For a false hit,
add a regex for `path:line:text` to `secrets.allow` in
`docs/review/delivery.json`.

## 4. The steps from the config

For each changed path, the gate finds the workspace in
`docs/review/delivery.json` with the longest matching directory. It runs the
commands of that workspace in the workspace directory. `{files}` in a command
becomes the changed paths that exist.

- A step with no command is `skipped`. A skipped step goes in the chunk
  report. It is not a pass.
- A step that the config sets to `false` is off for that workspace.
- Do not change a command during a run to make a chunk pass.

## 5. Revert check

The gate does not run this step. Run
`bash test-review/scripts/revert-check.sh "$WORKSPACE/chunk-$N.diff"` when the
diff touches tests.
It reverses the hunks that are not tests, runs the changed tests, and restores
the tree. It names each test that passed with the change reversed. Each name
is a failure of the gate. Send it back in a static round.

## 6. Reuse scan

`reuse-guardrails/scripts/reuse-scan.sh` runs last, on the same paths. It
gives flags and does not fail the gate. It flags:

- a new file in a shared layer;
- a new export that exists in a different file, or has the name of a common
  helper;
- an added dependency;
- a hand-made version of a common helper in the added lines;
- duplicate blocks, when the project has `jscpd`.

It also prints what `delivery-pipeline/scripts/dep-vet.sh` says about each
dependency that the diff adds or gives a new version:

| Word | Cause |
| --- | --- |
| `BLOCK` | the registry does not know the name; the package is less than 30 days old; the version is less than 7 days old; a malware advisory exists |
| `FLAG` | the package has an install script, or known advisories exist |

The hook does the same check before an install or an `npx` during a run, and
refuses on `BLOCK`. Put private scopes in `deps.allow` in
`docs/review/delivery.json`.

The flags go to the reviewer with the snapshot. On a low-risk chunk they go
directly to the `Reuse:` line of the chunk report. A flag that the Reuse block
of the implementer answers is not a finding.

## 7. Escape scan

`delivery-pipeline/scripts/escape-scan.sh` runs after the reuse scan, on the
same paths. It gives flags and does not fail the gate. It reads the added
lines of source files that are not tests. It flags:

- a silenced checker: `eslint-disable`, `@ts-ignore`, `@ts-expect-error`,
  `@SuppressWarnings`, a coverage `ignore`;
- a type escape: `as any`, `as unknown as`;
- a comment that defers the fix: "for now", "temporary", "workaround",
  `TODO`;
- a comment that keeps two copies in sync by hand.

Each flag is a line that got past a check and did not correct the cause. The
flags go to the reviewer with the snapshot. A flag is a finding unless its
line is one of these:

- a silenced rule that is wrong for that line, with the reason on the line;
- a workaround for a cause outside the code, with its removal condition.

The correction is the cause. A shorter comment is not a correction. Two
copies that a comment keeps in sync become one line in
`docs/review/drift.checks`.

On a low-risk chunk the flags go directly to the `Escapes:` line of the chunk
report. For a flag that the project accepts, add a regex for `path:line:text`
to `escapes.allow` in `docs/review/delivery.json`.

## 8. Erosion scan

`delivery-pipeline/scripts/erosion-scan.sh` runs after the escape scan, on the
same paths. It gives flags and does not fail the gate. It compares each
function of a source file that is not a test with the function of the same
name before the change. The complexity of a function is one plus its
branches: `if`, a loop, `case`, `catch`, `&&`, `||`, `??`, a ternary. It
flags a function when both of these are true:

- the complexity is higher than before the change;
- the complexity is at the limit or above it. The limit is 10.

A new function is not a flag. The linter of the project owns the size of new
code. The scan reads the text and not a syntax tree, so a callback counts
toward the function around it. The scan names each file that it cannot read.

One branch more in one chunk is small. The same function in each chunk is how
a codebase goes bad while each diff looks fine. The flags go to the reviewer
with the snapshot. A flag is a finding unless the new branch cannot live
apart from the others. The correction moves the new branch into a function
with a name, or splits the function.

On each risk class the flags that stay go to the `Erosion:` line of the chunk
report. For a function that the project accepts as it is, add a regex for
`path:function` to `erosion.allow` in `docs/review/delivery.json`. Set
`erosion.threshold` there to change the limit.
