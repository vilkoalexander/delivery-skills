# Observability Invariants

The one-way doors and what the project layer must supply. `CHECKLIST.md`
applies these to one file; this says why they are absolute and what the
rubric cannot know on its own.

## Invariants

1. **One logger.** Every line goes through the project's logger. A
   `console.*` line bypasses level, redaction, request id and shipping; it
   is not a weaker log, it is a missing one.
2. **One error, one log.** An error is logged once, at the layer that has
   the context, with the error object. Logged at every layer it is three
   alerts for one fault; logged nowhere it is a fault that never happened.
3. **Every request-scoped line carries the correlation id.** Without it the
   line cannot be joined to the request, the trace, the other services, or
   the user's report. When the project has a mechanism, absence is a defect.
4. **Nothing secret is ever logged.** Not at `debug`, not "temporarily",
   not behind a flag. Log pipelines are the place engineers can read what
   the database encrypts.
5. **Money, deletion and auth decisions leave a line** with the entity id
   and the outcome. These are the paths where "what happened" is asked
   under pressure.
6. **An external dependency is visible** — its calls carry an outcome and
   an id, and its liveness reaches the health endpoint when the project has
   one.

## What the project layer must supply

`docs/review/observability-review.md` (template in
`templates/observability-review.md`). Without it the rubric derives what it
can from `CLAUDE.md` and `scripts/inventory.sh` and says so.

| The rubric needs to know | Because |
| --- | --- |
| The logger and how it reaches a class (injection token, `new Logger(name)`, child) | §1 — to name the right call, not a generic one |
| The field shape (`(obj, msg)` pino style, or `(msg, ctx)` Nest style) | §1 — "structured" means their shape |
| The correlation mechanism and the field name (`reqId`, `traceId`, `correlationId`) | §4 — absence is only a defect if presence is possible |
| The tenant field name, or "single-tenant" | §4 |
| The redaction list, and where it is configured | Severity floor — what counts as secret here |
| The exception filter and the error reporter, and what they already capture | §2 — to avoid double-capture findings |
| Tracing setup and which clients are auto-instrumented | §3 — a manual span is only for what auto cannot see |
| Health module and metrics registry, if any | §6 — whether to expect a health indicator or a counter |
| Events that must always be logged (the "audit list") | Severity floor, §2 — the project's own list beats the generic one |
| Log volume ceilings, if any (lines per request, per job) | §5 |
