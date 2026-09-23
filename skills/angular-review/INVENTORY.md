# Shared-Code Inventory

Reinvention is the #1 miss in AI-generated components, and a stale mental
inventory is why. **`scripts/inventory.sh` is authoritative for what exists.**

It prints one line per shared unit — kind, selector or pipe name, class —
under Nx-style `libs/**` and `packages/**`, or `src/app/{shared,core,ui}` on
a classic CLI layout, then counts of API-generation markers across the
scanned roots (decorators vs signals, `*ngIf` vs `@if`, and so on). Output is
capped at `INVENTORY_LIMIT` lines per root (default 40) and shows the overflow
count; `INVENTORY_DOCS=1` adds each unit's first doc line. In a monorepo pass
the root: `scripts/inventory.sh <app>/src`.

The project layer (`docs/review/angular-review.md`, template in
`templates/angular-review.md`) adds what a listing cannot: the
symptom → use-this-instead table, which API generation the project is on
(and the rule for new files mid-migration), and the known ceilings.

Layers: shared UI = presentational, no domain knowledge; shared data-access /
util = services, guards, interceptors, pure functions used by 2+ features;
feature lib = one feature. Single-file use stays local — do not extract on
first use.
