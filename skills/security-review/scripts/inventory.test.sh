#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo project
mkdir -p apps/api/src/auth apps/web/src node_modules/dep dist backend/src/main/java backend/src/test/java
cat > package.json <<'JSON'
{ "devDependencies": { "typescript": "5.0.0" } }
JSON
cat > apps/api/package.json <<'JSON'
{ "dependencies": { "@nestjs/throttler": "6.0.0", "argon2": "0.40.0", "express": "4.0.0", "helmet": "8.0.0" } }
JSON
cat > apps/api/src/main.ts <<'TS'
app.use(helmet());
app.useGlobalPipes(new ValidationPipe({ whitelist: true }));
app.enableCors({ origin: allowed });
TS
cat > apps/api/src/auth/auth.module.ts <<'TS'
providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }],
export const Public = () => SetMetadata('isPublic', true);
const hash = await argon2.hash(password);
TS
cat > apps/api/src/auth/health.controller.ts <<'TS'
@Public()
@Get('health') health() {}
const rows = await prisma.$queryRaw`select 1`;
const event = stripe.webhooks.constructEvent(body, sig, key);
TS
echo "await SecureStore.setItemAsync('token', t);"   > apps/web/src/session.ts
echo "@Public() class InASpec {}"                    > apps/api/src/auth/auth.spec.ts
echo "@Public() class Dep {}"                        > node_modules/dep/index.ts
echo "@Public() class Dist {}"                       > dist/main.ts
echo 'implementation("org.springframework.boot:spring-boot-starter-security")' > backend/build.gradle.kts
echo "http.authorizeHttpRequests(a -> a.requestMatchers(\"/health\").permitAll());" > backend/src/main/java/SecurityConfig.java
echo "@PermitAll class InATest {}"                   > backend/src/test/java/ATest.java

out=$(bash "$inventory")
eq   "exits 0"                 "$?" 0
sees "names the root"          "^root: $tmp/project$" "$out"

libs=$(under "Security libraries")
sees   "a workspace dependency"  '^  argon2 0.40.0$' "$libs"
sees   "a scoped one"            '^  @nestjs/throttler 6.0.0$' "$libs"
sees   "a Gradle one"            '^  spring-boot-starter-security$' "$libs"
misses "unrelated dependencies"  'express|typescript' "$libs"

sees "password hashing"        'auth.module.ts:3:.*argon2.hash' "$(under 'Authentication')"
sees "the global guard"        'auth.module.ts:1:.*APP_GUARD' "$(under 'Authorization')"
sees "the public marker"       'auth.module.ts:2:.*Public' "$(under 'Authorization')"
sees "Spring URL rules"        'SecurityConfig.java:1:' "$(under 'Authorization')"
sees "the validation pipe"     'main.ts:2:' "$(under 'Input validation')"
sees "headers and CORS"        'main.ts:1:.*helmet' "$(under 'Rate limiting')"
sees "raw SQL"                 'health.controller.ts:3:' "$(under 'Raw SQL')"
sees "a signature check"       'health.controller.ts:4:' "$(under 'Webhooks')"
sees "client token storage"    'session.ts:1:' "$(under 'Where the client keeps a token')"
misses "specs, tests, dist and node_modules are skipped" 'auth\.spec|ATest|dist/|node_modules' "$out"
eq   "open handlers are counted" "$(under 'Handlers open to everyone (each one should be meant)' | tr -d ' ')" "count:2"

echo "# options"
has "INVENTORY_LIMIT caps a section" 0 '… \+[0-9]+ more lines \(raise INVENTORY_LIMIT=1' env INVENTORY_LIMIT=1 bash "$inventory"
has "takes a root"                   0 "^root: $tmp/project/apps$" bash "$inventory" "$tmp/project/apps"
has "a missing root"                 1 '^root not found: .*nope$' bash "$inventory" "$tmp/nope"

finish
