# NestJS Service Review Checklist

Eight categories. Walk them in order. Each rule is tagged **[hard]**,
**[prefer]** or **[context]** — see SKILL.md. Name the consequence: "this is
wrong" without "because X breaks" is not a finding.

`<tenant>` below stands for the project's tenant key (`TENANT_FIELD`). Skip §1
on a single-tenant service and say so in one line.

## 1. Tenant isolation — merge blocker

The service `where` clause is the primary defence. A global Prisma extension
or middleware that checks scoping is a backstop that throws 500, not a licence
to omit scoping.

- **[hard] Every query on a tenant-scoped model carries `<tenant>`** in its
  `where` — `findFirst`, `findMany`, `updateMany`, `deleteMany`, `count`,
  `aggregate`, `groupBy`. Creates prove tenancy through `data`. No exceptions.
  Always 🔴.
- **[hard] `<tenant>` comes from the authenticated context** — a guard-resolved
  request context, a JWT claim, a session — **never** from a route param,
  query string, or request body. A `<tenant>` field in a request DTO is itself
  the finding.
- **[hard] `findUnique` cannot be tenant-scoped** unless the model has a
  compound unique including `<tenant>`. Default to `findFirst` with
  `{ id, <tenant> }`.
- **[hard] Cross-tenant miss returns 404, never 403.** A 403 confirms the id
  exists in another tenant; 404 reveals nothing. `findFirst` returning null
  covers both cases — that is the point. Always 🔴. 403 is correct only for
  *authorization* failures: no membership, wrong role.
- **[hard] Nested writes and `include` / `select` reach other models** — a
  relation traversal must not escape the tenant. Check the include tree.
- **[context] Guard-time queries run before the tenant context exists.** A
  guard's own membership lookup is unscoped by design. Do not flag it; do not
  copy the pattern into a service.

## 2. Money & ledger invariants

Skip §2 when the service touches no money and no ledger, and say so.

- **[hard] Money is integer minor units** (`amountMinor`, `priceCents`). Never
  `Float`, never a `number` parsed from a decimal string. Any arithmetic that
  can produce a fraction is a bug.
- **[hard] `currency` travels with every amount** (ISO 4217) unless the model
  is single-currency by documented design.
- **[hard] Balance is never stored** where a ledger exists. It is
  `SUM(ledger.delta)`. A cached balance written back to a row is a 🔴.
- **[hard] Reversal compensates, never deletes.** Undo emits a compensating
  ledger row. Deleting or mutating a past ledger row is a 🔴.
- **[context] Idempotency** — a write a client may retry (payments, grants,
  order placement) is keyed on `(<tenant>, idempotencyKey)`: same key + same
  body replays the original, same key + different body is a 409. A new
  retryable money endpoint without this is a finding.

## 3. Transactions & async correctness

No type-aware lint here, so nothing but this review catches the following.

- **[hard] Use `tx`, not `this.prisma`, inside a `$transaction` callback.** The
  single most common Prisma bug: the outer client is not enrolled in the
  transaction, so the call blocks on locks the transaction itself holds and
  hangs until timeout. Raising the timeout only prolongs the stall. Always 🔴.
- **[hard] Unawaited promise** — a `prisma.*` call or `$transaction` without
  `await` / `return` resolves after the response is sent, so its failure
  surfaces as an unhandled rejection instead of a 500. Always 🔴.
- **[hard] Atomic multi-write** — a parent row and its child rows, or a
  business event and its ledger entries, go in ONE `$transaction`. Partial
  writes corrupt the data.
- **[hard] No network calls inside a transaction** — `fetch`, HTTP clients,
  the auth provider, a queue publish. Interactive transactions hold locks for
  their whole duration; fetch first, then open the transaction.
- **[prefer] Keep the transaction body short** — parsing, authorization checks
  and mapping belong outside it.
- **[context] Isolation level** — the default is fine for most writes. A
  stricter level (`RepeatableRead`, `Serializable`) also needs a retry path,
  because Prisma does not auto-retry `P2034` write conflicts.
- **[context] The 5s default timeout** — a transaction that loops over an
  unbounded collection will blow it. Bound the work or move it out.

## 4. Controller & contract shape

- **[hard] Controllers are thin.** Extract context / params, delegate, return.
  Any branching, Prisma access, or mapping in a controller belongs in the
  service.
- **[hard] Guard stack order matches the siblings** — an auth guard before a
  tenant guard that reads `req.user`, plus whatever interceptor sets the
  request-scoped tenant context. The project layer names the exact stack.
- **[hard] Read the request context through the project's decorator**
  (`@CurrentUser()`, `@TenantCtx()`), not by reaching into `req` — the
  decorator carries the "guard must have run" assertion.
- **[hard] Response serialization on every handler** — `@ZodSerializerDto`,
  `ClassSerializerInterceptor`, or whatever the project uses. Without it the
  response shape is unvalidated and a contract drift ships silently.
- **[hard] `ParseUUIDPipe` (or `ParseIntPipe`) on every id param.**
- **[prefer] Swagger decorators match reality** — the response codes listed
  are the ones the service can actually throw. A documented 403 on an endpoint
  that returns 404 for cross-tenant is a doc bug worth flagging.
- **[prefer] `@HttpCode(HttpStatus.CREATED)` on a POST that creates.**
- **[hard] DTOs and response types come from the shared contract package**
  when the project has one. A type redefined locally is a contract split.

## 5. Pagination & unbounded queries

- **[hard] Every list endpoint is paginated** with the project's shared helper
  (limit clamp, cursor encode/decode, keyset `where` / `orderBy`, page
  builder). Do not hand-roll offset pagination or a bare `findMany`.
- **[hard] `take: limit + 1`** — the overflow probe is how a keyset page knows
  whether a next page exists. `take: limit` breaks `nextCursor`.
- **[hard] Any `findMany` without a `take`** is an unbounded query. Includes
  nested `include` relations that can grow without limit.
- **[hard] Keyset sort is `(createdAt, id)`** or another unique pair. A
  `createdAt`-only sort skips or duplicates rows when timestamps collide.
- **[prefer] No `count()` for "has more"** — the probe row already answers it.

## 6. Errors & i18n

- **[hard] User-facing messages go through the project's i18n function** when
  it has one. A hardcoded string in a thrown exception is a finding. Guards
  that run before the locale is resolved are the documented exception.
- **[hard] Prisma error codes come from a named constant**, not string
  literals like `'P2002'`.
- **[prefer] Map known Prisma errors** — unique constraint → `ConflictException`
  with a specific message, not a bare 500.
- **[prefer] Never swallow an error** into a default return value; a caught
  error is either mapped or rethrown.
- **[context] Log level** — `logger.warn` for a caller mistake, `logger.error`
  for a server bug. Never log a token, a JWT, or a full request body.

## 7. Tests

Every new backend unit needs a spec — services **and** controllers.

- **[hard] Controller delegation spec** — `Test.createTestingModule` with the
  service replaced by a `jest.fn()` / `vi.fn()` double and every guard
  overridden via `.overrideGuard(...).useValue({ canActivate: () => true })`.
  Assert the service was called with exactly the right arguments and the
  result is passed through. The project layer names the reference spec.
- **[hard] Service spec covers the invariant, not just the happy path** — the
  cross-tenant 404, the role rejection, the ledger sign, the idempotent
  replay. A spec that only proves "it calls prisma" proves nothing.
- **[prefer] Mocks come from the project's test-utils package** rather than
  being hand-built per file.
- **[prefer] Spec location follows the siblings** — `__tests__/x.service.spec.ts`
  or `x.controller.spec.ts` beside the file.
- **[context] Missing spec file** — `scripts/inventory.sh` lists them. Report
  it for the file under review only; do not turn the review into a backlog.

## 8. Structure & consistency

- **[hard] Module boundaries** — a service reaches other modules through their
  exported service, not by importing another module's Prisma queries.
- **[prefer] Barrel exports** — each folder has an `index.ts`; imports use it,
  not deep paths into a sibling module's internals.
- **[prefer] `Prisma.validator<...>()` for reusable include / select shapes**
  with a derived `Prisma.XGetPayload<...>` row type. A hand-written interface
  for a query result drifts from the schema.
- **[prefer] Static `toXResponse` mappers** convert rows to response types in
  one place; `Date` → `.toISOString()` at the boundary, never a raw `Date` in
  a response.
- **[hard] `$extends`, not `$use`** on Prisma 5+ — middleware is deprecated.
- **[hard] No `process.env` reads scattered through services** —
  configuration is injected (`ConfigService` or a typed config provider).
- **[prefer] Class member order matches the siblings** — constructor, public
  methods, then private and static helpers.

---

## Sources

- [Prisma — Transactions and batch queries](https://www.prisma.io/docs/orm/prisma-client/queries/transactions) — interactive transaction timeout / maxWait, isolation levels, lock duration
- [Prisma discussion #25922 — transaction deadlocks and timeouts](https://github.com/prisma/prisma/discussions/25922) — the `this.prisma`-inside-`tx` hang
- [NestJS — Testing](https://docs.nestjs.com/fundamentals/testing) — `overrideGuard`, `createTestingModule`
- [Prisma — Unit testing](https://www.prisma.io/docs/orm/prisma-client/testing/unit-testing) — mocking the client by injection
- [typescript-eslint — no-floating-promises](https://typescript-eslint.io/rules/no-floating-promises/) — requires type information (`parserOptions.project`)
