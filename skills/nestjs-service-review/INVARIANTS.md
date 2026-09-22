# Backend Invariants

The generic non-negotiables. `scripts/inventory.sh` is authoritative for what
currently exists; the project layer (`docs/review/nestjs-service-review.md`)
names the project's own primitives, reference files and ceilings.
`templates/nestjs-service-review.md` in this repository is a starting point.

## The three layers of tenant isolation

Multi-tenant services only.

1. **Auth → context.** A guard resolves the tenant key from the authenticated
   identity. Nothing else may source it — not a param, not a body field.
2. **Query-time backstop.** A Prisma extension (or middleware) that throws when
   a tenant-scoped model is queried without the tenant key, or with one that
   does not match the request context. Optional but recommended.
3. **Service `where` clauses (primary).** Every query names the tenant key
   explicitly. Layer 2 existing does not excuse omitting Layer 3 — Layer 2
   turns the bug into a 500, which is still an outage.

Creation operations prove tenancy through `data`; everything else proves it
through `where`.

## What the project layer must say

| Question | Why the review needs it |
| --- | --- |
| Tenant key name, or "single-tenant" | Sets `TENANT_FIELD`; decides whether §1 applies |
| The context decorator and guard stack | So §4 can check order and source |
| Models deliberately unscoped | Otherwise every `User` lookup is a false 🔴 |
| Shared primitives — pagination, error codes, i18n, mocks | "Do not rebuild these" needs real names |
| Reference implementations — one service, one controller, one spec, one transaction | The consistency baseline per pattern |
| Validation library and serializer | `nestjs-zod` vs `class-validator` changes §4 |
| Known ceilings | So the review never recommends past them |
| Deferred features | So they are not proposed as gaps |

## Shared primitives — the generic shapes

| The file hand-rolls… | Expect the project to have |
| --- | --- |
| Offset/limit paging, a `count()` for "has more" | a keyset pagination helper |
| A base64 cursor encode/decode | the same helper |
| A `'P2002'` string literal | a `PRISMA_ERROR_CODES` constant |
| An English error string | an i18n function or a messages constant |
| Reading `req.user` / `req.tenant` directly | a param decorator |
| A role check | an `assertRole`-style helper on the tenant service |
| A hand-built context object in a test | a test-utils factory |
| A hand-written type for a query result | `Prisma.validator` + `Prisma.XGetPayload` |
| A Prisma middleware (`$use`) | a client extension (`$extends`) |

If the project has none of these, the finding is "this should be the first
one" — once. Not on every file.

## Known ceilings — don't recommend past these

- **A guard runs before the request-scoped context exists.** Its own lookup is
  unscoped by design. Do not flag it; do not copy it.
- **Guard messages are not localizable** when locale is resolved from the
  tenant the guard is still finding.
- **Prisma does not retry serialization failures.** A stricter isolation level
  without a retry loop is worse than the default.
- **`$transaction` cannot span an HTTP call** without holding every lock for
  the round-trip duration.
