---
name: verify-recipe
description: Use when asked to write, set up or update how agents run and verify an app — a verify recipe, a run recipe, a feature map — or when the verifier of a delivery run keeps working out how to start the project, drives the wrong screen, or cannot tell which feature a criterion means. Not during a delivery run.
---

# Verify Recipe

Writes down, once, how an agent starts this app, drives it the way a user
does and shows what happened. Two things in the project's `docs/review/`:

- `verify.md` — the recipe: launch, doctor, drive, evidence, cleanup.
- `features/` — the feature map: one file per user-facing feature, saying
  how to reach it, how to drive it and what end state proves it works.

The verifier of `chunked-delivery` reads both instead of rediscovering the
project every chunk, and the plan's `exercise:` lines name features by the
map's names. Nothing is committed; the human reads `git diff`.

The reader is an agent that has never seen the app and opens the file in the
middle of a task. Write for that reader: exact commands, real selectors,
nothing left as a placeholder.

## Workflow

1. **Root.** The repository to write for. Default: the git root of the cwd.
   Never while a delivery run is marked there (`run.sh status`): this skill
   writes project files.
2. **Have one already?** `bash scripts/check.sh <root>`. No recipe: go on.
   A recipe with problems, or a request to update: go to "Keeping it true".
3. **Interview the repository, not the human.** Answer from the code; ask
   only what cannot be observed.
   - *Surface.* What a user touches: a web UI, a mobile app, an API, a CLI.
     Pick the primary one and name the others.
   - *Run.* How it starts locally. The project's own documented command
     first: package scripts, a compose file, the README. Ports, env vars,
     seed data, auth.
   - *Drive.* What already drives it: Playwright or Cypress specs, Maestro
     or Detox flows, a request collection, a debug port. Only when there is
     none, a generic way: a browser tool for web, plain HTTP for a service,
     a PTY for a CLI.
   - *Observe.* What can be captured: screenshots, response bodies, log
     lines, exit codes, rows in the database.
   - *Isolate.* Whether two instances can run side by side. If not, the
     recipe says so: refusing to drive a shared instance beats corrupting
     the human's session.
4. **The checkout must start.** If it does not build or start as it is, stop
   and report exactly what fails. A recipe written against a broken base
   teaches wrong steps.
5. **Write `docs/review/verify.md`** from [`templates/verify.md`](../../templates/verify.md),
   every section from what step 3 found:
   - *Launch* — the command, and how to tell the app is usable, not only
     that a process answers. It reaches a usable state from an empty data
     directory: migrations and seed included.
   - *Doctor* — one read-only command that answers "is this instance worth
     driving": the process is up, the port is ours, the build is current,
     auth is valid.
   - *Drive* — the harness, with real selectors and commands. Stable handles
     (labels, test ids, route paths) over coordinates.
   - *Evidence* — what a proof captures and where it goes: a directory
     outside the working tree. The standards: the real user path, not an
     internal setter or a test-only endpoint; the action and the resulting
     state, not only the last screen; side effects (rows, files, messages)
     next to what is visible; a mock only where production already has a
     boundary.
   - *Cleanup* — stops what the recipe started, by pid or by compose
     project, never by process name. It removes instances and scratch state
     and leaves the evidence.
6. **Seed the feature map.** `docs/review/features/README.md` as the index
   and one file per feature from [`templates/verify-feature.md`](../../templates/verify-feature.md).
   Start with the three to five features a user touches most, found from
   routes, navigators, commands or menus. Name a file for what the user
   calls the feature. If the project has `GLOSSARY.md`, use its terms.
   A precondition the seed data lacks goes under `Gotchas`; the journey is
   never weakened to make it pass.
7. **Prove it once.** Follow the files exactly as written: launch, doctor,
   drive one mapped feature, capture the evidence, clean up. Confirm the
   evidence is still there after cleanup. Fix what fails and run the cleanup
   after every failed attempt. A recipe nobody executed is a draft.
8. **`bash scripts/check.sh <root>`** until it ends with `ok`.
9. **Stamp what step 7 proved.**
   `bash ../delivery-pipeline/scripts/stamp.sh set docs/review/verify.md <the feature files driven>`
   writes the commit of HEAD below the title of each, as an `As of:` line.
   Do not stamp a file that nobody drove. `DIRTY` means that a path the file
   names has uncommitted changes: do not stamp, say so in the report.
10. **Report** in the format below and stop.

## Keeping it true

A map that has drifted from the app is worse than none: the verifier trusts
it. Run this when `check.sh` reports a problem, when a verifier line says
`recipe — STALE`, or when asked.

1. `bash scripts/check.sh <root>`. A `STALE` line is a path a feature file
   names that is gone: find where the feature went and correct the file.
   `bash ../delivery-pipeline/scripts/stamp.sh check`. A `DRIFT` line is a
   file whose code changed since the commit on its `As of:` line: the file
   can be wrong, and step 3 drives it. An `UNSTAMPED` line is a file that
   nobody proved.
2. Compare the index with the routes, navigators or commands of today. A
   feature the app has and the map does not gets a file; a feature the app
   dropped loses its file and its index line.
3. One live pass over the features whose files changed and the features
   with a `DRIFT` line: drive, capture, clean up. Correct only what the pass
   proved wrong. Then `stamp.sh set` on each file that the pass drove.
4. Report.

## Output format

```
Verify recipe — <root>
Surface:  <what the recipe drives> · also: <the other surfaces, not covered>
Launch:   <the command> — <how ready is told>
Proved:   <the feature driven> — <the evidence path>
Features: <n> mapped — <their names>
Not mapped: <features found and left for later, or "nothing">
Asked:    <each thing the human must supply: a test account, an env value>
Check:    <the last line of check.sh>
Stamps:   <the last line of stamp.sh check>

Read it: git diff
```

A line with nothing to list is left out.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/verify-recipe/scripts/`.
