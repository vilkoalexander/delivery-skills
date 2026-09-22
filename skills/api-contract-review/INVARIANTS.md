# Contract Invariants

The generic shape. `scripts/inventory.sh` is authoritative for the current
chain; the project layer (`docs/review/api-contract-review.md`) names the
packages, the consumers and the release trains.
`templates/api-contract-review.md` in this repository is a starting point.

## The chain

```
database schema (Prisma, SQL)          ← the persistence truth
        │ (hand-mirrored enums; nothing enforces it)
        ▼
schemas package   validation schemas — THE source of truth for the API
        ├──► dto package     framework wrapper → server validation + API docs
        └──► types package   inferred types    → every consumer
```

One direction only. `types` never defines a shape; `dto` never defines a
shape. If a shape exists in two places, one of them is wrong.

## Who consumes what — the generic table

| Package | Server | Client apps | Reaches a client bundle |
| --- | --- | --- | --- |
| schemas | yes | yes | **yes** — runtime code ships |
| types | yes | yes | types only (erased) |
| utils | yes | yes | **yes** |
| dto | yes | **never** | no — depends on the server framework |
| test-utils | tests only | no | no — may reach the database client |

The project layer fills in real names and counts. Nothing in most lint
configs enforces the "never" row — that is why it is a review rule.

## The release-train asymmetry

| Client | Reaches users | Old builds in the field |
| --- | --- | --- |
| Server | on deploy, minutes | none |
| Web SPA | on reload; cached bundles linger hours | short tail |
| Mobile (store) | when the user updates | **assume yes, indefinitely** |
| Desktop / CLI | when the user updates | assume yes |

Every contract change is judged twice: **new server + old client** and
**old server + new client**. Corollary for `.strict()` request schemas: a
field the client sends must exist on the server *first*, in an earlier
deploy. Schema and client cannot ship together.

## What the project layer must say

| Question | Why the review needs it |
| --- | --- |
| Package names per chain link, and the barrel files | So §2 can check the chain |
| Which apps import which package, by count | Decides what "reaches a bundle" means here |
| Release train per client | Decides how long old builds live |
| Shared primitives — currency, integer ceiling, common enums | "Use, don't recreate" needs real names |
| Validation library and pin | Decides §3's strictness mechanics and what not to propose |
| Deliberate decisions — uncapped `limit`, no versioning, no codegen | So they are not "fixed" |

## Known ceilings — don't recommend past these

- **No API versioning** until the project builds it. "This is breaking" is
  the finding; choosing to break it is the human's call.
- **No codegen** when the chain is hand-written on purpose and a few lines
  per entity.
- **Enum mirroring is manual.** The database enum is the truth and the
  schema enum is a copy. The inventory cross-check is the only safety net.

## Out of scope

Tenant scoping and ledger semantics → **nestjs-service-review**. Columns,
indexes and migrations → **prisma-schema-review**. Component structure →
**react-review** / **angular-review**.
