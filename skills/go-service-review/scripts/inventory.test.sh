#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo shop
mkdir -p cmd/server internal/cart internal/order internal/platform/respond internal/middleware internal/testutil vendor/x .github/workflows
cat > go.mod <<'MOD'
module shop

go 1.27

toolchain go1.27.4

require (
	github.com/a-h/templ v0.3.1118
	github.com/jackc/pgx/v5 v5.8.0
	github.com/gorilla/csrf v1.7.3
	example.com/unrelated v1.0.0
)
MOD
printf 'version: "2"\nlinters:\n  enable:\n    - bodyclose\n    - errorlint\n' > .golangci.yml
printf 'steps:\n  - run: go vet ./...\n  - run: go test -race ./...\n' > .github/workflows/ci.yml
echo 'package main' > cmd/server/main.go
cat > cmd/server/routes.go <<'GO'
package main

func routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /cart", cart.Show)
	mux.Handle("POST /cart", requireUser(cart.Add))
}
GO
cat > internal/cart/handler.go <<'GO'
package cart

var ErrEmpty = errors.New("cart: empty")

type PriceError struct{}

func Show(w http.ResponseWriter, r *http.Request) { slog.Info("show", "q", r.URL.Query().Get("q"), "s", http.StatusBadGateway) }

type Handler struct{ payments *PaymentsClient }

type Prices struct{ client *http.Client }
GO
echo 'package cart' > internal/cart/cart_templ.go
echo 'package order' > internal/order/service.go
printf 'package order\n\nfunc newStore(t *testing.T) {\n\tt.Helper()\n}\n' > internal/order/service_test.go
printf 'package respond\n\nfunc HTML(w http.ResponseWriter) {}\nfunc Error(w http.ResponseWriter) {}\nfunc private() {}\n' > internal/platform/respond/respond.go
printf 'package middleware\n\nfunc RequireUser(next http.Handler) http.Handler { return next }\n' > internal/middleware/auth.go
echo 'package testutil' > internal/testutil/db.go
echo 'package x' > vendor/x/x.go

out=$(bash "$inventory" .)
versions=$(under 'versions')
sees   "the go line"                    '^  go 1\.27$' "$versions"
sees   "the toolchain line"             'toolchain go1\.27\.4' "$versions"
sees   "templ with its version"         'a-h/templ v0\.3\.1118' "$versions"
sees   "the driver"                     'jackc/pgx/v5 v5' "$versions"
misses "an unrelated module"            'unrelated' "$versions"
analyzers=$(under 'analyzers')
sees   "the lint config"                'golangci-lint  \.golangci\.yml' "$analyzers"
sees   "a linter the config names"      'bodyclose +named' "$analyzers"
sees   "one it does not"                'rowserrcheck +not named' "$analyzers"
misses "a version 2 config is fine"     'not version 2' "$analyzers"
sees   "the race detector in CI"        '-race +in the build or CI' "$analyzers"
sees   "no govulncheck"                 'govulncheck +not in the build or CI' "$analyzers"
packages=$(under 'packages')
sees   "a package with a test"          'internal/order +files:1 +tests:1' "$packages"
sees   "a generated file is not counted" 'internal/cart +files:1 +tests:0' "$packages"
misses "vendor is not a package"        'vendor' "$packages"
shared=$(under 'shared primitives')
sees   "exported helpers by name"       'internal/platform/respond/respond.go +Error HTML' "$shared"
misses "an unexported one"              'private' "$shared"
sees   "the error value and type"       'ErrEmpty|PriceError' "$(under 'error values and types')"
middleware=$(under 'middleware')
sees   "the middleware"                 'RequireUser' "$middleware"
sees   "the route count and file"       'routes registered: 2 +in: cmd/server/routes.go' "$middleware"
sees   "no CSRF defence in the code"    'CSRF defence: none found' "$middleware"
sees   "the remote client"              'http\.Client' "$(under 'remote clients')"
sees   "a client type of the project"   'PaymentsClient' "$(under 'remote clients')"
misses "a status constant is not a client" 'StatusBadGateway' "$(under 'remote clients')"
sees   "the logger in use"              'slog' "$(under 'logging')"
helpers=$(under 'test helpers')
sees   "a helper"                       'internal/order/service_test.go' "$helpers"
sees   "the fixture package"            'internal/testutil/db.go' "$helpers"
untested=$(under 'no test in the package')
sees   "a package with no test"         'internal/cart' "$untested"
misses "a package with one"             'internal/order' "$untested"
misses "cmd is not required to"         'cmd/server' "$untested"

echo "# REVIEW_FILES, a version 1 lint config, no module"
out=$(REVIEW_FILES="internal/order/service.go internal/middleware/auth.go" bash "$inventory" .)
untested=$(under 'no test in the packages of REVIEW_FILES')
sees   "only the packages under review" 'internal/middleware' "$untested"
misses "not the rest"                   'internal/cart' "$untested"
printf 'linters:\n  enable:\n    - bodyclose\n' > .golangci.yml
out=$(bash "$inventory" .)
sees   "a version 1 config is named"    'config is not version 2' "$out"
cd internal/cart && out=$(bash "$inventory") && cd ../..
sees   "the root is found from below"   "^root: .*/shop$" "$out"
mkdir -p "$tmp/empty"
has "no go.mod"                         1 'go.mod not found' bash "$inventory" "$tmp/empty"

finish
