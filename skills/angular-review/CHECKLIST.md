# Angular Review Checklist

Eight categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). For each finding, name the
consequence: "this is wrong" without "because X breaks" is not a finding.

## Before you start

### Version baseline

Read the installed version before applying §2 below:

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

### Tooling coverage

Do not assume what lint catches. Run once per review:

```bash
npx eslint --print-config <file> | grep -E '"@angular-eslint/(prefer-signals|prefer-standalone|prefer-inject|prefer-on-push-component-change-detection|template/prefer-control-flow|template/use-track-by-function|template/click-events-have-key-events|template/interactive-supports-focus|no-async-lifecycle-method)|rxjs-angular|no-console'
```

Rules that resolve to `"error"` are the build's job — skip them. `"warn"` does
not fail the build — still report. Absent rules are this skill's job.
`scripts/scan.sh` targets the commonly absent set. The compiler itself owns:
`@for` track, unused standalone imports (v19+ diagnostic), template type
errors under `strictTemplates`.

## Severity floor

Always 🔴, regardless of effort:

- a manual `.subscribe()` with no teardown (`takeUntilDestroyed`, `DestroyRef`,
  or the `async` pipe instead) on a stream that outlives the component
- an `effect()` that writes application state to propagate a change — the
  documented path to circular updates
- a clickable `<div>` / `<span>` standing in for a `<button>` with no role,
  keyboard handler and focusability

## 1. Over-engineering & scope

The most common defect in AI-generated code. The bias is toward too much.

- **[hard] Speculative generality** — inputs, outputs, branches, or config that
  no caller uses. A `variant` input with one variant. A service method with no
  caller.
- **[prefer] Premature abstraction** — a generic component built for one caller.
  Generalize on the second use, not the first.
- **[prefer] Wrapper with no value** — a component that only forwards inputs to
  one child. Inline it.
- **[hard] Reinvention** — re-implements something the shared libs already do.
  **Run `scripts/inventory.sh` before judging this.** Name the replacement by
  its real selector or class, not a guess.
- **[context] Size** — could this be 25 lines instead of 90?
- **[hard] Dead code** — unused imports, inputs, outputs, fields, template
  branches, `imports: [...]` entries no template uses (v19+ warns; older
  versions do not).

## 2. Angular correctness

Check the version baseline above, then the project's generation. The
rules below assume the signals generation is available; each says what to do
when it is not.

### Inputs, outputs, state

- **[prefer] `input()` / `input.required()` / `model()` / `output()`** over the
  `@Input()` / `@Output()` decorators on 17.1+, when the project has adopted
  them. A new file mixing both in one class is a **[hard]** finding regardless.
- **[hard] Derived state is `computed()`**, never an `effect()` that writes a
  signal, never `ngOnChanges` copying an input into a field. Both re-implement
  what `computed` does and both go stale.
- **[hard] `effect()` is the last resort.** Valid: syncing signal state to a
  non-signal API — logging, `localStorage`, a third-party widget, a DOM
  measurement. Invalid: propagating state to other signals, calling `emit`,
  triggering navigation on a state change that a handler already owns. Always
  🔴 when it writes application state.
- **[prefer] `linkedSignal` for "derived but user-overridable"** (a selection
  that resets when options change) on 19+, instead of a `computed` plus a
  manual reset effect.
- **[context] `toSignal` / `toObservable`** at the RxJS boundary, not a manual
  subscribe that sets a signal.

### Change detection

- **[prefer] `ChangeDetectionStrategy.OnPush`** on every component. **[hard]**
  when the siblings are OnPush — a Default-strategy child under OnPush parents
  is the one that does not update and nobody knows why.
- **[hard] No `detectChanges()` / `setTimeout(() => …, 0)` to force a render.**
  That is a symptom: state mutated outside Angular's knowledge. The fix is a
  signal, `markForCheck()` after an imperative mutation, or moving the mutation
  into a handler.
- **[context] Zoneless readiness** — direct mutation of a reactive form model
  or a plain field will not render under zoneless. Flag only when the project
  has `provideZonelessChangeDetection()` or says it is heading there.

### Dependency injection & lifecycle

- **[prefer] `inject()` over constructor parameters** on 14+, when the project
  has adopted it. Mixed in one class is **[hard]**.
- **[hard] `providedIn: 'root'` for singleton services**; a component-level
  `providers: []` only when a per-instance service is the point, with a
  why-comment.
- **[prefer] Constructor / field initialisers for wiring, `ngOnInit` for
  input-dependent work** — with signal inputs, most `ngOnInit` bodies become
  `computed` or disappear.
- **[hard] No `async ngOnInit`** — a rejected promise there is an unhandled
  rejection with no template feedback.

### RxJS

- **[hard] Every manual `.subscribe()` has a teardown**: `takeUntilDestroyed()`
  (16+), a `DestroyRef.onDestroy`, `take(1)` / `first()` for a genuine
  one-shot, or — better — no subscribe at all and the `async` pipe / `toSignal`.
  Always 🔴 on a stream that outlives the component.
- **[hard] No nested subscribes.** `switchMap` / `concatMap` / `exhaustMap`,
  chosen deliberately (cancel / queue / ignore) — name which one and why.
- **[prefer] `Subject` fields are private and exposed as `asObservable()`** or
  as a signal.
- **[context] `shareReplay` on an HTTP stream** used by several template
  bindings, or one `async` pipe with `@if (data$ | async; as data)`.

## 3. Template

The template is half the component. Load it.

- **[prefer] Built-in control flow** `@if` / `@for` / `@switch` over `*ngIf` /
  `*ngFor` / `*ngSwitch` on 17+, per the project's generation. Mixed in one
  template is **[hard]**.
- **[hard] `track` on a stable identity** — `track item.id`, not
  `track $index` on data that reorders, inserts or deletes, and never
  `track item` on objects that are recreated per emission (every row
  re-renders).
- **[prefer] Direct `[class.x]` / `[style.x]` bindings** over `[ngClass]` /
  `[ngStyle]`, per the current style guide.
- **[context] Method calls in bindings** — `{{ total() }}` on a signal is
  free; `{{ computeTotal() }}` on a method runs every check. Under OnPush with
  signals this is mostly fine; under Default it is the classic perf leak.
- **[prefer] `@defer` for heavy below-the-fold content** and `NgOptimizedImage`
  for images with known dimensions, on 17+.
- **[hard] No business logic in the template** — ternaries three deep, array
  filtering, date math. A `computed` or a pipe.
- **[hard] Reactive forms over template-driven** for anything beyond a single
  field, and **typed** (`FormGroup<{…}>` / `nonNullable`) on 14+.

## 4. Comment quality

- **[hard] Delete "what" comments** — `// inject the service`, `// loop over
  items`, anything restating the code.
- **[hard] Delete commented-out code** — git remembers it.
- **[prefer] Keep / expect "why" comments** — rationale, non-obvious
  constraints, gotchas. A non-trivial decision with NO why-comment is itself a
  finding. A component-level `providers: []`, an `effect()`, a
  `ViewEncapsulation.None`, a `runOutsideAngular` each need one.
- **[hard] No issue/PR/SHA/date refs in code comments** — those live in commit
  messages and PR bodies.

## 5. Styling & design tokens

Read the project's design doc first. The styling system (SCSS with design
tokens, Tailwind, Angular Material theming, CSS custom properties) is whatever
the siblings use — the rule is consistency with it.

- **[hard] Raw color literals** — `#0F766E`, `rgb(...)` where the project has a
  token or custom property for it.
- **[hard] Magic numbers** — literal spacing / radius / font sizes outside the
  documented scale.
- **[hard] `::ng-deep`** — it is deprecated, leaks past encapsulation, and
  breaks the next time the child's DOM changes. The fix is a CSS custom
  property the child exposes, or `ViewEncapsulation.None` on a deliberately
  global stylesheet with a why-comment.
- **[hard] `!important`** — a specificity fight that someone will lose later.
- **[context] `ViewEncapsulation.None`** — legitimate for a layout shell or a
  theme root; a finding on a leaf component.
- **[hard] The project's "do not" list** — a design doc's forbidden patterns
  are findings by definition.
- **[context] Inline `styles: [...]` vs `styleUrl`** — match the siblings.

## 6. Shared-code extraction

**Run `scripts/inventory.sh` first.** The project layer names the real libs;
the generic shape:

| Belongs in | When |
| --- | --- |
| a shared UI lib | Generic presentational component, directive, pipe — no domain knowledge |
| a shared util / data-access lib | A service, guard, interceptor, or pure function used by 2+ features |
| a feature lib | Reused within one feature only |
| a shared types / schemas package | A data type or validation schema also used by the backend |

- **[prefer] Duplicated block** — same template/logic as another file → extract
  to the layer above.
- **[hard] Redefined type** — a type that already exists in the shared types
  package.
- **[hard] Redefined pipe / directive** — a `formatDate`-style pipe when the
  shared lib already ships one. Name the real selector.
- **[hard] Do not extract on first use.** Single-file use stays local.

## 7. Accessibility & platform

Web platform; these have no automated coverage unless the
`@angular-eslint/template` a11y rules are on.

- **[hard] Interactive means focusable** — `(click)` on a `<div>` / `<span>`
  is a `<button>` or carries `role`, `tabindex="0"` and a keyboard handler.
  Always 🔴.
- **[hard] Every form control has a label** — `<label for>`, `aria-label` or
  `aria-labelledby`. Placeholder is not a label.
- **[hard] Images carry `alt`** (empty `alt=""` for decorative).
- **[prefer] Live regions for async status** — `aria-live="polite"` on a
  loading/error message that appears without focus moving.
- **[hard] States** — loading, empty and error handled, not just the happy path.
- **[context] Router-driven state** — a filter or tab that survives reload
  belongs in the URL, not in a service.

## 8. Codebase consistency

AI code compiles and still drifts from house style. Compare to the sibling.

- **[hard] Standalone on 19+** — a new `NgModule` declaring components, or
  `standalone: false`, in a standalone project. On 14–18 match the siblings.
- **[prefer] File & class naming match the siblings** — the 20+ style guide
  drops `.component` / `Component`; a project on the older convention keeps
  it. Either is fine; mixing is the finding.
- **[hard] Imports** — the project's path aliases (`@app/…`, `@shared/…`,
  `@org/lib`), never deep relative paths.
- **[prefer] Member order** — inputs/outputs, injected deps, signals/state,
  lifecycle, handlers, private helpers — whatever the siblings do.
- **[hard] No milestone names** — nothing named after a sprint, quarter or
  ticket. Names describe behaviour.
- **[prefer] One unit per file** — a component file exports its component; a
  helper used elsewhere gets its own file.

---

## Do NOT report

- Anything the Angular compiler or angular-eslint already **errors** on in this
  project (see Tooling coverage above). `@for` without `track` is a compile error —
  never a finding.
- Restating the project's instructions file as if it were a finding.
- A migration the project has not chosen. On a codebase still on `*ngIf` and
  `@Input()` throughout, one more of each is consistency, not a defect — the
  finding is a *new file* mixing both generations. Say once, at the top, which
  generation the project is on.
- Test recommendations the project has decided against; check the project
  layer first.
- Style-only rewrites of untouched sibling/legacy code.
