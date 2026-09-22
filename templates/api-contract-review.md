# API contract review — project layer

Loaded by `api-contract-review` at step 2. Also the source for the scan env:
`CLIENT_LIBS='<schemas|types|utils>'`.
Everything in `<angle brackets>` is a placeholder — replace it or delete the row.

## The chain

```
prisma/models/*.prisma
  → <contracts>/schemas   (@<scope>/schemas — zod, the source of truth)
      → <contracts>/dto   (@<scope>/dto — createZodDto, backend only)
      → <contracts>/types (@<scope>/types — z.infer, every consumer)
```

Barrels: `<contracts>/<pkg>/src/index.ts`.

## Who consumes what

| Package | api | web | mobile | Reaches a client bundle |
| --- | --- | --- | --- | --- |
| `@<scope>/schemas` | yes | yes | yes | yes |
| `@<scope>/types` | yes | yes | yes | types only |
| `@<scope>/dto` | yes | never | never | no |
| `@<scope>/test-utils` | tests | no | no | no |

Enforced by: `<nothing — review rule only | Nx tags + depConstraints in eslint.config.mjs>`.

## Release trains

| Client | Reaches users | Old builds in the field |
| --- | --- | --- |
| api | `<on merge>` | none |
| web | `<on reload>` | `<hours>` |
| mobile | `<store release pipeline>` | assume yes, indefinitely |

## Shared primitives — use, don't recreate

| Need | Use |
| --- | --- |
| ISO 4217 currency | `<currencySchema>` |
| Integer ceiling for a Postgres `Int` | `<PG_INT_MAX>` |
| `<status enum>` on create vs in responses | `<createXStatusSchema>` / `<xStatusSchema>` |

## Deliberate decisions — do not "fix"

- `<limit is not capped in the schema; the service clamps it>`
- `<No API versioning; "this is breaking" is the finding>`
- `<No codegen; the chain is hand-written on purpose>`
- `<zod pinned to <major> through the '<entry point>' root; note any wrapper library's zod-version constraint>`
