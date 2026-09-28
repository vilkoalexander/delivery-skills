# Test-Helper Inventory

The most common miss in AI-written tests is a second render wrapper, a
second user factory, a second auth stub. **`scripts/inventory.sh` is
authoritative for what exists.**

It prints, per section: the runner and its config and setup files; helper
modules under the conventional locations (`test`, `tests`, `__tests__`,
`test-utils`, `testing`, `fixtures`, `factories`, `__mocks__`, `mocks`)
with their exports; `msw` handlers; and a count of `.only`/`.skip` across the
suite so a stray one is visible before the review starts. Output is capped at
`INVENTORY_LIMIT` lines per section (default 40) and shows the overflow
count. In a monorepo pass the root: `scripts/inventory.sh <app>`.

The project layer (`docs/review/test-review.md`, template in
`templates/test-review.md`) adds what a listing cannot: which helper to use
for which situation, the fixture strategy for the database and the network,
and the test types the project has decided against. Name a replacement by
its real export, never a guess.
