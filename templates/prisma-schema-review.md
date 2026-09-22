# Prisma schema review — project layer

Loaded by `prisma-schema-review` at step 2. Also the source for the scan env:
`TENANT_FIELD=<tenantId>` `EXEMPT_MODELS='<User|Tenant|ApiToken>'`
`LEDGER_TABLES='<ledger_table|other_ledger_table>'`.
Everything in `<angle brackets>` is a placeholder — replace it or delete the row.

## Tenancy

- Tenant key: `<tenantId | orgId | "" (single-tenant)>`.
- Scoping tiers (from `<src/prisma/constants/…>`): scoped (default) · globally unscoped `<User>` · pure child reached through its parent `<ParentLine>`.
- Deliberately tenant-free uniques: `<@@unique([parentId, position])>` — the parent FK pins the tenant.

## Reference models

| Pattern | Read |
| --- | --- |
| Plain tenant-scoped entity | `prisma/models/<x>.prisma` |
| Append-only ledger | `prisma/models/<ledger>.prisma` |
| Idempotent financial event | `prisma/models/<event>.prisma` |
| Globally unscoped model | `prisma/models/<auth>.prisma` |

## Conventions

- Ids: `<uuid() | cuid() | autoincrement>`; tables `@@map` to `<snake_case plural | none>`.
- Money: `<Int minor units, Minor suffix, currency String beside every amount | Decimal(12,2) by decision because …>`.
- Data-architecture doc: `<docs/data-architecture.md>` — §<n> is the ledger contract, §<n> the migration protocol.

## Tables that grow without bound

`<ledger, events, audit log>` — lock duration is a real finding here; elsewhere it is not.

## Forward hooks — not dead columns

- `<Model.column>` — `<nullable + unique; written for a feature with no UI yet>`.
- `<Model.column>` — `<written, not yet read>`.

## Known ceilings

- `<CREATE INDEX CONCURRENTLY is out-of-band only>`
- `<no varchar(n) — lengths capped at the DTO>`

## Deferred — never propose as gaps

`<multi-currency, soft-delete everywhere, …>`
