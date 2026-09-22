# React Review Checklist

Eight categories. Walk them in order. Each rule is tagged **[hard]**,
**[prefer]** or **[context]** — see SKILL.md. For each finding, name the
consequence: "this is wrong" without "because X breaks" is not a finding.

## 1. Over-engineering & scope

The most common defect in AI-generated code. The bias is toward too much.

- **[hard] Speculative generality** — props, branches, or config that no caller
  uses. A `variant` prop with one variant. A callback that is always the same.
- **[prefer] Premature abstraction** — a generic component built for one caller.
  Generalize on the second use, not the first.
- **[prefer] Wrapper with no value** — a component that only forwards props to
  one child. Inline it.
- **[hard] Reinvention** — re-implements something the shared layers already do.
  **Run `scripts/inventory.sh` before judging this.** Name the replacement by
  its real export, not a guess.
- **[context] Size** — could this be 25 lines instead of 90? Ask what the file
  would lose if cut in half. If nothing essential, cut it.
- **[hard] Dead code** — unused imports, exports, props, state, branches.

## 2. React correctness & smells

Check the version baseline in SKILL.md first — React 19 and the React Compiler
each flip rules in this section.

### Effects — the top smell

`useEffect` is for syncing with systems outside React. Everything else has a
better tool. The named anti-patterns and their replacements:

| Anti-pattern | Replacement | Tag |
| --- | --- | --- |
| State derived from props/state | compute during render | [hard] |
| Effect caching an expensive calc | `useMemo` | [prefer] |
| Effect resetting all state when a prop changes | `key` prop on the component | [prefer] |
| Effect adjusting *some* state when a prop changes | `setState` during render, guarded | [context] |
| Effect sharing logic between handlers | plain function called by both | [prefer] |
| Chain of effects each triggering the next | compute it all in the event handler | [hard] |
| Effect doing app init | module-level guard, or do it at the root | [context] |
| Effect notifying the parent of a state change | call the parent callback in the same handler | [prefer] |
| Effect subscribing to an external store | `useSyncExternalStore` | [context] |
| Effect fetching data | fine — but it needs abort/ignore cleanup | [hard] |

Rule of thumb: code that runs *because the component was displayed* belongs in
an effect. Everything else belongs in an event.

- **[hard] Dependency arrays** — missing deps (stale closure) or padded deps
  (extra runs). Only report when `exhaustive-deps` is not active.
- **[hard] State that should be derived** — `useState` + `useEffect` mirroring a
  prop. Genuine resync from an external `value` change is the rare valid case,
  and it deserves a why-comment.
- **[hard] Missing effect cleanup** — subscription, timer, listener, or fetch
  with no teardown. On React 19 a ref callback can return a cleanup; use it
  instead of a paired mount/unmount effect.

### Memoization (no React Compiler)

- **[prefer] Over-memoization** — `useMemo`/`useCallback` whose result feeds no
  memoized child and is cheap to recompute. Costs more than it saves.
- **[prefer] Under-memoization** — inline object/array/function passed to a
  memoized child or a list `renderItem`: new ref every render defeats the memo.
  React Native is more sensitive to this than web — derived list data and
  `renderItem` handlers are the cases that actually pay.

With the React Compiler on, both rules invert: manual memoization is noise and
the finding is the *presence* of hand-written `useMemo`/`useCallback` that the
compiler already does.

### The rest

- **[hard] List keys** — stable unique `key`/`keyExtractor`; never the array
  index for reorderable data.
- **[hard] Hooks rules** — no hooks in conditionals, loops, or after an early
  return. Always 🔴.
- **[hard] `forwardRef` on React 19** — obsolete. A function component takes
  `ref` as an ordinary prop. A new `forwardRef` in a React 19 codebase is a
  regression.
- **[context] Component doing too much** — fetch + transform + layout + 6
  `useState` in one body → extract a hook or split the component.
- **[prefer] Prop drilling** — a prop threaded through 3+ layers untouched →
  context or composition.

## 3. Comment quality

- **[hard] Delete "what" comments** — `// set loading to true`, `// map over
  items`, anything restating the code or the function name.
- **[hard] Delete commented-out code** — git remembers it.
- **[prefer] Keep / expect "why" comments** — rationale, non-obvious
  constraints, gotchas. A non-trivial decision with NO why-comment is itself a
  finding. The project layer names the files that set the bar.
- **[context] Mandated TODOs** — a project may require a specific TODO shape
  (for example a label-localisation marker). Check the project layer before
  flagging a TODO as a smell; the finding may be the TODO that is *missing*.
- **[hard] No issue/PR/SHA/date refs in code comments** — those live in commit
  messages and PR bodies. Comments explain code-scope why only.

## 4. Styling & design tokens

Read the project's design doc first. The styling system (utility classes, a
theme hook, StyleSheet, CSS modules, styled-components) is whatever the
siblings use — the rule is consistency with it, not a preference.

- **[hard] Raw color literals** — `#0F766E`, `rgb(...)`, `'white'` where the
  project has a token or theme value for it.
- **[hard] Arbitrary values** — `p-[7px]`, `text-[#1C1917]`, `marginTop: 13`
  outside the project's spacing / type scale.
- **[hard] Magic numbers** — literal spacing/radius/font sizes outside the
  documented scale.
- **[hard] The project's "do not" list** — most design docs carry an explicit
  list of forbidden patterns (gradient buttons, icon grids, a banned font).
  Those are findings by definition.
- **[hard] Mixed styling systems** — a `style={{}}` object in a codebase that
  styles with classes, or a class string in one that uses StyleSheet. One
  system per file, matching the siblings.
- **[context] Conditional styles** — declare both branches rather than only the
  "on" state. A class that only appears conditionally can leave the base style
  undefined instead of reset.
- **[context] Native-only style props** — a few React Native props
  (`columnWrapperStyle`, `contentContainerStyle` on some lists) accept only a
  style object. Using `style` there is correct, not a token violation.

## 5. Shared-code extraction

**Run `scripts/inventory.sh` first.** When something is reusable, name the
correct destination layer. The project layer names the real directories; the
generic shape is:

| Belongs in | When |
| --- | --- |
| generic UI primitives | Styled text, button, input, chip, checkbox, skeleton — no domain knowledge |
| app-level compositions | Rows, cards, form fields, screens, empty states reused across features |
| shared hooks | A hook used by 2+ features |
| shared lib / constants | A pure util or constant used by 2+ features |
| `features/<x>/…` | Reused within one feature only |
| a shared types / schemas package | A data type or validation schema also used by the backend |

- **[prefer] Duplicated block** — same JSX/logic as another file → extract to the
  layer above.
- **[hard] Redefined type** — a type that already exists in the shared types
  package.
- **[hard] Local validation** — hand-rolled checks duplicating a shared schema.
- **[hard] Do not extract on first use.** Single-file use stays local.

## 6. TypeScript

- **[prefer] `any` / `as any`** — type it, or `unknown` + a guard.
- **[prefer] Non-null `!`** — hides a real nullable; handle the null.
- **[hard] Props typing** — a named `type <Component>Props` (or whatever the
  siblings do), not an inline object literal.
- **[prefer] Loose unions** — model exclusive states as a discriminated union,
  not independent booleans (`isLoading` + `isError` + `data` all true at once).
- **[hard] Unsafe casts** — a cast across unrelated shapes is a hidden bug.

## 7. Platform: React Native & mobile

Skip this section for a web-only component; the a11y rules move to
`aria-*` / semantic elements there.

- **[hard] Accessibility** — interactive elements need `accessibilityRole`,
  `accessibilityLabel`, and `accessibilityHint` where non-obvious; a `testID`
  when the project drives UI tests. Add `accessibilityState` for
  selected/disabled/checked controls. A `Pressable` marked `accessible` must
  carry the full spoken label — children are not individually focusable.
- **[hard] Label quality** — the label is a noun phrase naming the control, not
  the visible text dumped verbatim and not "button" (the role already says that).
- **[hard] Tap target** — interactive rows/buttons meet the 44pt minimum.
- **[hard] States** — loading, empty and error handled, not just the happy path.
- **[hard] Lists** — long/unbounded lists use a virtualized list, not `.map()`
  in a `ScrollView`. Always 🔴 when the data is unbounded.
- **[context] Safe area / insets** — padding per screen, not on the root, and a
  scrolling screen under a floating bar owes it bottom clearance.
- **[hard] No single-platform code paths** unless the project ships to one
  platform only. `Platform.OS === 'ios'` with no Android branch is a finding
  on a two-platform app.

## 8. Codebase consistency

AI code type-checks and still drifts from house style. Compare to the sibling.

- **[hard] Imports** — use the project's path aliases, never deep relative
  paths (`../../..`).
- **[prefer] Naming & ordering** — handler names (`handleX`), prop order, export
  style match siblings.
- **[prefer] Patterns** — same data-fetching hook, same form primitives, same
  navigation typing as neighboring files.
- **[hard] No milestone names** — nothing named after a wave, sprint, quarter or
  ticket. Names describe behaviour.
- **[prefer] One job per file** — a component file exports its component (and its
  props type), not a grab-bag of unrelated helpers.

---

## Sources

- [You Might Not Need an Effect — react.dev](https://react.dev/learn/you-might-not-need-an-effect) — §2 effects table
- [React v19 — react.dev](https://react.dev/blog/2024/12/05/react-19) and [forwardRef — react.dev](https://react.dev/reference/react/forwardRef) — ref-as-prop, ref cleanup functions
- [React Compiler — react.dev](https://react.dev/learn/react-compiler) — when manual memoization stops mattering
- [Accessibility — reactnative.dev](https://reactnative.dev/docs/accessibility) — roles, labels, states
