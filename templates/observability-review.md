# Observability review — project layer

Loaded by `observability-review` at step 2. Keep every entry a real path or
export. Everything in `<angle brackets>` is a placeholder — replace it or
delete the row.

## Logger

- Library: `<nestjs-pino | winston via nest-winston | @nestjs/common Logger>`, configured at `<apps/api/src/logging/logger.module.ts>`.
- Reaches a class by: `<constructor(@InjectPinoLogger(X.name) private readonly logger: PinoLogger) | private readonly logger = new Logger(X.name)>`.
- Field shape: `<this.logger.info({ orderId }, 'order paid')  — object first, message second>`.
- Levels: `error` = needs a human · `warn` = degraded, self-healing · `info` = business event · `debug` = diagnostic, off in prod.

## Correlation

- Mechanism: `<nestjs-cls at src/cls.module.ts | AsyncLocalStorage wrapper at src/lib/context.ts>`.
- Field: `<reqId>` — added automatically by `<pino-http mixin>`; `<yes | no>` a log call must add it by hand.
- Tenant field: `<tenantId>` — `<added by the CLS mixin | must be passed>`. Single-tenant: write "single-tenant".
- Propagated outbound via `<x-request-id header in src/http/client.ts; `correlationId` in queue payloads>`.

## Redaction

- Configured at `<logger.module.ts: redact.paths>`. Current list: `<req.headers.authorization, req.headers.cookie, *.password, *.token>`.
- Anything not on that list that must never be logged: `<card PAN, IBAN, national id>`.

## Errors

- Global filter: `<src/filters/all-exceptions.filter.ts>` — logs once at `error` for 5xx, `warn` for 4xx, and calls `<Sentry.captureException>` for 5xx.
- So a handler `<never | may>` log an error it rethrows.
- Client-facing error id: `<errorId in the response body = reqId>`.

## Tracing and metrics

- Tracing: `<@opentelemetry/sdk-node at src/tracing.ts; auto-instrumented: http, pino, prisma, ioredis>`. Manual spans for `<queue consumers, in-process pipelines>`.
- Metrics: `<prom-client via @willsoto/nestjs-prometheus; registry at src/metrics/>`. Counters exist for `<http_requests, jobs_processed, payments_attempted>`.
- Health: `<TerminusModule at src/health/; indicators: db, redis, <vendor>>`. A new external dependency adds one.

## Must-log events (the audit list)

| Event | Level | Fields |
| --- | --- | --- |
| `<payment captured / declined / refunded>` | info | `<paymentId, orderId, amount, currency, reason>` |
| `<entity deleted>` | info | `<entityType, entityId, actorId>` |
| `<auth decision denied>` | warn | `<userId, resource, reason>` |
| `<external vendor call failed>` | error | `<vendor, remoteId, status, durationMs>` |

## Ceilings — do not recommend past these

- `<No per-row logs in batch jobs; one summary line per batch>`
- `<No manual spans where OTel auto-instrumentation already covers the client>`
