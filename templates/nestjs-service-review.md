# NestJS service review — project layer

Loaded by `nestjs-service-review` at step 2. Also the source for the scan
env: `TENANT_FIELD=<tenantId>` `EXEMPT_MODELS='<user|tenant|apiToken>'`.
Everything in `<angle brackets>` is a placeholder — replace it or delete the row.

## Tenancy

- Tenant key: `<tenantId | orgId | "" (single-tenant)>`.
- Source of truth: `<TenantGuard>` resolves it from the `<JWT | session>`; read it with `<@TenantCtx()>`.
- Guard stack on every tenant-scoped controller: `<@UseGuards(AuthGuard, TenantGuard)>` + `<@UseInterceptors(…)>`.
- Query-time backstop: `<src/prisma/tenant-isolation.ts | none>`.
- Deliberately unscoped models: `<User, ApiToken>` — and the guard's own membership lookup.

## Reference implementations

| Concern | Read |
| --- | --- |
| Service shape, tenant scoping, 404, mappers | `src/<x>/services/<x>.service.ts` |
| Controller shape, guards, Swagger, serialization | `src/<x>/controllers/<x>.controller.ts` |
| Controller delegation spec | `src/<x>/controllers/<x>.controller.spec.ts` |
| Idempotent write | `src/<x>/services/<x>.service.ts` |
| Multi-write atomic transaction | `src/<x>/services/<x>.service.ts` |
| Keyset pagination | `<src/shared/pagination/index.ts>` |

## Shared primitives — do not rebuild

| The file hand-rolls… | Use |
| --- | --- |
| Offset paging, a `count()` for "has more" | `<the keyset pagination helpers>` |
| A `'P2002'` literal | `<PRISMA_ERROR_CODES>` |
| An English error string | `<t(key, locale) | MESSAGES constant>` |
| A role check | `<TenantService.assertRole(ctx, role)>` |
| A context mock in a test | `<createMockContext>` from `@<scope>/test-utils` |

## Validation & serialization

`<nestjs-zod: DTOs from @<scope>/dto, @ZodSerializerDto on every handler | class-validator + ClassSerializerInterceptor>`

## Money & ledger

`<none | integer minor units with a Minor suffix; ledgers: <table> (append-only, SUM(delta))>`

## Known ceilings

- `<a guard's own lookup runs before the request context exists — unscoped by design>`
- `<one ceiling per line, stated as a rule a reviewer can check>`

## Deferred — never propose as gaps

`<feature, feature, …>`
