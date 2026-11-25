# Go Service Review Checklist

Nine categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). Name the
consequence: "this is wrong" without "because X breaks" is not a finding.

HTML templates and `.templ` files have their own rubric, `htmx-review`. This
one covers handlers, services, stores, middleware, `main`, workers and their
tests.

## Before you start

### Version baseline

Read before applying §2, §3, §4 and §8:

```bash
grep -E '^(go|toolchain) ' go.mod
```

The `go` line is a strict minimum since 1.21 and it selects the language
rules: a module on `go 1.21` still shares one loop variable across
iterations. Do not recommend an API the `go` line does not have.

| `go` line | What changes |
| --- | --- |
| below 1.21 | No `slog`, `slices`, `maps`, `min` / `max`, `context.WithoutCancel`. Skip the stale-idiom rules of §8. |
| 1.21 | `log/slog`, `slices`, `maps`, `cmp`, `min` / `max` / `clear`, `context.WithoutCancel` and `AfterFunc`, `sync.OnceValue`. |
| 1.22 | One loop variable per iteration: `x := x` is dead code and a closure in a loop is safe. `ServeMux` takes `"GET /items/{id}"` and `r.PathValue`. `math/rand/v2`. |
| 1.23 | Range over functions, `iter`. An unreferenced timer is collected: `time.After` in a loop no longer leaks. |
| 1.24 | `omitzero`, `os.Root`, `tool` directives in `go.mod`, `b.Loop()`, `t.Context()`. |
| 1.25 | `testing/synctest`, `sync.WaitGroup.Go`, `http.CrossOriginProtection`, `GOMAXPROCS` follows the container CPU limit. A result used before its `err` check now panics where it used to pass. |
| 1.26 | `new(expr)`, `errors.AsType`, `go fix` runs the modernizers, `signal.NotifyContext` cancels with a cause. |
| 1.27 | `encoding/json` runs on the v2 implementation and `encoding/json/v2` is stable: v2 rejects duplicate names and invalid UTF-8. `uuid` in the standard library. Generic methods. Goroutine leak profile. |
| 1.28 (draft, February 2027) | `go vet` reports a missing `rows.Err()`. |

### Tooling coverage

Do not assume what the build catches. When the dispatch handed you the static
gate's coverage lines, use them and skip the command. Otherwise run once per
review:

```bash
ls .golangci.y*ml .golangci.toml 2>/dev/null; grep -E 'default:|^ +- ' .golangci.y*ml 2>/dev/null | head -40
grep -rhoE 'go vet|staticcheck|govulncheck|go fix|golangci-lint|-race' Makefile Taskfile.y*ml .github/workflows 2>/dev/null | sort | uniq -c
```

| Runs in the build | Do not hand-report |
| --- | --- |
| `gofmt` / `goimports` | formatting, import order |
| `go vet` | a lost `cancel`, a copied lock, a `Printf` verb mismatch, a bad struct tag, `wg.Add` inside the goroutine, a response used before its error check, mismatched `slog` pairs |
| golangci-lint `standard` | an unchecked error, an unused value, the staticcheck set |
| `errorlint` | `==` on an error, a type assertion on an error, `%v` where `%w` was meant |
| `bodyclose`, `sqlclosecheck`, `rowserrcheck` | an unclosed body or rows, a missing `rows.Err()` |
| `noctx`, `contextcheck` | a request or a query with no context |
| `gosec` | a string-built query, `InsecureSkipVerify`, `math/rand` for a secret, a server with no header timeout |
| `modernize`, or `go fix -diff ./...` clean in CI | every stale idiom of §8 |
| `govulncheck` | a dependency with a known vulnerability |
| `go test -race` | a race the tests exercise — and only those |

A golangci-lint configuration without `version: "2"` is refused by v2: treat
its linters as absent and say so once.

Nothing in that table sees any of these, so they are this review's job: a
route with no authorization, a handler that keeps running after the error
response, a goroutine with no owner, a transaction held across a remote
call, a timeout that does not exist, an error that tells the client too much
or the caller too little, a test that cannot fail. With only `go vet` — the
common case — the linter rows are this review's job too, and
`scripts/scan.sh` covers the mechanical part.

## Severity floor

Always 🔴, regardless of effort:

- a new or changed route with no authorization middleware, or a handler that
  reaches an object by id with no check that the caller may act on it
- identity read from a header, a form field, a query value or the body
- a query built by formatting or concatenating a value into the SQL text
- a handler that writes an error response and does not return
- a goroutine started from a handler with no owner: nothing stops it, waits
  for it or sees its error
- a multi-write operation with no transaction, or a remote call between
  `Begin` and `Commit`
- a secret, token, password or full request body in a log line or an error
  response
- user-controlled text passed through `template.HTML`, `template.JS`,
  `template.URL`, `templ.Raw` or `text/template`

A **[hard]** rule that is not on this list is 🟡, unless what it breaks in
this file is one of the lines above.

## 1. Authorization and identity — merge blocker

Go has no annotation on a handler. Read the line that registers the route.

- **[hard] The route is wrapped in the authorization middleware**, the way
  its siblings are, or mounted under a group that is. A new route outside it
  is 🔴 unless the project layer lists the path as public.
- **[hard] Signed in is not allowed.** A handler that takes an id checks that
  this caller may act on that object: an owner or tenant predicate in the
  query, or the project's policy helper. Always 🔴.
- **[hard] The identity comes from the request context**, through the
  project's accessor. A `user_id`, `org_id` or `role` read from a header, a
  form field, a query value or a decoded body is the finding.
- **[hard] List queries are scoped in SQL.** Filtering in Go after the query
  loads other people's rows first, and a missing filter returns them.
- **[hard] A missing object and a forbidden one answer the way the siblings
  do.** A different answer for "exists but not yours" tells the caller which
  ids exist; follow the project layer's rule.
- **[hard] The context key is an unexported type**, and one accessor reads
  it. A string key collides; a type assertion without `, ok` panics on a
  public route.
- **[context] Middleware order.** Recovery and request id first, then
  authentication, then authorization, then the handler. A limit or a CSRF
  check placed after the handler's group does not run.

## 2. Errors

- **[hard] Every error is handled once**: returned with context, or logged
  and turned into a response. Logged and returned is two log lines for one
  failure; neither is a failure nobody sees.
- **[hard] `_` never discards an error** without a reason a reader can check.
  That includes `Close` on a file that was written and `Decode` of a body.
- **[hard] Wrapping uses `%w`, with what was being attempted**:
  `fmt.Errorf("load cart %s: %w", id, err)`. `%v` cuts the chain and
  `errors.Is` stops matching above this line. Wrap with `%v` on purpose only
  where the cause must not become part of the package's API, and then map it
  to the package's own error.
- **[hard] Errors are compared with `errors.Is` and `errors.As`** (or
  `errors.AsType` from 1.26), never with `==`, a type assertion or a match on
  the message text.
- **[hard] The client gets the project's error response, not `err.Error()`.**
  A driver message names tables, columns and hosts.
- **[hard] A handler returns after it writes an error.** Without the
  `return` it runs on with a zero value and writes a second response.
- **[hard] A function that returns `error` never returns a typed nil
  pointer.** `var e *MyError; return e` is not `nil` to the caller.
- **[hard] No `panic`, `log.Fatal` or `os.Exit` outside `main`** for a
  failure a caller could handle. `log.Fatal` skips every deferred call.
- **[hard] No token, password, credential, cookie or full request body in a
  log line**; personal data follows the project layer's rule.
- **[prefer] Sentinel errors and error types are named by the package that
  owns the failure**, and the mapping to a status lives in one place.
- **[prefer] Structured logging through the project's logger** with
  key-value pairs, and the error as a value, not formatted into the message.

## 3. Context, deadlines and shutdown

- **[hard] `ctx` is the first parameter** of anything that does I/O, and it
  is the caller's. `context.Background()` or `context.TODO()` below `main`
  drops the deadline and the cancellation.
- **[hard] A context is not stored in a struct** and not put in a
  package-level variable.
- **[hard] Every query and remote call takes the context**: `QueryContext`,
  `ExecContext`, `BeginTx`, `http.NewRequestWithContext`.
- **[hard] The `cancel` of `WithTimeout` / `WithCancel` is deferred.**
- **[hard] The server has timeouts.** `http.ListenAndServe` and a bare
  `http.Server{}` have none: set `ReadHeaderTimeout` at least, and
  `ReadTimeout`, `WriteTimeout` and `IdleTimeout` unless the server streams.
  A streaming handler (SSE) lifts its own write deadline with
  `http.NewResponseController`.
- **[hard] An outbound client has a timeout** and is reused.
  `http.DefaultClient`, `http.Get` and `&http.Client{}` wait forever. One
  client per request also throws away the connection pool.
- **[hard] Work that outlives the request does not use the request
  context.** It is cancelled when the handler returns. Take
  `context.WithoutCancel(ctx)` with a new timeout, and hand the goroutine to
  something that waits for it at shutdown.
- **[hard] `main` shuts down in order**: `signal.NotifyContext`, then
  `Server.Shutdown` with a deadline, then wait for the workers, then close
  the pool. `ListenAndServe` returning `http.ErrServerClosed` is not a
  failure.
- **[context] A loop that waits uses a timer and `ctx.Done()` in a
  `select`**, not `time.Sleep`.
- **[context] Values in a context** are request-scoped data that crosses API
  boundaries — the caller, a request id. A dependency or an optional
  parameter passed that way is hidden coupling.

## 4. Concurrency

- **[hard] Every goroutine has an owner.** For each `go` statement, name what
  stops it, what waits for it and where its error goes. An `errgroup` with a
  context, or `sync.WaitGroup.Go` (1.25), answers all three. None of them
  answered is a leak.
- **[hard] A panic in a goroutine kills the process.** The recovery
  middleware covers only the handler's own goroutine.
- **[hard] Fan-out is bounded**: `errgroup.SetLimit`, a worker pool, a
  semaphore. One goroutine per row or per request item is unbounded memory
  and an unbounded number of connections.
- **[hard] Shared state is guarded.** A map, a slice, a counter or a struct
  field written by more than one goroutine needs a mutex, an atomic or a
  single owner goroutine. A package-level `map` in a server is written by
  every request. A concurrent map write is a fatal error, not a panic that
  can be recovered.
- **[hard] A mutex guards named fields, sits next to them, and is not
  copied.** A value receiver on a struct with a mutex copies it.
- **[hard] No lock is held across I/O** — a query, a remote call, a channel
  send that can block.
- **[hard] A send can always complete or be abandoned.** A goroutine that
  sends its result on an unbuffered channel blocks forever when the receiver
  left on a timeout. Buffer for the result, or `select` on `ctx.Done()`.
- **[hard] A channel is closed by its sender, once.**
- **[context] `sync.Once`, `OnceValue`** for lazy set-up; a hand-rolled
  check-then-set is a race.
- **[context] A new goroutine where a plain call would do.** Concurrency the
  measurement did not ask for is the finding.

## 5. HTTP handlers and responses

- **[hard] Handlers are thin**, the way the siblings are: decode, validate,
  call, respond. Business branching and SQL belong where the project layer
  puts them.
- **[hard] The body has a size limit.** `http.MaxBytesReader` in the decode
  helper or in a middleware. `io.ReadAll(r.Body)` with no limit lets one
  request take the memory.
- **[hard] Input is decoded into a request struct, never into a stored
  model.** Decoding straight into the struct the store writes lets the
  client set its id, owner, role and status. Always 🔴 when a server-owned
  field is reachable.
- **[hard] Decoded input is validated** before it is used, through the
  project's validator. A JSON decoder accepts a missing field as the zero
  value: a `bool` or an `int` cannot tell "absent" from `false` or `0`; use a
  pointer where that matters.
- **[context] On Go 1.27 a decoder change is a contract change.** Code moved
  to `encoding/json/v2` starts rejecting duplicate names and invalid UTF-8
  that v1 accepted. Name the clients that send them, or say there are none.
- **[hard] Status codes match the siblings.** A failure never answers 200.
  `WriteHeader` is called once, and headers are set before it: a header set
  after the first write is dropped.
- **[hard] The method is in the route** (`"POST /cart"`, a router method),
  not checked by hand in some handlers and forgotten in others.
- **[hard] GET does not change state.** `http.CrossOriginProtection` and
  `SameSite=Lax` both let a cross-site GET through.
- **[hard] A state-changing route has the project's CSRF defence**, when the
  session is a cookie. gorilla/csrf is not one: CVE-2025-47909 has no fixed
  release.
- **[hard] HTML goes through `html/template` or templ.** `text/template`
  escapes nothing. `template.HTML`, `template.JS`, `template.URL`,
  `template.HTMLAttr` and `templ.Raw` emit the value as written: each use
  needs a value the server made, and user text never qualifies. Always 🔴
  otherwise.
- **[hard] Templates are parsed once at start-up**, not inside a handler.
- **[prefer] A template is rendered to a buffer, then written.** Executed
  straight into the `ResponseWriter`, an error halfway leaves half a page
  with status 200.
- **[hard] A session cookie is `Secure`, `HttpOnly` and `SameSite`.**
- **[context] A POST a client may retry** (payment, registration, message
  send) needs a duplicate guard: a unique constraint or an idempotency key.

In an htmx application, also:

- **[hard] A URL that answers a fragment or a page depending on `HX-Request`
  sets `Vary: HX-Request`.** Without it a cache, or the browser on Back,
  serves the fragment as the page.
- **[hard] A history restore gets the full page.** htmx 2: check
  `HX-History-Restore-Request`, or the project turns off
  `historyRestoreAsHxRequest`. htmx 4: branch on `HX-Request-Type`, `full`
  or `partial`.
- **[hard] The handler answers HTML, not JSON**, and the fragment it returns
  is the one the template's `hx-target` expects.
- **[hard] A redirect after an htmx request uses `HX-Redirect` or
  `HX-Location`.** The browser follows a 3xx inside the request and the
  whole page lands in the target. A boosted link or form is the exception.
- **[hard] A validation failure answers the status the project's htmx
  version swaps.** htmx 2 does not swap 4xx or 5xx unless `responseHandling`
  or the response-targets extension says so; htmx 4 swaps them. A 422 with
  the form in it shows nothing on a default htmx 2.
- **[hard] Header names match the htmx version.** htmx 4 sends `HX-Source`
  where 2 sent `HX-Trigger`, sends `HX-Target` as `tag#id`, and dropped
  `HX-Trigger-Name` and the `HX-Trigger-After-Swap` / `-After-Settle`
  response headers. Status 286 stops polling in htmx 2 only.
- **[hard] `hx-delete` parameters are in the query string**, in both
  versions: read `r.URL.Query()`, not the form.

## 6. Data access

- **[hard] Values are query arguments.** `fmt.Sprintf` or `+` into SQL is an
  injection. An identifier that cannot be an argument — a sort column, a
  table — comes from a fixed list the code owns. Always 🔴.
- **[hard] Rows are closed and checked**: `defer rows.Close()` after the
  error check, `rows.Err()` after the loop. Without `Err` a failure halfway
  looks like a short list. pgx `CollectRows` and sqlc do both.
- **[hard] `QueryRow` handles `sql.ErrNoRows`** (`pgx.ErrNoRows`) with
  `errors.Is` and maps it to the project's not-found error; it is not a 500.
- **[hard] A multi-write operation is one transaction**, and `defer
  tx.Rollback()` follows `BeginTx` on the next line. An early return without
  it holds the connection and its locks.
- **[hard] Inside a transaction every statement runs on the `tx`.** A call
  on the pool there runs on another connection, outside the transaction, and
  can wait on the locks the transaction holds.
- **[hard] No remote call between `Begin` and `Commit`** — HTTP, object
  store, mail, queue. The connection is held for the round trip, and the
  remote effect stays when the commit fails. Call first and then begin, or
  commit and then call. Always 🔴.
- **[hard] The `Commit` error is checked.** A failed commit is a failed
  operation.
- **[hard] Every list query has a limit**, with a maximum the client cannot
  raise, and a unique last sort key: sorting on a non-unique column alone
  skips or repeats rows between pages.
- **[hard] No query per row in a loop.** Join, use `= ANY($1)`, or batch.
- **[hard] The pool has limits**: `SetMaxOpenConns`, `SetConnMaxLifetime`
  for `database/sql`; `MaxConns` for pgxpool. The `database/sql` default is
  unlimited.
- **[prefer] A nullable column scans into `sql.Null[T]` or a pointer**; a
  plain `string` fails on the first NULL.
- **[context] `SELECT *`** breaks a `Scan` when a column is added.
- **[context] Money** is integer minor units or a decimal type, never
  `float64`. **Time** is stored in UTC, and `now` comes from the project's
  clock when it has one.

## 7. Tests

Every new handler and service has a test.

- **[hard] The test covers the invariant, not just the happy path** — the
  caller with no session, the object of another owner, the invalid body, the
  miss, the rollback.
- **[hard] The test can fail.** It compares a result with `t.Error` /
  `t.Fatal`, `cmp.Diff` or the project's assertion library. A test that only
  calls the function, or only checks `err == nil`, proves little.
- **[hard] A handler is tested through HTTP**: `httptest.NewRecorder` or a
  test server, through the router with its middleware, so the route, the
  method and the authorization are part of what is tested.
- **[hard] The database in a test is the real engine**, through the
  project's fixture. sqlmock passes on a query the database rejects.
- **[hard] No `time.Sleep` to wait for a goroutine.** Use
  `testing/synctest` (1.25), a channel, or a fake clock.
- **[hard] `t.Fatal` is called only from the test goroutine.**
- **[prefer] Table-driven with `t.Run`**, one name per case, when the cases
  differ only in data. A table that needs an `if` per case is two tests.
- **[prefer] Helpers call `t.Helper()` and register `t.Cleanup`**; the test
  uses `t.Context()` (1.24) and `t.TempDir()`.
- **[context] `t.Parallel()` with shared state** — a package variable, the
  environment, one database schema — is a flaky test.
- **[context] An interface and a mock for a dependency the test could run
  for real.** The mock repeats the implementation's assumptions.
- **[context] Missing test** — `scripts/scan.sh` reports it. Report it for
  the file under review only; do not turn the review into a backlog.

## 8. Structure, consistency and version

- **[hard] Reinvention** — re-implements a render helper, an error mapping,
  a decode helper, a transaction helper, a paging helper or a test fixture
  that the project already has, or something the standard library provides
  at the module's `go` version. **Run `scripts/inventory.sh` before judging
  this.** Name the replacement by its real package and function.
- **[hard] No API older or newer than the `go` line** — see the baseline.
  Generated Go is written in the style of its training corpus. On a current
  module these are findings when no analyzer already fails on them:
  `io/ioutil`; `golang.org/x/exp/slices`, `maps` or `slog`; `rand.Seed`;
  `x := x` in a loop; `wg.Add(1)` with `go func` and `defer wg.Done()` where
  `wg.Go` exists; `sort.Slice` where `slices.SortFunc` exists; a hand-rolled
  `contains`, `min` or pointer helper; `for i := 0; i < b.N; i++`;
  `go.uber.org/automaxprocs` on 1.25; a `tools.go` of blank imports on 1.24.
  One finding for the file, not one per line; `go fix ./...` (1.26) rewrites
  most of them.
- **[hard] No new dependency for what the standard library does at this
  version**: gorilla/mux or chi for plain method-and-path routing (1.22),
  `github.com/pkg/errors` (`%w`), `google/uuid` in new code (1.27), a logging
  library beside `slog`. The project's existing choice stands — see Do NOT
  report.
- **[hard] Layering matches the siblings** — which package holds handlers,
  which holds SQL, which way the imports point. `internal/` for what is not
  an API. A new package named `util`, `common` or `helpers` is a finding.
- **[prefer] An interface is declared where it is used**, by the consumer,
  with the methods that consumer calls. An interface beside its only
  implementation, made "for testing", is a finding when nothing substitutes
  it.
- **[prefer] Accept interfaces, return concrete types.**
- **[hard] No mutable package-level state and no `init()` that does work.**
  Dependencies are built in `main` and passed in.
- **[hard] Configuration is read once at start-up** into a struct, validated,
  and passed in. `os.Getenv` inside a handler or a service is a finding.
- **[context] Generics, an option pattern, a factory or a wrapper** is a
  finding only when the siblings do not have it and nothing in the diff
  needs it.
- **[context] A generated file was edited by hand**, or its source changed
  and the generated file did not: `*_templ.go`, sqlc output, protobuf.

## 9. Comment quality

<!-- comment-rules:start — the short form of comment-cleanup/RULES.md, the same text in each checklist -->
The default is no comment; a rename, an extracted function or a type comes
first.

- **[hard] Delete comments that restate the code or describe the change** —
  "now uses", "added", "fixed", a banner, a step number, a doc comment that
  repeats the signature or the types.
- **[hard] Delete commented-out code** — git remembers it.
- **[hard] No ticket, PR, SHA, date or link in a comment** — the code does
  not know the outside world; those live in commit messages and PR bodies.
- **[prefer] A comment that stays is one line and one of four kinds** — why
  this and not the obvious alternative, an outside constraint, a warning
  about what breaks if edited, a workaround with its removal condition. On a
  constant or a field: only units, where a number comes from, a domain term,
  or what null means, and only when a rename cannot say it.
- **[context] A missing comment** is a finding only for one of those four
  kinds, with the consequence named.
- **[context] A comment the diff removed** that was still true and one of the
  four kinds — restore it.
- **[hard] A lint, type or check suppression states its reason.**
<!-- comment-rules:end -->

In this stack:

- A restated line reads like `// loop over items` or `// return the error`,
  or is a doc comment that repeats the signature. Go asks for a doc comment
  on every exported name; one that only restates the name satisfies the
  linter and nothing else — say what the caller must know, or unexport.
- A query that skips the tenant or owner filter on purpose, a goroutine that
  outlives its request, and a call that must stay outside the transaction
  each need a comment of one of the four kinds.
- The suppression is a `//nolint:<linter>` and it names the linter and the
  reason; a bare `//nolint` is a finding.
- `//go:build`, `//go:generate`, `//go:embed` and `//go:fix inline` are
  directives, not comments.

---

## Do NOT report

- Anything a configured analyzer already fails the build on (see Tooling
  coverage).
- Restating the project's instructions file as if it were a finding.
- A violation in code the change did not touch.
- A migration to another library or a newer Go version — replacing the
  project's router, logger, driver, ORM or assertion library, or moving the
  `go` line.
- Style `gofmt` owns, and naming taste beyond what the siblings do.
- `time.After` in a loop on a module at `go 1.23` or later.
- Features and ceilings the project layer lists as deferred or known.
- Missing end-to-end tests. This rubric reviews one unit.
- A speculative failure. If the finding needs "might" or "could, if", find the
  line that makes it real or drop it.
