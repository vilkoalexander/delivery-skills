---
name: htmx-review
description: Use when asked to review a single htmx template or fragment (.html, .gohtml, .tmpl or .templ with hx- attributes) served by a Go backend, check whether an htmx page or partial is okay, check a template before or after an htmx 2 to htmx 4 upgrade, or sanity-check AI-generated htmx markup one file at a time. For a whole diff or PR, go through review-routing instead. For the Go handler that serves the fragment, use go-service-review.
---

# htmx Review

Structured review of ONE template: a page, a layout or a fragment with
`hx-` attributes. Report and suggest — never edit the file.

No compiler reads an `hx-` attribute. A misspelled one, one from another
htmx major, a target that matches nothing and a template value evaluated as
JavaScript all render without an error and fail in the browser. htmx 2 and
htmx 4 are both current and disagree on defaults, attribute names and event
names; generated markup mixes them, and mixes in htmx 1. The first job is to
say which major the *project* loads and hold the file to that.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the nine categories, and what not to report. A
diff review reaches it through `review-routing` and never loads this file.

## Workflow

1. **Target.** One template file. None given — ask which.
2. **Project layer.** `docs/review/htmx-review.md` if the repository has
   one: the htmx major, extensions, the Content-Security-Policy, the CSRF
   mechanism, reference templates, shared partials, ceilings. If it is
   absent, derive the same from `CLAUDE.md` / `AGENTS.md`, the layout
   template and the siblings, and say so in one line. A scan flag that only
   the layer can settle is reported as one question, not as a finding. Then
   the template
   under review, **the handler behind each URL it requests** — the template
   alone is half the contract — and one sibling as the consistency baseline.
3. **`bash scripts/inventory.sh [root]`** — how htmx is loaded, extensions,
   which major's syntax the templates use, partials, targets that match no
   id, the server side. [INVENTORY.md](INVENTORY.md) says how to read it.
4. **`bash scripts/scan.sh <template>`** — mechanical pre-scan; its first
   line is the htmx major it found. Flags, not a verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/htmx-review/scripts/`. `scan.sh` reads
`HTMX_VERSION` (`2` or `4`) from the environment when the repository does not
say; the project layer says what to set.

## Effort

Default **medium**: 🔴 and 🟡 only, and **zero findings is a valid outcome**
— say so and stop. **high** adds ⚪ nits, still ranked. A short report of
real defects beats an exhaustive one.

## Output format

```
### <file> review

htmx <2 | 4> (<where the version was read>) — templates: <html/template | templ>

🔴 <file:line> — <one-sentence defect>
   why: <what the user or an attacker sees, in this file>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. One finding per defect. `<file:line>` names the handler
when the finding lives there. Every finding names the why. A clean category
gets one line.
