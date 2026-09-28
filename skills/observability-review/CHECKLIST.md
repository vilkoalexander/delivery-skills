# Observability Review Checklist

Six categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). For
each finding, name the production question it leaves unanswerable: "add a
log here" without "otherwise a failed refund is invisible" is not a finding.

## Before you start

### Version baseline

Read what the project runs on before applying the rules:

```bash
node -e 'const p=require("./package.json"),d={...p.dependencies,...p.devDependencies};for(const k of ["@nestjs/common","pino","nestjs-pino","pino-http","winston","nest-winston","@opentelemetry/sdk-node","@opentelemetry/api","@sentry/node","@sentry/nestjs","dd-trace","newrelic","nestjs-cls","@nestjs/terminus","prom-client","@willsoto/nestjs-prometheus"])if(d[k])console.log(k,d[k])'
```

- **`nestjs-pino` / `pino-http`** — every request already gets a request
  log with a request id; per-handler "request received" logs are noise.
  `redact` in its options is the project's redaction list.
- **`nestjs-cls` or an `AsyncLocalStorage` wrapper** — the correlation id is
  available anywhere; a log without it is a defect, not a limitation.
- **`@opentelemetry/*` or `dd-trace`** — HTTP, Prisma and common clients are
  auto-instrumented; a manual span is for a unit of work those do not see
  (a loop over a queue, an in-process pipeline).
- **`@sentry/*`** — unhandled errors are captured by the filter; a
  `captureException` in a handler that also throws double-reports.
- **`@nestjs/common` `Logger` only** — string messages; structured fields
  need the project's convention (JSON in the message, or a wrapper).

### Tooling coverage

Do not assume what lint catches. Run once per review:

```bash
npx eslint --print-config <file> | grep -E '"(no-console|@typescript-eslint/no-floating-promises)'
```

`no-console` at `"error"` means §1's console rule is the build's job — skip
it. Absent, it is this skill's job. Nothing in lint knows whether a catch
logs, whether a log carries the tenant id, or whether a secret is in a log
field; `scripts/scan.sh` targets those. When the dispatch handed you a
coverage table from the static gate, use that and skip the command.

For the full picture — every analyzer the repository has or lacks, and the
strict recipe for each missing one — `bash
${CLAUDE_PLUGIN_ROOT}/skills/delivery-pipeline/scripts/static-gate.sh
coverage` and its `STATIC-SETUP.md`.

## Severity floor

Always 🔴, regardless of effort:

- a secret, token, password, `Authorization` or cookie header, card number,
  or full request body with any of those, in a log call
- a `catch` that neither rethrows nor logs the error object
- a money movement, a deletion, or an auth decision with no log line that
  carries the entity id and the outcome

## 1. The logger

- **[hard] Project logger, not console** — `console.*` where the project
  injects a logger. The console line has no level, no request id, no
  redaction, and is dropped by the log pipeline.
- **[hard] Class-scoped context** — `new Logger(OrdersService.name)`, a
  child logger, or the injected one with its context; a bare `Logger`
  without context makes every line "from somewhere".
- **[prefer] Structured fields over interpolation** — `` `Order ${id} failed` ``
  cannot be filtered by `orderId`; `({ orderId }, 'order failed')` can. The
  project layer says which shape is theirs.
- **[prefer] Stable message, variable fields** — the message is the search
  key; ids, counts and states go in fields.
- **[context] `JSON.stringify` inside a log call** — usually the whole
  object, with whatever is in it; report when the object can carry a secret
  or is unbounded.

## 2. Error paths

- **[hard] Silent catch** — the floor. Also: a catch that logs a string
  without the error object, so there is no stack and no cause.
- **[hard] Log-and-rethrow at every layer** — the same error logged three
  times as it unwinds; the filter logs it once at the boundary. One log per
  error, at the layer that has the context.
- **[prefer] Wrong level** — an expected miss (404, validation, a
  duplicate) at `error` pages someone; an unexpected failure at `warn`
  pages no one. `error` is for what needs a human.
- **[prefer] The domain outcome, not only the exception** — "payment
  declined" is a business event with a reason code; it is logged as such,
  not only as the exception class.
- **[context] Error reporter double-capture** — `captureException` in a
  handler whose exception the global filter already captures.

## 3. External calls and units of work

- **[hard] External call with no outcome** — an HTTP client, a queue
  publish, a third-party SDK, a payment call, with no log or span carrying
  the outcome and the id on the other side. When it fails you have nothing
  to send to the vendor.
- **[prefer] Duration** — a call that can be slow is logged or spanned with
  its duration; the auto-instrumentation covers HTTP and Prisma, not a
  hand-rolled `fetch` wrapper or an SDK.
- **[prefer] Job and consumer boundaries** — a queue consumer, a cron, a
  batch: start with the batch id and size, end with counts of ok, failed,
  skipped. A job that logs nothing either ran or did not.
- **[context] Manual span** where auto-instrumentation cannot see — an
  in-process pipeline, a loop with per-item work.

## 4. Correlation

- **[hard] Request id absent** when the project has one — the log cannot
  be joined to the request, the trace, or the other services.
- **[hard] Tenant id absent** on a tenant-scoped path in a multi-tenant
  project — you cannot answer "which customer".
- **[prefer] Entity ids** — the order, the user, the payment intent, in
  fields, on every line about them.
- **[prefer] Propagation across the boundary** — the id goes into the queue
  message, the outbound header, the job payload; the consumer logs with it.
- **[context] User-facing error reference** — when the project returns an
  error id to the client, the log carries the same id.

## 5. Volume and level

- **[hard] Per-item `info` in a loop** over user data — a thousand lines per
  request; the pipeline bills for it and the signal drowns.
- **[prefer] `debug` for the diagnostic detail**, gated by level, not
  deleted. Payload shapes and intermediate values belong at `debug`.
- **[prefer] No log for the happy path of a trivial handler** when
  `pino-http` already logs the request; the extra line is noise.
- **[context] Unbounded field** — an array, a full entity, a response body
  in a log field; report when it can be large.

## 6. Health, metrics and alerts

- **[hard] New external dependency with no health or readiness signal**
  when the project has `terminus` or an equivalent — the deploy goes green
  while the dependency is down.
- **[prefer] Counter or histogram** for a new business-critical path when
  the project runs `prom-client` or an equivalent — a dashboard cannot be
  built from logs alone.
- **[context] Alert-worthy condition without a distinguishable signal** —
  a failure that should page but is logged with the same message and level
  as a routine warning. Report only when the project layer names an SLO or
  an alert.

## Do NOT report

- Log wording, capitalisation, or punctuation.
- Logs in pure functions, DTOs, mappers or config — nothing happens there.
- Replacing the project's logger, tracer or error reporter with another.
- Dashboard, alert or retention configuration — infrastructure, not this
  file.
- A metric platform the project has not chosen.
- Anything ESLint already **errors** on (see Tooling coverage).
- Restating the project's instructions file as if it were a finding.
- Adding logs to untouched sibling code. Review the file in front of you.
