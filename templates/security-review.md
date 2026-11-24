# Security review — project layer

Loaded by `security-review` at step 2. Keep every entry a real path or
export. Everything in `<angle brackets>` is a placeholder — replace it or
delete the row.

## Who is asking

- Session: `<bearer JWT in the Authorization header | httpOnly cookie "sid">`. Issued at `<apps/api/src/auth/auth.service.ts>`, verified by `<JwtStrategy at apps/api/src/auth/jwt.strategy.ts>` with algorithm `<RS256>`.
- The caller in a handler: `<@CurrentUser() user: AuthUser>` — owner key `<user.id>`, tenant key `<user.tenantId>`.
- Password hash: `<hashPassword / verifyPassword from src/auth/password.ts (argon2id)>`.
- Random secrets: `<newToken() from src/lib/tokens.ts>`. One-time tokens are stored `<hashed, with expiresAt, deleted on use>`.
- The client keeps the token in: `<expo-secure-store through src/session/store.ts | cookie only>`.
- Account enumeration: `<matters — sign-in and reset answer the same for a known and an unknown email | does not matter here>`.

## Who may act

- Global guard: `<JwtAuthGuard as APP_GUARD in app.module.ts>` — a new route is covered. Opened with `<@Public() from src/auth/public.decorator.ts>`.
- Roles and permissions are decided in: `<RolesGuard + @Roles() | CASL ability at src/auth/ability.factory.ts>`. Not in a handler body.
- CSRF: `<not applicable, bearer tokens | csurf on every state-changing route>`.

### Public on purpose

| Route | Why |
| --- | --- |
| `<POST /auth/login, POST /auth/refresh>` | `<sign-in>` |
| `<GET /health>` | `<probe>` |
| `<POST /webhooks/stripe>` | `<signature-checked>` |

### A client may never set

| Entity | Fields |
| --- | --- |
| `<User>` | `<role, emailVerified, tenantId>` |
| `<Order>` | `<status, total, ownerId>` |

### Never leaves the server

`<User.passwordHash, User.resetTokenHash, ApiKey.secret, internal notes>` — responses go through `<the DTOs in src/**/dto/ | select presets in src/prisma/selects.ts>`.

## What it lets in and where it sends

- Validation: `<global ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }) | zod schema per route>`.
- Throttler: `<@nestjs/throttler, default 100/min; auth routes 5/min by @Throttle>`. Already covers `<every route>`.
- Uploads: `<FileInterceptor with limits at src/uploads/upload.config.ts — 5 MB, images only, stored under a generated key in S3>`.
- Outbound hosts: `<api.stripe.com, the hosts in src/config/outbound.ts>`. A URL from a user goes through `<assertPublicUrl() from src/lib/url.ts>`.
- Webhooks: `<Stripe — stripe.webhooks.constructEvent on the raw body, in src/webhooks/stripe.controller.ts>`.
- CORS: `<origins from CORS_ORIGINS in config>`.

## Sensitive data here

`<email, phone, address, payment method last four, date of birth>` — not in URLs, cache keys or analytics events.

## Known ceilings — do not recommend past these

- `<No second auth library; no hand-rolled crypto>`
- `<No per-handler role checks where the guard already decides>`
