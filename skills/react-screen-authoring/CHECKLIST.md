# React Screen Authoring Checklist

A screen is three things: a **container** that owns navigation, server state
and screen-local state; a **view** that renders props; and **builders** that
turn data into what the view shows. React does not force them apart the way
a framework with classes, templates and services does, and a generator
working one session at a time will not either. The split is written down
here, enforced by lint, and reviewed by `react-review`.

Each rule is tagged **[hard]** (never violated), **[prefer]** (the default;
deviate with a stated reason) or **[context]** (depends on the situation).

## 1. Roles

| Role | Lives in | May use | May not |
| --- | --- | --- | --- |
| **Container** (`*Screen.tsx`, `*Page.tsx`) | `features/<f>/screens/` | navigation (typed param lists), query hooks, behaviour hooks, `useState` / `useReducer` for screen-local UI and form state, `useMemo` around builders | `useEffect`, service clients, inline helper components, derivations beyond calling a builder |
| **View** (`*View.tsx`, rows, sheets, forms, pickers) | `features/<f>/components/` | props in, semantic callbacks out; theme, translation, locale and settings read hooks; `useState` for interaction state the parent must not know | `useEffect`, service clients, query hooks, any fetching hook. A view never fetches: pickers and forms receive `options` / `status` / `retry` as props |
| **Primitive** | `components/ui/`, `components/app/` | everything a view may, plus `useEffect` / `useRef` for animation lifecycle, timers with cleanup, native-resource sync | domain data, domain types, query hooks, service clients, anything under `features/` |
| **Builder / reducer** (`build<Section>.ts`, `<x>FormState.ts`) | `features/<f>/lib/`, `src/lib/` | pure functions over data snapshots plus explicit presentation inputs (`t`, `locale`, domain labels, clock values) | React, React Native, the i18n singleton, `Date.now()`, query objects, navigation, setters, components. Every one has a spec beside it |
| **Behaviour hook** (`use<Behaviour>.ts`) | `hooks/`, `features/<f>/hooks/` | `useEffect`, `useRef`, native APIs, navigation focus | fetching (that is the query layer), JSX. One behaviour per hook |
| **Query hook** | `queries/`, `features/<f>/hooks/` | the query library, service clients, types, pure helpers for orchestration | JSX, navigation |

- **[hard] Dependency direction is UI -> lib, never lib -> UI.** A type shared
  by a component and its logic lives beside the logic in `lib/`; the component
  imports it. A `lib/` file that imports from `components/` is the inversion.
- **[hard] A container has no effects.** Lifecycle goes in a behaviour hook;
  derived data goes in a builder; a fetch goes in a query hook.
- **[hard] A view never fetches**, directly or through a hook that does. The
  container calls the query and passes the result down. Shared read hooks
  (theme, translation, locale, settings) are fine; a shared hook that runs a
  query or exposes a client is not.
- **[prefer] Line caps, code lines only:** container 150, view and primitive
  250, hook 100. A cohesive form, sheet or lifecycle hook that must exceed
  its cap takes the file-level exception with its why.

## 2. Contracts

- **[hard] Exclusive states are a discriminated union.** A builder or query
  adapter returns `{ status: 'loading' | 'error' | 'ready', ... }` and the
  view switches on it once. No `isLoading` + `isError` + `data` triples, no
  three early returns for one concept.
- **[prefer] Builders are per decision or per rendered section**, not one god
  function per screen. A screen-level `build<X>View` that composes them is
  optional. Trivial prop selection stays inline.
- **[hard] Builders take their inputs explicitly.** `t`, `locale`, domain
  labels and clock values (`todayYmd`, `nowHm`) are arguments, not imports.
  That is what makes a builder testable in Node without a renderer.
- **[hard] Builder specs run against the real locale bundle** through a test
  helper that throws on a missing key. A JSX-only literal-string lint does not
  see a `.ts` builder; the spec is its copy coverage.
- **[prefer] Extract on the second use.** A scroll-driven condensed header
  used by two screens becomes a shared behaviour hook; a focus-driven clock
  refresh likewise. Nothing is extracted to hide a single effect.
- **[hard] Forms.** Independent simple fields use the project's single-field
  hook. Coupled forms (one field clears another; hydration must not overwrite
  a dirty draft) get a pure reducer in `lib/` wired by `useReducer` in the
  container or a thin form hook; controlled fields render from reducer state.
  A field is never in both. The spec covers hydration before and after the
  first edit, dependent-field clearing, validation, reset, dirty comparison
  and the payload. No form library unless the project already has one.
- **[hard] Sheets.** Draft initialization and reset are separate from
  visibility. Reopening, or switching the edited entity, starts a fresh
  draft; a background refetch never overwrites a dirty draft. Dirty-dismiss
  confirmation, a dismissal lock while a write is pending, local failure
  display and the exit animation (the sheet primitive stays mounted through
  it) are preserved.
- **[hard] Copy.** Every rendered string comes from the project's locale
  bundle. A builder receives `t`; it never imports the i18n singleton.
- **[prefer] Comments** document lifecycle invariants, races and native
  constraints, never what the code does. A comment explaining why a *fetch*
  workaround exists is a signal the primitive is wrong.
- **[context] Exceptions** are a file-level `eslint-disable` with a one-line
  why. They are counted, not forbidden; the count is reported when the
  migration that introduced the lint closes.

## 3. The file set a new screen creates

In this order:

1. The param-list entry in the navigation types, so the route and its params
   exist before anything navigates to it.
2. `features/<f>/lib/build<Section>.ts` + `lib/__tests__/build<Section>.spec.ts`.
   One builder per decision or section. Plain functions, typed inputs
   including `t`, no React import.
3. Optional `features/<f>/lib/<x>FormState.ts` + spec, only for a coupled
   form.
4. `features/<f>/components/<X>View.tsx`.
5. `features/<f>/screens/<X>Screen.tsx`.
6. The E2E flow in the project's flow runner.

Relative imports inside anything a spec touches, when the project's jest
setup does not resolve the path alias (the project layer says).

## 4. Platform checklist (React Native; skip for web)

Get these right while writing the view and container. The review rubric
checks for them, but a miss caught here is free and a miss caught in review
costs a round trip.

- **[hard]** `accessibilityRole` and `accessibilityLabel` on every interactive
  element. The label is a noun phrase naming the control, not the visible text
  restated and not "button". `accessibilityState` for selected / disabled /
  checked.
- **[hard]** 44pt touch targets, through the project's token class, never a raw
  pixel value.
- **[hard]** A test id on every interactive element and every list row, in the
  project's dotted convention. The flow runner selects on these; a renamed or
  missing id breaks a flow silently.
- **[hard]** Unbounded or growing lists use a virtualized list, never `.map()`
  inside a scroll container.
- **[hard]** Loading, empty and error states through the existing primitives,
  not just the happy path.
- **[context]** A scrolling screen under a floating bar clears it with the
  project's clearance hook, or the last row is untappable.
- **[hard]** Both platforms. Never a single-platform code path on a
  two-platform app.
- **[hard]** Styling through the project's token classes only; the theme hook
  only for props that reach the native bridge (icon colour, ripple, animated
  values).

## 5. Lint that enforces the split

ESLint flat config, composed with whatever the project already has. Land the
rules at `warn` with a reported count while existing screens are brought to
shape, then flip to `error`.

| Files | Rules |
| --- | --- |
| `src/features/**/*Screen.tsx` | `max-lines` 150 (`skipBlankLines`, `skipComments`); `useEffect` / `useLayoutEffect` banned; `no-restricted-imports` on service clients |
| `src/features/**/components/**` | `max-lines` 250; the same effect ban; `no-restricted-imports` on service clients, query hooks, feature hooks, and the fetching exports of the shared hooks barrel (`importNames`) |
| `src/components/{ui,app}/**` | `max-lines` 250; `no-restricted-imports` on service clients, query hooks, anything under `features/` |
| `src/features/**/lib/**`, `src/lib/**` | `no-restricted-imports` on `react`, `react-native`, the i18n singleton, query hooks, any `components/` |
| `src/hooks/**`, `src/features/**/hooks/**` | `max-lines` 100 |
| everywhere | `react-hooks/exhaustive-deps` at `error` |
| `**/__tests__/**`, `*.spec.*` | `max-lines` off |

Two traps, both verified:

- **The effect ban is not `no-restricted-syntax`.** That rule carries one
  severity for its whole selector array, so a `files` override that adds
  effect selectors at `warn` would silently downgrade every existing selector
  in the same block (token guards, glyph guards). Use `no-restricted-imports`
  with `{ name: 'react', importNames: ['useEffect', 'useLayoutEffect'] }`
  for the named and namespace forms, plus `no-restricted-properties` with
  `{ property: 'useEffect' }` and `{ property: 'useLayoutEffect' }` (no
  `object`, so a renamed default import is caught too) for the member form.
  Only a destructured `require('react')` escapes, and nothing in an ESM tree
  writes that.
- **Relative-path globs lie.** In `no-restricted-imports` patterns, `*`
  matches `..`, so `../../*/hooks/*` matches `../../../hooks/x` (the shared
  hooks folder) and misses a deeper nested component. Use a `regex` entry
  that bans any relative reach to a `hooks` segment from a view, and require
  shared hooks to come through the path alias, which the import rule in
  `react-review` already demands. Likewise, `**/i18n` matches a scoped
  package whose name ends in `i18n`; spell the singleton's alias and relative
  forms out instead.

Probe every restriction against named, aliased, default, namespace, barrel
and relative imports with a throwaway file before trusting it, then delete
the file.

## Do NOT

- Do not fetch in a view to "keep the container small". Pass the data down.
- Do not put an effect in a screen to avoid writing a hook. The hook is the
  shape.
- Do not name a builder, hook or component after a sprint, wave, ticket or
  date. Names describe behaviour.
- Do not reach for a form library, a state library or a new dependency the
  project does not already have.
- Do not write a component test for a screen when the project tests screens
  through an E2E flow runner; write the builder spec and the flow.
