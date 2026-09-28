#!/usr/bin/env bash
# Live observability inventory for observability-review. Prints what plumbing
# exists — logger, correlation, redaction, filters, tracing, health, metrics
# — so the review judges against what the project has, not a generic ideal.
#
# Usage: scripts/inventory.sh [root]
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

LIMIT="${INVENTORY_LIMIT:-40}"
cap() { awk -v n="$LIMIT" 'NR<=n{print;next} END{if(NR>n) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR-n, n}'; }
g() { grep -rnE "$1" --include='*.ts' . 2>/dev/null | grep -vE 'node_modules|/dist/|\.spec\.|\.test\.' | sed 's/^/  /' | cap; }

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root" || exit 1
echo "root: $root"

echo; echo "## Logging libraries"
node -e 'const p=require("./package.json"),d={...p.dependencies,...p.devDependencies};for(const k of Object.keys(d))if(/pino|winston|bunyan|nestjs-cls|opentelemetry|sentry|dd-trace|newrelic|terminus|prom-client|prometheus|datadog/.test(k))console.log("  "+k,d[k])' 2>/dev/null

echo; echo "## Logger setup and injection"
g 'LoggerModule\.forRoot|WinstonModule|new Logger\(|PinoLogger|@InjectPinoLogger|app\.useLogger|bufferLogs' | head -"$LIMIT"

echo; echo "## Redaction"
g 'redact|REDACT|censor' 

echo; echo "## Correlation id"
g 'ClsModule|ClsService|AsyncLocalStorage|reqId|requestId|correlationId|x-request-id|x-correlation-id|traceId'

echo; echo "## Exception filters and interceptors"
g '@Catch\(|implements ExceptionFilter|implements NestInterceptor|LoggingInterceptor|useGlobalFilters|useGlobalInterceptors|APP_FILTER|APP_INTERCEPTOR'

echo; echo "## Error reporting and tracing"
g 'Sentry\.init|captureException|NodeSDK|@opentelemetry|tracer\.startActiveSpan|startSpan\(|dd-trace|tracer\.init'

echo; echo "## Health and metrics"
g 'TerminusModule|HealthCheckService|HealthIndicator|@HealthCheck|PrometheusModule|prom-client|new Counter\(|new Histogram\(|makeCounterProvider|makeHistogramProvider'

echo; echo "## console.* in backend sources (should be zero)"
grep -rnE 'console\.(log|error|warn|info|debug)\(' --include='*.ts' . 2>/dev/null | grep -vE 'node_modules|/dist/|\.spec\.|\.test\.|scripts/|/cli/' | wc -l | sed 's/^/  count: /'
