---
name: angular-review
description: Use when asked to review a single Angular component, directive or pipe file (*.component.ts and its template), check whether an Angular component is okay, or sanity-check AI-generated Angular code one file at a time. For a whole diff or PR, go through review-routing instead.
---

# Angular Review

Structured review of ONE Angular unit — a component (with its template and
stylesheet), a directive, or a pipe. Report + suggest — never edits the file.
Built for sanity-checking AI-generated Angular code one unit at a time.

Angular carries two generations of API side by side — decorators, modules and
RxJS on one side; signals, standalone and built-in control flow on the other.
Most AI-generated code mixes them. This review's first job is to say which
generation the *project* is on and hold the file to that.

## Workflow

1. **Identify the target.** One `*.component.ts` (plus its `templateUrl` /
   `styleUrl` files), `*.directive.ts` or `*.pipe.ts`. If none was given, ask.
2. **Load the project layer** (do not skip):
   - `docs/review/angular-review.md` if the repository has one — reference
     components, the shared libs, the styling system, known ceilings, and
     which API generation the project has standardised on. If it is absent,
     derive the same from `CLAUDE.md` / `AGENTS.md`, `angular.json` and the
     siblings, and say in one line that you did.
   - The unit under review, **including its template and stylesheet**. A
     component is three files; reviewing the `.ts` alone misses half the bugs.
   - One sibling of the same kind — the consistency baseline.
3. **Run `scripts/inventory.sh [src-root]`** — the LIVE list of shared
   components, directives, pipes and services with their selectors. Read it
   before claiming anything must be built. [INVENTORY.md](INVENTORY.md)
   explains how to read it.
4. **Run `scripts/scan.sh <file.ts>`** — mechanical pre-scan. It follows
   `templateUrl` and `styleUrl` on its own. Heuristic, not a gate.
5. **Walk [CHECKLIST.md](CHECKLIST.md)** — all 8 categories, in order.
6. **Emit the report** (format below). Do not edit the file.

Scripts live next to this file. Installed as a plugin, that is
`${CLAUDE_PLUGIN_ROOT}/skills/angular-review/scripts/`.

## Effort scaling

Default is **medium**. The user may say low / medium / high.

- **low / medium** — only findings you would defend out loud in review: 🔴 and 🟡.
  Roughly 7 findings max. **Zero findings is a valid, expected outcome** — say so
  plainly and stop.
- **high** — add ⚪ nits and lower-confidence observations, still ranked.

## Rule confidence

- **[hard]** — never correct. Always report.
- **[prefer]** — the right default. Report unless the file gives a reason not to.
- **[context]** — depends. Report only when you can name the concrete
  consequence *in this file*.

## Severity floor

Always 🔴, regardless of effort:

- a manual `.subscribe()` with no teardown (`takeUntilDestroyed`, `DestroyRef`,
  or the `async` pipe instead) on a stream that outlives the component
- an `effect()` that writes application state to propagate a change — the
  documented path to circular updates
- a clickable `<div>` / `<span>` standing in for a `<button>` with no role,
  keyboard handler and focusability

## Do NOT report

- Anything the Angular compiler or angular-eslint already **errors** on in this
  project (see coverage below). `@for` without `track` is a compile error —
  never a finding.
- Restating the project's instructions file as if it were a finding.
- A migration the project has not chosen. On a codebase still on `*ngIf` and
  `@Input()` throughout, one more of each is consistency, not a defect — the
  finding is a *new file* mixing both generations. Say once, at the top, which
  generation the project is on.
- Test recommendations the project has decided against; check the project
  layer first.
- Style-only rewrites of untouched sibling/legacy code.

## Tooling coverage

Do not assume what lint catches. Run once per review:

```bash
npx eslint --print-config <file> | grep -E '"@angular-eslint/(prefer-signals|prefer-standalone|prefer-inject|prefer-on-push-component-change-detection|template/prefer-control-flow|template/use-track-by-function|template/click-events-have-key-events|template/interactive-supports-focus|no-async-lifecycle-method)|rxjs-angular|no-console'
```

Rules that resolve to `"error"` are the build's job — skip them. `"warn"` does
not fail the build — still report. Absent rules are this skill's job.
`scripts/scan.sh` targets the commonly absent set. The compiler itself owns:
`@for` track, unused standalone imports (v19+ diagnostic), template type
errors under `strictTemplates`.

## Output format

Findings ranked most-severe first. Every finding names the WHY.

```
### <ComponentName> review

Project generation: <signals + standalone + control flow | decorators + modules | mixed — see §2>

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

`<file:line>` names the template or stylesheet when the finding lives there.
If a checklist category is clean, say so in one line.

## Version baseline

Read the installed version before applying §2 of the checklist:

```bash
node -e 'const p=require("./package.json");for(const k of ["@angular/core","@angular/cli","typescript","rxjs"])console.log(k,(p.dependencies||{})[k]||(p.devDependencies||{})[k]||"-")'
```

The switches that change the rules:

| Angular | What becomes available — and what becomes a finding to omit |
| --- | --- |
| 14 | standalone components (preview), `inject()` |
| 16 | signals (preview), `takeUntilDestroyed`, `DestroyRef` |
| 17 | built-in control flow `@if` / `@for` / `@switch`, `@defer`, signals stable |
| 17.1 – 17.2 | signal inputs `input()`, `model()`, `output()`, signal queries |
| 19 | standalone is the default (`standalone: true` is redundant, `standalone: false` is the opt-out), `linkedSignal`, `resource` |
| 20 | new style guide: no `Component`/`Service` class suffix, no `.component` file suffix, for **new** projects |
| 21 | zoneless change detection stable |

Below the row a rule needs, the rule does not apply. Above it, the project's
own generation choice (project layer) decides whether omitting it is a finding.
