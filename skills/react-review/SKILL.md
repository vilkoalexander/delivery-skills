---
name: react-review
description: Use when asked to review a single React or React Native component file (.tsx), check whether a component is okay, or sanity-check AI-generated React code one file at a time. For a whole diff or PR, go through review-routing instead.
---

# React Review

Structured review of ONE React or React Native component file. Report and
suggest — never edit the file.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the eight categories, and what not to report. A
diff review reaches it through `review-routing` and never loads this file.

## Workflow

1. **Target.** One `.tsx` component file. None given — ask which.
2. **Project layer.** `docs/review/react-review.md` if the repository has one:
   reference components, shared layers, styling system, known ceilings. If it
   is absent, derive the same from `CLAUDE.md` / `AGENTS.md` and say so in one
   line. Then the file under review, plus one sibling in the same directory as
   the consistency baseline.
3. **`scripts/inventory.sh [src-dir]`** — the live shared-code inventory.
   [INVENTORY.md](INVENTORY.md) says how to read it.
4. **`scripts/scan.sh <file>`** — mechanical pre-scan. Flags, not a verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/react-review/scripts/`.

## Effort

Default **medium**: 🔴 and 🟡 only, roughly seven findings at most, and
**zero findings is a valid outcome** — say so and stop. **high** adds ⚪ nits,
still ranked. A short report of real defects beats an exhaustive one.

## Output format

```
### <ComponentName> review

🔴 <file:line> — <one-sentence defect>
   why: <what breaks, in this file>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. Every finding names the why. Before/after is the two lines
that change. A clean category gets one line.
