# Shared-Code Inventory

Reinvention is the #1 miss in AI-generated components, and a stale mental
inventory is why. **`scripts/inventory.sh` is authoritative for what exists** —
run it first. This file explains how to read it and what the project layer
should add on top.

## What the script prints

For every shared layer it can find, one line per Angular unit: kind
(component / directive / pipe / service), its selector or pipe name, the class,
and the first line of its doc comment when it has one. Enough to recognise a
match, short enough to read in one pass.

The script treats these as shared: Nx-style `libs/**` and `packages/**`, and
`src/app/shared`, `src/app/core`, `src/app/ui` under a classic CLI layout.
Everything under `features/`, `pages/` or a feature lib is listed as
feature-local. Pass the root explicitly in a monorepo:
`scripts/inventory.sh <app>/src`.

## What the project layer adds

`docs/review/angular-review.md` in the project should carry the curated
**"symptom → use this instead"** table that a directory listing cannot express.
Its shape:

| The component hand-rolls… | Use |
| --- | --- |
| A page shell with title and actions | `<app-page-header>` |
| A confirm dialog | `ConfirmDialogService.open()` |
| A date in the user's locale | `localDate` pipe |
| A loading skeleton | `<ui-skeleton>` |
| An empty-list placeholder | `<ui-empty-state>` |
| A debounced search input | `<ui-search-field>` |
| HTTP with auth + error mapping | `ApiClient` (never raw `HttpClient` in a component) |

Plus:

- **Which API generation the project is on** — signals + standalone + control
  flow, decorators + modules, or a documented mid-migration state with the
  rule for new files.
- **Known ceilings** — what each shared unit deliberately does *not* do, so the
  review never recommends past it.

`templates/angular-review.md` in this repository is a starting point.

## Layer boundaries

Shared UI = presentational, no domain knowledge. Shared data-access / util =
services, guards, interceptors, pure functions used by 2+ features. Feature
lib = reused inside one feature only. Single-file use stays local — do not
extract on first use.
