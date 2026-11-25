# Go service review — project layer

Loaded by `go-service-review` at step 2. Also the source for the scan
env: `HANDLER='<http\.ResponseWriter|\*app\.Context>'` `REMOTE_CALL='<\.Do\(|s3\.|mailer\.>'`.
Everything in `<angle brackets>` is a placeholder — replace it or delete the row.

## Stack

Go `<1.27>`. Router: `<net/http ServeMux | chi>`. Data access: `<pgx + sqlc | database/sql>`. Templates: `<templ | html/template>`. Logger: `<slog>`.
Analyzers in the build: `<go vet only | golangci-lint v2: standard + errorlint, bodyclose, rowserrcheck, gosec, modernize>`. `<go test -race in CI | not>`.

## Authorization

- Routes are registered in: `<cmd/server/routes.go>`.
- A route is authorized by: `<the RequireUser middleware around the group | per-route mw.Require(perm)>`.
- Object-level check: `<an owner_id predicate in every store query | policy.Can(ctx, user, "order:read", id)>`.
- Identity is read with: `<auth.UserFrom(ctx)>`. Never from `<the X-User-Id header>`.
- An object the caller may not see answers: `<404>`.
- Public on purpose: `</healthz, /login, /static/*>`.
- CSRF defence: `<http.CrossOriginProtection on the root mux | a token | none: API with bearer tokens>`.

## Layout

| Kind | Lives in |
| --- | --- |
| Handler | `<internal/<feature>/handler.go>` |
| Service | `<internal/<feature>/service.go | none: handler calls the store>` |
| Store / queries | `<internal/<feature>/store.go | db/queries/*.sql + sqlc>` |
| Templates | `<internal/<feature>/*.templ | web/templates>` |
| Imports point | `<cmd → internal/feature → internal/platform; never feature → feature>` |

## Reference implementations

| Concern | Read |
| --- | --- |
| Handler shape, decoding, error response | `<internal/cart/handler.go>` |
| Transaction with a deferred rollback | `<internal/order/service.go>` |
| Remote call kept outside the transaction | `<…>` |
| Background work that outlives a request | `<…>` |
| Handler test through the router | `<internal/cart/handler_test.go>` |
| Store test on the real engine | `<internal/order/store_test.go>` |

## Shared primitives — do not rebuild

| The file hand-rolls… | Use |
| --- | --- |
| `http.Error` with a status | `<respond.Error(w, r, err)>` |
| Render to a buffer and write | `<render.HTML(w, r, component)>` |
| A branch on `HX-Request` | `<render.Page(w, r, page, fragment)>` |
| A context value and a type assertion | `<auth.UserFrom(ctx)>` |
| Decode, limit and validate a body | `<httpx.Decode(w, r, &in)>` |
| `Begin` / `Rollback` / `Commit` | `<store.InTx(ctx, func(tx) error)>` |
| A "not found" error | `<apperr.NotFound>` |
| A container in a test | `<testutil.NewDB(t)>` |

## Transactions and remote calls

- Boundary: `<the service method | store.InTx>`.
- Remote clients: `<the payments client, S3, the mailer>` — `<called before the transaction | from the outbox worker after commit>`.

## Personal data

Never in a log line: `<email, phone, token, session id>`.

## Known ceilings — do not recommend past these

- `<the health endpoint queries the pool with no caller identity, by design>`
- `<one ceiling per line, stated as a rule a reviewer can check>`

## Deferred — never propose as gaps

`<feature, feature, …>`
