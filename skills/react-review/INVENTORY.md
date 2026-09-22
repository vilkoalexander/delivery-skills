# Shared-Code Inventory

Reinvention is the #1 miss in AI-generated components, and a stale mental
inventory is why. **`scripts/inventory.sh` is authoritative for what exists** —
run it first. This file explains how to read it and what the project layer
should add on top.

## What the script prints

One line per module under each shared layer it can find: the file name, its
exported symbols, and the first line of its doc comment when it has one. Enough
to recognise a match, short enough to read in one pass.

The script looks for the conventional layers — `components/ui`, `components`, `hooks`, `lib`, `utils`, `constants` — under the
source root you pass it (or the first `src/` it finds). Pass the root explicitly
in a monorepo: `scripts/inventory.sh <app>/src`.

## What the project layer adds

`docs/review/react-review.md` in the project should carry the curated
**"symptom → use this instead"** table that a directory listing cannot express.
Its shape:

| The component hand-rolls… | Use |
| --- | --- |
| A screen wrapper with padding / scroll / safe area | `<Screen>` |
| A styled text with size + weight classes | `<Text>` with a `variant` |
| A two-line tappable row | `<ListRow>` |
| A label + input + error text stack | `<FormField>` |
| A "no items yet" block | `<EmptyState>` |
| Cursor pagination state | `<usePagedQuery>` |
| A fetch with the auth token attached | `<useApi>` |

Plus two lists that only a human who knows the codebase can write:

- **Variant reference** — the whole set of `variant` / `size` names per
  primitive, so the review never invents one.
- **Known ceilings** — what each primitive deliberately does *not* do
  (a presentational checkbox that is not pressable, a wrapper that owns padding
  and fights any `p-*` on top of it), so the review never recommends past it.

`templates/react-review.md` in this repository is a starting point.

## Layer boundaries

Generic primitive = no domain knowledge. App-level composition = reused across
features. `features/<x>/…` = reused inside one feature only. Single-file use
stays local — do not extract on first use.
