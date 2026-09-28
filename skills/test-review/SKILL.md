---
name: test-review
description: Use when asked to review a single test file (*.spec.ts, *.test.ts, *.test.tsx, __tests__/*), check whether a test is worth keeping, or sanity-check AI-generated tests one file at a time. For a whole diff or PR, go through review-routing instead.
---

# Test Review

Structured review of ONE test file and the unit it tests. Report and suggest
— never edit the file.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the seven categories, and what not to report. A
diff review reaches it through `review-routing` and never loads this file.

The one question every rule serves: **would this test fail if the code it
covers were wrong?** A test that cannot fail is cost with no return.

## Workflow

1. **Target.** One test file. None given — ask which. Resolve the unit under
   test from its imports; read that too.
2. **Project layer.** `docs/review/test-review.md` if the repository has one:
   the test stack, factories, custom render, fixture strategy, what the
   project has decided not to test. If it is absent, derive the same from
   `CLAUDE.md` / `AGENTS.md` and say so in one line. Then one sibling test in
   the same directory as the consistency baseline.
3. **`scripts/inventory.sh [root]`** — the live test-helper inventory.
   [INVENTORY.md](INVENTORY.md) says how to read it.
4. **`scripts/scan.sh <file>`** — mechanical pre-scan. Flags, not a verdict.
5. **Revert-check result**, when one was handed to you: every test it lists
   still passed with the change reversed, and each is a 🔴 finding before
   you read a line. `scripts/revert-check.sh` reverses working-tree hunks,
   so the controller or the human runs it, never the reviewer; with no
   result, say in one line that it was not run.
6. **Walk CHECKLIST.md** top to bottom.
7. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/test-review/scripts/`.

## Effort

Default **medium**: 🔴 and 🟡 only, and **zero findings is a valid outcome**
— say so and stop. **high** adds ⚪ nits, still ranked. A short report of
real defects beats an exhaustive one.

## Output format

```
### <file> review

🔴 <file:line> — <one-sentence defect>
   why: <what this test lets through>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. Every finding names what wrong code would pass. A clean
category gets one line.
