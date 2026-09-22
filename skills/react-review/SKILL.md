---
name: react-review
description: Use when asked to review a single React or React Native component file (.tsx), check whether a component is okay, or sanity-check AI-generated React code one file at a time. For a whole diff or PR, go through review-routing instead.
---

# React Review

Structured review of ONE React or React Native component file. Report +
suggest — never edits the file. Built for sanity-checking AI-generated
components one at a time.

## Workflow

1. **Identify the target.** One `.tsx` component file. If none was given, ask which.
2. **Load the project layer** (do not skip):
   - `docs/review/react-review.md` if the repository has one — reference
     components, the shared-code layers, the styling system, known ceilings.
     If it is absent, derive the same from `CLAUDE.md` / `AGENTS.md` and the
     project's design doc, and say in one line that you did.
   - The component file under review.
   - One sibling file in the same directory — the consistency baseline.
     AI-generated code often silently diverges from its siblings.
3. **Run `scripts/inventory.sh [src-dir]`** — prints the LIVE shared-code
   inventory. Read it before claiming anything is missing or must be built.
   Reinvention is the #1 miss and a stale mental inventory is why.
   [INVENTORY.md](INVENTORY.md) explains how to read it.
4. **Run `scripts/scan.sh <file>`** — mechanical pre-scan. Heuristic, not a gate.
5. **Walk [CHECKLIST.md](CHECKLIST.md)** — all 8 categories, in order.
6. **Emit the report** (format below). Do not edit the file.

Scripts live next to this file. Installed as a plugin, that is
`${CLAUDE_PLUGIN_ROOT}/skills/react-review/scripts/`.

## Effort scaling

Default is **medium**. The user may say low / medium / high.

- **low / medium** — only findings you would defend out loud in review: 🔴 and 🟡.
  Roughly 7 findings max. **Zero findings is a valid, expected outcome** — say so
  plainly and stop. Do not pad to look thorough.
- **high** — add ⚪ nits and lower-confidence observations, still ranked.

A short report of real defects beats an exhaustive one. Noise trains the reader
to skim, and then the 🔴 gets skimmed too.

## Rule confidence

Every checklist rule carries a tag. Respect it — do not flatten everything into
absolutes.

- **[hard]** — never correct. Always report.
- **[prefer]** — the right default. Report unless the file gives a reason not to.
- **[context]** — depends on the situation. Report only when you can name the
  concrete consequence *in this file*.

## Severity floor

Always 🔴, regardless of effort:

- a hook called conditionally, in a loop, or after an early return
- an effect with a subscription, timer, listener or fetch and no cleanup
- an unbounded list rendered with `.map()` inside a scroll container on React
  Native

## Do NOT report

- Anything ESLint already **errors** on in this project (see coverage below).
- Restating the project's instructions file as if it were a finding.
- Test recommendations the project has decided against. Check the project layer
  first — a mobile app that tests through an end-to-end flow runner only does not want RN unit
  tests suggested.
- Deep performance analysis (list virtualization internals, re-render
  profiling, Hermes) — name the concern once and point at the project's perf
  guidance, do not duplicate it.
- Style-only rewrites of untouched sibling/legacy code. Review the file in front
  of you; do not commission a migration.

## Tooling coverage

Do not assume what lint catches. Run once per review:

```bash
npx eslint --print-config <file> | grep -E '"(react-hooks/|react/jsx-key|no-console|@typescript-eslint/no-explicit-any)' 
```

Rules that resolve to `"error"` are the build's job — skip them. Rules that
resolve to `"warn"` do not fail the build and get scrolled past — still report
them. Rules that are **absent** (`rules-of-hooks`, `exhaustive-deps`,
`jsx-key`, `no-console`, any a11y plugin) have zero automated coverage and are
squarely this skill's job. `scripts/scan.sh` targets the absent set.

## Output format

Findings ranked most-severe first. Every finding names the WHY — a finding
without a consequence is noise.

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

Keep the before/after minimal — the two lines that change, not the file.
If a checklist category is clean, say so in one line; do not pad the report.

## Version baseline

Read the installed versions before applying §2 of the checklist:

```bash
node -e 'const p=require("./package.json");for(const k of ["react","react-native","expo","next","typescript"])console.log(k,(p.dependencies||{})[k]||(p.devDependencies||{})[k]||"-")'
```

Two switches change the rules:

- **React 19** — `forwardRef` is obsolete (`ref` is a prop); ref callbacks may
  return a cleanup. On React 18 those rules do not apply.
- **React Compiler** — look for `babel-plugin-react-compiler` or
  `experiments.reactCompiler`. When it is enabled, the over-/under-memoization
  rules in CHECKLIST §2 invert: manual `useMemo`/`useCallback` becomes noise,
  not diligence. When it is absent, manual memoization still matters.
