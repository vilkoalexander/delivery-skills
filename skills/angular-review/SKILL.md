---
name: angular-review
description: Use when asked to review a single Angular component, directive or pipe file (*.component.ts and its template), check whether an Angular component is okay, or sanity-check AI-generated Angular code one file at a time. For a whole diff or PR, go through review-routing instead.
---

# Angular Review

Structured review of ONE Angular unit — a component with its template and
stylesheet, a directive, or a pipe. Report and suggest — never edit the file.

Angular carries two API generations side by side — decorators, modules and
RxJS; signals, standalone and built-in control flow. AI-generated code mixes
them. The first job is to say which generation the *project* is on and hold
the file to that.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the eight categories, and what not to report. A
diff review reaches it through `review-routing` and never loads this file.

## Workflow

1. **Target.** One `*.component.ts` (plus its `templateUrl` / `styleUrl`
   files), `*.directive.ts` or `*.pipe.ts`. None given — ask which.
2. **Project layer.** `docs/review/angular-review.md` if the repository has
   one: reference components, shared libs, styling system, ceilings, and the
   API generation the project standardised on. If it is absent, derive the
   same from `CLAUDE.md` / `AGENTS.md`, `angular.json` and the siblings, and
   say so in one line. Then the unit under review **including template and
   stylesheet** — the `.ts` alone misses half the bugs — and one sibling of
   the same kind as the consistency baseline.
3. **`scripts/inventory.sh [src-root]`** — live shared components,
   directives, pipes and services with selectors, plus generation counts.
   [INVENTORY.md](INVENTORY.md) says how to read it.
4. **`scripts/scan.sh <file.ts>`** — mechanical pre-scan; follows
   `templateUrl` and `styleUrl` itself. Flags, not a verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/angular-review/scripts/`.

## Effort

Default **medium**: 🔴 and 🟡 only, roughly seven findings at most, and
**zero findings is a valid outcome** — say so and stop. **high** adds ⚪ nits,
still ranked.

## Output format

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

Most-severe first. `<file:line>` names the template or stylesheet when the
finding lives there. A clean category gets one line.
