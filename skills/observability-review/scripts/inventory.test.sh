#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo project
mkdir -p src/health scripts node_modules/dep dist
cat > package.json <<'JSON'
{ "dependencies": { "nestjs-pino": "4.0.0", "@sentry/node": "8.0.0", "express": "4.0.0" },
  "devDependencies": { "prom-client": "15.0.0" } }
JSON
cat > src/main.ts <<'TS'
LoggerModule.forRoot({ pinoHttp: { redact: ['req.headers.authorization'] } });
ClsModule.forRoot({ middleware: { generateId: true } });
app.useGlobalFilters(new AllExceptionsFilter());
Sentry.init({ dsn });
console.log('booted');
TS
echo "@Controller() class H { constructor(private health: HealthCheckService) {} }" > src/health/health.controller.ts
echo "const requestId = cls.getId();"                 > src/health/context.ts
echo "console.log('in a spec'); new Logger('Spec');"  > src/main.spec.ts
echo "console.log('a script');"                       > scripts/seed.ts
echo "new Logger('Dep'); console.log('dep');"         > node_modules/dep/index.ts
echo "new Logger('Dist'); console.log('dist');"       > dist/main.ts


out=$(bash "$inventory")
eq   "exits 0"                 "$?" 0
sees "names the root"          "^root: $tmp/project$" "$out"

libs=$(under "Logging libraries")
sees   "logging library"       '^  nestjs-pino 4.0.0$' "$libs"
sees   "error reporting"       '^  @sentry/node 8.0.0$' "$libs"
sees   "dev dependency"        '^  prom-client 15.0.0$' "$libs"
misses "unrelated dependency"  'express' "$libs"

sees "logger setup"            '^  ./src/main.ts:1:LoggerModule.forRoot' "$(under 'Logger setup and injection')"
sees "redaction"               '^  ./src/main.ts:1:' "$(under 'Redaction')"
sees "correlation id"          '^  ./src/main.ts:2:ClsModule' "$(under 'Correlation id')"
sees "exception filters"       '^  ./src/main.ts:3:' "$(under 'Exception filters and interceptors')"
sees "error reporting setup"   '^  ./src/main.ts:4:Sentry.init' "$(under 'Error reporting and tracing')"
sees "health"                  '^  ./src/health/health.controller.ts:1:' "$(under 'Health and metrics')"
misses "specs, dist and node_modules are skipped" 'main\.spec|dist/|node_modules' "$out"
eq   "console count skips specs and scripts" "$(under 'console.* in backend sources (should be zero)' | tr -d ' ')" "count:1"

echo "# options"
has "INVENTORY_LIMIT caps a section" 0 '… \+1 more lines \(raise INVENTORY_LIMIT=1' env INVENTORY_LIMIT=1 bash "$inventory"
has "takes a root"                   0 "^root: $tmp/project/src$" bash "$inventory" "$tmp/project/src"
has "a missing root"                 1 '^root not found: .*nope$' bash "$inventory" "$tmp/nope"

finish
