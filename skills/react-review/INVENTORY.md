# Shared-Code Inventory

Reinvention is the #1 miss in AI-generated components, and a stale mental
inventory is why. **`scripts/inventory.sh` is authoritative for what exists.**

It prints one line per module under `components/ui`, `components`, `hooks`,
`lib`, `utils`, `constants` and `shared`: file name and exported symbols.
Output is capped at `INVENTORY_LIMIT` lines per layer (default 40) and shows
the overflow count; `INVENTORY_DOCS=1` adds each module's first doc line. In
a monorepo pass the root: `scripts/inventory.sh <app>/src`.

The project layer (`docs/review/react-review.md`, template in
`templates/react-review.md`) adds what a listing cannot: the
symptom → use-this-instead table, the variant names per primitive, and the
known ceilings. Name a replacement by its real export, never a guess.

Layers: generic primitive = no domain knowledge; app-level composition =
reused across features; `features/<x>/…` = one feature. Single-file use stays
local — do not extract on first use.
