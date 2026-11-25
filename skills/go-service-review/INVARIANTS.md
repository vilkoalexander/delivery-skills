# Go Backend Invariants

The generic non-negotiables. `scripts/inventory.sh` is authoritative for what
currently exists; the project layer (`docs/review/go-service-review.md`)
names the project's own primitives, reference files and ceilings.
`templates/go-service-review.md` in this repository is a starting point.

## The three layers of authorization

1. **Authentication → identity in the context.** A middleware resolves the
   caller from the session or the token and puts it in the request context
   under an unexported key type. Nothing else may source identity: not a
   header, not a form field, not a query value.
2. **Route protection.** Go has no annotation on a handler. A handler is
   protected only when the line that registers it wraps it in the middleware,
   or mounts it under a group that does. A handler file can look correct and
   be public.
3. **Object and query scope.** A handler that takes an id checks that this
   caller may act on that object; a list is filtered in the query by what the
   caller may see.

Layer 2 does not excuse omitting layer 3: "is signed in" is not "owns this
order".

## Who ends what

| Started | Ends when | Who must make that true |
| --- | --- | --- |
| A handler | it returns | the handler: a `return` after every error response |
| A query, a remote call | the context is cancelled or the deadline passes | the caller passes the request context; the server and the client set the deadlines |
| A transaction | `Commit` or `Rollback` | `defer tx.Rollback()` on the line after `Begin` |
| Rows, a response body, a file | `Close` | `defer` on the line after the error check |
| A goroutine | its function returns | the code that started it: a context, a closed channel, an `errgroup`, a `WaitGroup` |
| The process | `SIGTERM` | `main`: `signal.NotifyContext`, `Server.Shutdown`, then wait for the workers |

A request context is cancelled the moment the handler returns. Work that must
outlive the request takes `context.WithoutCancel(ctx)` and its own timeout,
and something still waits for it at shutdown.

## What the project layer must say

| Question | Why the review needs it |
| --- | --- |
| Where routes are registered, and which middleware authorizes them | Otherwise layer 2 cannot be checked from a handler file |
| The paths that are public on purpose | So an unwrapped route is not a false 🔴 |
| How identity is read from the context | So §1 can check the source |
| The object-level check: a helper, a scoped query, a policy package | So §1 can name the right one |
| The 403 / 404 rule for an object the caller may not see | So §1 judges it the same way every time |
| Layering: handler → service → store, or handler → store | Decides whether SQL in a handler is a finding |
| Data access: `database/sql`, pgx, sqlc, an ORM; where the transaction boundary is | Decides which rules of §6 apply |
| Error types, the mapping from error to status, the render helper | "Do not rebuild these" needs real names |
| Logger, and the fields that must never be logged | So §2 judges a log line |
| CSRF defence: `CrossOriginProtection`, a token, none | So §5 knows whether a state-changing GET is exploitable |
| Reference implementations — one handler, one service, one store, one test | The consistency baseline per pattern |
| Test fixtures: the real-engine database, the server helper | So §7 can require them |
| Remote clients in the codebase | Sets `REMOTE_CALL` for the scan |
| Known ceilings and deferred features | So the review never recommends past them |

## Shared primitives — the generic shapes

| The file hand-rolls… | Expect the project to have |
| --- | --- |
| `http.Error` with a status picked on the spot | one function that maps an error to a response |
| A render-to-buffer-then-write sequence | a render helper |
| `HX-Request` read and a branch on it | a helper that picks fragment or page and sets `Vary` |
| `r.Context().Value(...)` with a type assertion | a typed accessor for the caller |
| `errors.New` for "not found" in each package | shared sentinel errors or an error type with a kind |
| Decoding, size limit and validation of a body | one decode helper |
| `Begin`, `defer Rollback`, `Commit` around a closure | a transaction helper |
| Page and limit parsing | a paging helper with a maximum |
| A pointer helper, a `contains`, a `max` | `new(expr)` (1.26), `slices`, the builtins |
| A container and a schema in a test | a test database helper |
| `time.Now()` | an injected clock, when the project has one |

If the project has none of these, the finding is "this should be the first
one" — once. Not on every file.

## Known ceilings — do not recommend past these

- **A transaction cannot span a remote call** without holding a connection
  for the round trip. The order of the work fixes it, not a longer timeout.
- **Rollback does not undo a remote effect.** A message sent or a payment
  taken stays. Compensation is code.
- **A goroutine cannot be killed from outside.** It stops only when its own
  code checks a context or a channel. A design that needs to kill one is the
  finding.
- **The race detector finds only races that happen in the run.** `-race`
  passing is not proof.
- **`http.CrossOriginProtection` passes every GET, HEAD and OPTIONS.** It
  protects nothing that changes state on a GET.
- **`Server.Shutdown` does not wait for hijacked connections or for
  goroutines the handlers started.** SSE and WebSocket handlers need their
  own stop.
