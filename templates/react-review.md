# React review — project layer

Loaded by `react-review` at step 2. Keep every entry a real path or export.
Everything in `<angle brackets>` is a placeholder — replace it or delete the row.

## Reference components

| Concern | Read |
| --- | --- |
| A list screen with pagination, empty and loading states | `src/features/<x>/screens/<X>ListScreen.tsx` |
| A form with validation and a dirty guard | `src/features/<x>/screens/<X>EditScreen.tsx` |
| A shared row primitive | `src/components/<Row>.tsx` |
| Why-comments at the right altitude | `src/hooks/<useSomething>.ts` |

## Styling system

- Classes / tokens: `<utility classes | Tailwind | StyleSheet + theme>`.
- Design doc: `<DESIGN.md>` — read it before any visual judgment. Its "do not" list is binding.
- Non-className color props (icon `color`, ripple): `<useTheme()>` from `<src/lib/theme>`.

## Symptom → use this instead

| The component hand-rolls… | Use |
| --- | --- |
| A screen wrapper with padding / scroll / safe area | `<Screen>` |
| A styled text with size + weight classes | `<Text>` with a `variant` |
| A two-line tappable row | `<ListRow>` |
| A label + input + error text stack | `<FormField>` |
| A "no items yet" block | `<EmptyState>` |
| Cursor pagination state | `<usePagedQuery>` |
| A fetch with the auth token attached | `<useApi>` |

## Variant reference

- `<Button>` — `variant`: `<default · destructive · outline · ghost>`. `size`: `<default · sm · lg>`.
- `<Text>` — `variant`: `<default · h1 · h2 · h3 · muted · small>`.

## Known ceilings — don't recommend past these

- `<Checkbox is presentational; the wrapping Pressable owns the role and state>`
- `<Screen owns padding; a screen that sets its own p-* on top is fighting it>`

## Testing policy

`<end-to-end flows only — never suggest RN unit tests | RTL component tests expected for hooks and pure components>`

## Mandated TODO shapes

`<// TODO: use settings.<x>Label>` marks a hardcoded label awaiting configurable labels. It is required, not a smell; the finding is a label *without* it.

## Deferred — never propose as gaps

`<dark mode, offline mode, …>`
