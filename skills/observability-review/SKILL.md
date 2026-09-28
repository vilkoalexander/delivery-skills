---
name: observability-review
description: Use when asked whether a backend change logs enough, whether it can be debugged in production, whether logging follows the project's logger and correlation setup, or to review observability (logs, metrics, traces, error reporting) of one backend file. For a whole diff or PR, go through review-routing instead.
---

# Observability Review

Structured review of ONE backend file for what it will tell you at three in
the morning. Report and suggest — never edit the file.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the six categories, and what not to report. A
diff review reaches it through `review-routing` and never loads this file.

The one question every rule serves: **when this path fails in production,
does one log line say what failed, for whom, and with which request?**

## Workflow

1. **Target.** One backend file — service, controller, gateway, processor,
   resolver, middleware, job. None given — ask which.
2. **Project layer.** `docs/review/observability-review.md` if the
   repository has one: the logger and how it is injected, the correlation
   mechanism, the redaction list, the error filter, the tracing setup, the
   events the project has decided must be logged. If it is absent, derive
   the same from `CLAUDE.md` / `AGENTS.md` and say so in one line. Then one
   sibling file in the same directory as the consistency baseline.
3. **`scripts/inventory.sh [root]`** — what observability plumbing exists.
   [INVARIANTS.md](INVARIANTS.md) says what the project layer must supply
   and which rules are one-way doors.
4. **`scripts/scan.sh <file>`** — mechanical pre-scan. Flags, not a verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/observability-review/scripts/`.

## Effort

Default **medium**: 🔴 and 🟡 only, and **zero findings is a valid outcome**
— say so and stop. **high** adds ⚪ nits, still ranked. A short report of
real defects beats an exhaustive one.

## Output format

```
### <file> review

🔴 <file:line> — <one-sentence defect>
   why: <what you cannot see or find in production because of it>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. Every finding names the production question it leaves
unanswerable. A clean category gets one line.
