---
name: go-service-review
description: Use when asked to review a single Go backend file (an HTTP handler, a service, a store or repository, middleware, main.go and server set-up, a worker, or their _test.go), check whether a Go handler or service is okay, or sanity-check AI-generated Go code one file at a time. For a whole diff or PR, go through review-routing instead. For an HTML template or a .templ file with hx- attributes, use htmx-review.
---

# Go Service Review

Structured review of ONE Go backend file. Report and suggest — never edit the
file.

Go compiles almost anything that type-checks, and `go vet` is narrow. So the
handler that keeps running after it wrote the error, the goroutine nobody
stops, the server with no timeouts and the query built from a string reach
production unchallenged. Generated Go is also written in the style of its
training corpus: idioms from before Go 1.21, libraries the standard library
has replaced. That is what this review is for.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the nine categories, and what not to report.
[INVARIANTS.md](INVARIANTS.md) is the generic non-negotiables. A diff review
reaches both through `review-routing` and never loads this file.

## Workflow

1. **Target.** One handler, service, store, middleware, `main.go`, worker or
   test file. None given — ask which. A file that starts with
   `// Code generated … DO NOT EDIT.` is not a target: review its source.
2. **Project layer.** INVARIANTS.md, then `docs/review/go-service-review.md`
   if the repository has one: where authorization happens, shared primitives,
   reference implementations, ceilings, deferred features. If it is absent,
   derive the same from `CLAUDE.md` / `AGENTS.md` and say so in one line. With
   none of them, the siblings are the baseline, and a scan flag that only the
   layer can settle is reported as one question, not as a finding. Then
   the file under review, **its test** if one exists, the file that registers
   its routes when it is a handler, and one sibling of the same kind as the
   consistency baseline.
3. **`bash scripts/inventory.sh [root]`** — the `go` line, libraries,
   analyzers, packages, shared primitives, middleware, remote clients, test
   helpers.
4. **`bash scripts/scan.sh <file>`** — mechanical pre-scan. Flags, not a verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/go-service-review/scripts/`. `scan.sh` reads
`HANDLER` (what marks a handler signature, for a router that is not
`net/http`, gin, echo or fiber) and `REMOTE_CALL` (calls that leave the
process) from the environment; the project layer says what to set. With no
project layer, set `REMOTE_CALL` from the inventory's remote clients before
the scan: its default knows only common names.

## Effort

Default **medium**: 🔴 and 🟡 only, and **zero findings is a valid outcome**
— say so and stop. **high** adds ⚪ nits, still ranked. A short report of
real defects beats an exhaustive one.

## Output format

```
### <file> review

Go <version from go.mod> — <router, data access, templates as the project uses them>

🔴 <file:line> — <one-sentence defect>
   why: <what breaks, concretely>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. One finding per defect: a line that is wrong for three
reasons is one finding with the worst reason first. Every finding names the
why. Before/after is the two lines that change. A clean category gets one
line.
