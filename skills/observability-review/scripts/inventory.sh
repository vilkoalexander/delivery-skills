#!/usr/bin/env bash
# Live observability inventory for observability-review. Prints what plumbing
# exists — logger, correlation, redaction, filters, tracing, health, metrics
# — so the review judges against what the project has, not a generic ideal.
#
# Usage: scripts/inventory.sh [root]
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

limit="${INVENTORY_LIMIT:-40}"

cap() {
  awk -v limit="$limit" '
    NR <= limit { print; next }
    END { if (NR > limit) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR - limit, limit }
  '
}

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
if [ ! -d "$root" ]; then
  echo "root not found: $root" >&2
  exit 1
fi
cd "$root" || exit 1
echo "root: $root"

# Lines of backend source that match, without vendored, built or test files.
backend_lines() {
  grep -rnE "$1" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --include='*.ts' . 2>/dev/null | grep -vE 'node_modules|/dist/|\.spec\.|\.test\.'
}

# section TITLE REGEX — prints the matching lines under a heading
section() {
  echo
  echo "## $1"
  backend_lines "$2" | sed 's/^/  /' | cap
}

echo
echo "## Logging libraries"
node -e '
  const pkg = require("./package.json");
  const deps = { ...pkg.dependencies, ...pkg.devDependencies };
  const relevant = /pino|winston|bunyan|nestjs-cls|opentelemetry|sentry|dd-trace|newrelic|terminus|prom-client|prometheus|datadog/;
  for (const name of Object.keys(deps)) {
    if (relevant.test(name)) console.log("  " + name, deps[name]);
  }
' 2>/dev/null

section "Logger setup and injection" \
  'LoggerModule\.forRoot|WinstonModule|new Logger\(|PinoLogger|@InjectPinoLogger|app\.useLogger|bufferLogs'
section "Redaction" \
  'redact|REDACT|censor'
section "Correlation id" \
  'ClsModule|ClsService|AsyncLocalStorage|reqId|requestId|correlationId|x-request-id|x-correlation-id|traceId'
section "Exception filters and interceptors" \
  '@Catch\(|implements ExceptionFilter|implements NestInterceptor|LoggingInterceptor|useGlobalFilters|useGlobalInterceptors|APP_FILTER|APP_INTERCEPTOR'
section "Error reporting and tracing" \
  'Sentry\.init|captureException|NodeSDK|@opentelemetry|tracer\.startActiveSpan|startSpan\(|dd-trace|tracer\.init'
section "Health and metrics" \
  'TerminusModule|HealthCheckService|HealthIndicator|@HealthCheck|PrometheusModule|prom-client|new Counter\(|new Histogram\(|makeCounterProvider|makeHistogramProvider'

echo
echo "## console.* in backend sources (should be zero)"
console_calls=$(backend_lines 'console\.(log|error|warn|info|debug)\(' | grep -cvE 'scripts/|/cli/')
echo "  count: $console_calls"
