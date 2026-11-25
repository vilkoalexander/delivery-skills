#!/usr/bin/env bash
# Live backend inventory for go-service-review: Go version, libraries that
# change the rules, analyzers, packages, shared primitives that already
# exist, middleware, remote clients and test helpers.
#
# Usage: scripts/inventory.sh [root]
#   root is the directory holding go.mod. Auto-detected from the current
#   directory upward when omitted.
# Env:   REVIEW_FILES  space-separated files under review; limits the
#                      missing-test check to their packages
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

# Output is bounded: INVENTORY_LIMIT lines per section (default 40), overflow
# reported as a count.
limit="${INVENTORY_LIMIT:-40}"

cap() {
  awk -v limit="$limit" '
    NR <= limit { print; next }
    END { if (NR > limit) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR - limit, limit }
  '
}

indent() {
  sed 's/^/  /'
}

or_none() {
  awk '{ print; seen = 1 } END { if (!seen) print "  none" }'
}

root="${1:-}"
if [ -z "$root" ]; then
  dir=$PWD
  while [ "$dir" != / ]; do
    if [ -f "$dir/go.mod" ]; then root=$dir; break; fi
    dir=$(dirname "$dir")
  done
fi
if [ -z "$root" ] || [ ! -f "$root/go.mod" ]; then
  echo "go.mod not found — pass its directory: inventory.sh <dir>" >&2
  exit 1
fi
cd "$root" || exit 1
echo "root: $root"

# Every hand-written Go source: no vendored, generated or testdata file.
all_sources=$(find . -name '*.go' -not -path '*/vendor/*' -not -path '*/node_modules/*' -not -path '*/testdata/*' \
  -not -name '*_templ.go' -not -name '*.pb.go' -not -name '*_gen.go' -not -name '*.sql.go' 2>/dev/null | sed 's|^\./||' | sort)
main_sources=$(printf '%s\n' "$all_sources" | grep -vE '_test\.go$' || true)
test_sources=$(printf '%s\n' "$all_sources" | grep -E '_test\.go$' || true)

main_files=()
test_files=()
while IFS= read -r file; do [ -n "$file" ] && main_files+=("$file"); done <<< "$main_sources"
while IFS= read -r file; do [ -n "$file" ] && test_files+=("$file"); done <<< "$test_sources"

# /dev/null keeps grep off stdin when the list is empty.
in_main()  { grep "$@" ${main_files[@]+"${main_files[@]}"} /dev/null 2>/dev/null; }
in_tests() { grep "$@" ${test_files[@]+"${test_files[@]}"} /dev/null 2>/dev/null; }

echo
echo "=== versions (the go line decides which language rules apply)"
{
  grep -E '^(go|toolchain) ' go.mod
  grep -oE '(github\.com/(a-h/templ|go-chi/chi(/v[0-9]+)?|gin-gonic/gin|labstack/echo(/v[0-9]+)?|gofiber/fiber(/v[0-9]+)?|gorilla/(mux|csrf|sessions)|jackc/pgx(/v[0-9]+)?|jmoiron/sqlx|sqlc-dev/sqlc|stretchr/testify|google/uuid|pkg/errors|donseba/go-htmx|angelofallars/htmx-go|alexedwards/scs(/v[0-9]+)?|golang-jwt/jwt(/v[0-9]+)?|testcontainers/testcontainers-go|DATA-DOG/go-sqlmock|pressly/goose(/v[0-9]+)?|golang-migrate/migrate(/v[0-9]+)?)|gorm\.io/gorm|entgo\.io/ent|go\.uber\.org/(zap|automaxprocs)|github\.com/rs/zerolog|filippo\.io/csrf|golang\.org/x/(sync|exp)) v[^ ]+' go.mod
} | sort -u | indent | cap | or_none

echo
echo "=== analyzers (absent = this review's job)"
lint_config=$(ls .golangci.yml .golangci.yaml .golangci.toml .golangci.json 2>/dev/null | head -1)
if [ -n "$lint_config" ]; then
  echo "  golangci-lint  $lint_config"
  grep -qE '^version: *"?2' "$lint_config" || echo "  golangci-lint  config is not version 2 — golangci-lint v2 refuses it"
  for linter in bodyclose rowserrcheck sqlclosecheck noctx contextcheck errorlint nilerr gosec modernize sloglint forcetypeassert musttag; do
    if grep -qE "(^|[^a-z])$linter([^a-z]|$)" "$lint_config"; then
      printf '  %-14s named\n' "$linter"
    else
      printf '  %-14s not named\n' "$linter"
    fi
  done
else
  echo "  golangci-lint  absent"
fi
ci_text=$(cat Makefile Taskfile.yml Taskfile.yaml justfile .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml 2>/dev/null)
for tool in 'go vet' staticcheck govulncheck 'go fix' '-race' 'templ generate' 'sqlc (generate|diff|vet)'; do
  if grep -qE -- "$tool" <<< "$ci_text"; then
    printf '  %-14s in the build or CI\n' "$tool"
  else
    printf '  %-14s not in the build or CI\n' "$tool"
  fi
done

echo
echo "=== packages"
printf '%s\n' "$all_sources" | awk -F/ '
  {
    dir = $0
    if (NF == 1) dir = "."; else sub(/\/[^\/]+$/, "", dir)
    if ($NF ~ /_test\.go$/) tests[dir]++; else files[dir]++
    seen[dir] = 1
  }
  END { for (dir in seen) printf "  %-44s files:%-3d tests:%d\n", dir, files[dir], tests[dir] }
' | sort | cap | or_none

echo
echo "=== shared primitives — do not rebuild"
shared='(^|/)(platform|httpx|httputil|web|render|respond|response|apperr|apperror|errs|errors|xerrors|validate|validation|middleware|authz?|session|pagination|paging|money|clock|db|dbx|store|testutil|testhelper|testsupport|fixtures?|htmx)/[^/]+\.go$'
printf '%s\n' "$main_sources" | grep -E -- "$shared" | while IFS= read -r file; do
  names=$(grep -hoE '^func (\([^)]*\) )?[A-Z][A-Za-z0-9]*' "$file" | sed -E 's/^func (\([^)]*\) )?//' | sort -u | head -8 | paste -sd' ' -)
  printf '  %-44s %s\n' "$file" "$names"
done | cap | or_none

echo
echo "=== error values and types"
in_main -hoE '^(var )?[[:space:]]*Err[A-Z][A-Za-z0-9]* += +(errors\.New|fmt\.Errorf)|^type [A-Z][A-Za-z0-9]*Error ' \
  | sed -E 's/^(var )?[[:space:]]*//; s/ += .*//' | sort -u | paste -sd' ' - | fold -s -w 100 | indent | or_none

echo
echo "=== middleware (authorization lives here and in the routes, not in the handler)"
in_main -noE 'func (\([^)]*\) )?[A-Za-z0-9]+\([^)]*\) (func\(http\.Handler\) http\.Handler|http\.Handler)|func (\([^)]*\) )?[A-Za-z0-9]+\(next http\.Handler[^)]*\)' \
  | sed -E 's/:[0-9]+:func (\([^)]*\) )?/  /; s/\(.*//' | sort -u | indent | cap | or_none
routes=$(in_main -hE '\.(HandleFunc|Handle|Get|Post|Put|Patch|Delete|GET|POST|PUT|PATCH|DELETE)\("([A-Z]+ )?/' | wc -l | tr -d ' ')
route_files=$(in_main -lE '\.(HandleFunc|Handle|Get|Post|Put|Patch|Delete|GET|POST|PUT|PATCH|DELETE)\("([A-Z]+ )?/' | paste -sd' ' -)
echo "  routes registered: $routes   in: ${route_files:-none}"
if in_main -qE 'CrossOriginProtection|csrf\.Protect|nosurf\.New|filippo\.io/csrf'; then
  in_main -lE 'CrossOriginProtection|csrf\.Protect|nosurf\.New|filippo\.io/csrf' | sed 's/^/  CSRF defence: /'
else
  echo "  CSRF defence: none found"
fi

echo
echo "=== remote clients in use (set REMOTE_CALL for scan.sh from these)"
in_main -hoE '\*?(http\.Client|s3\.Client|sqs\.Client|sns\.Client|minio\.Client|redis\.Client|kafka\.(Writer|Reader)|nats\.Conn|amqp\.Channel|smtp\.Client|grpc\.ClientConn)\b|[* ][A-Z][A-Za-z0-9]*(Client|Mailer|Gateway|Publisher|Notifier)\b' \
  | sed 's/^[* ]//' | sort | uniq -c | sort -rn | indent | cap | or_none

echo
echo "=== logging"
in_main -hoE '\b(slog|zap|zerolog|logrus|log)\.(Debug|Info|Warn|Error|Print|Fatal)[A-Za-z]*\(' \
  | sed -E 's/\..*//' | sort | uniq -c | sort -rn | indent | or_none

echo
echo "=== test helpers and fixtures"
{
  in_tests -lE 't\.Helper\(\)|testcontainers|httptest\.New(Server|TestServer)|func TestMain\('
  printf '%s\n' "$main_sources" | grep -E '(^|/)(testutil|testhelper|testsupport|fixtures?)/' || true
} | sort -u | indent | cap | or_none
mocked=$(in_tests -lE 'go-sqlmock|gomock|mockery' | wc -l | tr -d ' ')
echo "  test files that mock: $mocked"

echo
packages_without_a_test() {
  local dir
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    ls "$dir"/*_test.go > /dev/null 2>&1 || printf '  %s\n' "$dir"
  done
}
if [ -n "${REVIEW_FILES:-}" ]; then
  echo "=== no test in the packages of REVIEW_FILES (a new package needs one)"
  # shellcheck disable=SC2086
  candidates=$(printf '%s\n' $REVIEW_FILES | grep -E '\.go$' | grep -vE '_test\.go$' | sed -E 's|/[^/]+$||; s|^[^/]+\.go$|.|' | sort -u)
else
  echo "=== no test in the package (a new package here needs one)"
  candidates=$(printf '%s\n' "$main_sources" | grep -vE '(^|/)cmd/|^[^/]+$' | sed -E 's|/[^/]+$||' | sort -u)
fi
packages_without_a_test <<< "$candidates" | cap | or_none
