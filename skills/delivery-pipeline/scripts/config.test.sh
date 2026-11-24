#!/usr/bin/env bash
# Tests for config.mjs and the config-driven half of static-gate.sh check.
#
#   bash skills/delivery-pipeline/scripts/config.test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cfg="$here/config.mjs"; gate="$here/static-gate.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export DELIVERY_EVENTS_DIR="$tmp/events" DELIVERY_RUN_DIR="$tmp/runs" DEP_VET=off

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1"; printf '%s\n' "$2" | sed 's/^/       /'; }
# has NAME EXPECTED_EXIT PATTERN command... — pattern "" means no output
has() {
  local name=$1 want=$2 pat=$3 out code; shift 3
  out=$("$@" 2>&1); code=$?
  if [ "$code" != "$want" ]; then nok "$name" "exit $code, wanted $want"$'\n'"$out"
  elif [ -z "$pat" ] && [ -n "$out" ]; then nok "$name" "expected silence"$'\n'"$out"
  elif [ -n "$pat" ] && ! grep -qE -- "$pat" <<< "$out"; then nok "$name" "no match for $pat"$'\n'"$out"
  else ok "$name"; fi
}
lacks() { # NAME PATTERN command...
  local name=$1 pat=$2 out; shift 2
  out=$("$@" 2>&1)
  if grep -qE -- "$pat" <<< "$out"; then nok "$name" "$out"; else ok "$name"; fi
}
write() { mkdir -p docs/review; cat > docs/review/delivery.json; }

repo="$tmp/repo"; mkdir -p "$repo/apps/api/src" "$repo/apps/web/src" "$repo/tools" && git -C "$repo" init -q && cd "$repo"
T=$'\t'

echo "# check and get"
has "no file: refuses and names init"  2 "no docs/review/delivery.json.*static-gate.sh init" node "$cfg" check
has "no file: get is empty, exit 0"    0 "" node "$cfg" get risk.high
has "no file: the gate refuses"        2 "static-gate.sh init" bash "$gate" check apps/api/src/a.ts
echo '{ nope' | write
has "broken JSON"                      2 "delivery config: " node "$cfg" check
echo '{"workspace":{}}' | write
has "unknown key names the known ones" 2 'unknown key "workspace" \(known: .*workspaces' node "$cfg" check
echo '{"workspaces":{}}' | write
has "no workspace"                     2 "at least one directory" node "$cfg" check
echo '{"workspaces":{".":{"lint":7}}}' | write
has "step of the wrong type"           2 'workspaces\["\."\]\.lint must be' node "$cfg" check
echo '{"workspaces":{".":{"lint":{"run":"x"}}}}' | write
has "object step without files"        2 "lint.files must be a pattern" node "$cfg" check
echo '{"workspaces":{".":{}},"risk":{"high":"billing"}}' | write
has "pattern list of the wrong type"   2 "risk.high must be a list" node "$cfg" check

write <<'JSON'
{
  "stack": ["nestjs", "react"],
  "workspaces": {
    "apps/api": {
      "typecheck": { "run": "echo tsc", "files": "\\.ts$" },
      "lint": { "run": "echo lint {files}", "files": "\\.ts$" },
      "format": "echo fmt {files}",
      "test": false,
      "prisma": { "run": "echo prisma", "files": "\\.prisma$" }
    },
    "apps/web": { "lint": "echo weblint {files}" },
    ".": { "typecheck": false, "lint": false, "format": false, "test": false }
  },
  "risk": { "high": ["src/billing/", "ledger"] },
  "secrets": { "allow": ["^src/legacy/"] },
  "deps": { "allow": ["^@acme/"], "minAgeDays": 90 },
  "shared": ["(^|/)libs/ui/"]
}
JSON
has "valid file is silent"             0 "" node "$cfg" check
has "get: pattern list is one ERE"     0 '^\(src/billing/\)\|\(ledger\)$' node "$cfg" get risk.high
has "get: scalar"                      0 '^90$' node "$cfg" get deps.minAgeDays
has "get: unset is empty"              0 "" node "$cfg" get risk.medium

echo "# plan"
echo x > apps/api/src/a.ts; echo x > "apps/api/src/it's b.ts"; echo x > apps/web/src/c.tsx; echo x > tools/x.sh; echo x > README.md
has "files are relative to the workspace" 0 "^RUN${T}apps/api${T}lint${T}echo lint 'src/a.ts'$" node "$cfg" plan apps/api/src/a.ts
has "no {files}: command as written"   0 "^RUN${T}apps/api${T}typecheck${T}echo tsc$" node "$cfg" plan apps/api/src/a.ts
has "false is OFF"                     0 "^OFF${T}apps/api${T}test${T}$" node "$cfg" plan apps/api/src/a.ts
lacks "a step whose files do not match is absent" "prisma" node "$cfg" plan apps/api/src/a.ts
has "a quote in a path is escaped"     0 "echo lint 'src/it'\\\\''s b.ts'" node "$cfg" plan "apps/api/src/it's b.ts"
has "missing step is SKIP with the reason" 0 "^SKIP${T}apps/web${T}typecheck${T}no command for apps/web" node "$cfg" plan apps/web/src/c.tsx
has "longest workspace wins"           0 "^RUN${T}apps/web${T}lint${T}echo weblint 'src/c.tsx'$" node "$cfg" plan apps/web/src/c.tsx
lacks "the root's steps stay out of a nested workspace" "${T}\\.${T}" node "$cfg" plan apps/web/src/c.tsx
has "root catches the rest"            0 "^OFF${T}\\.${T}lint" node "$cfg" plan tools/x.sh
has "deleted path: {files} step is skipped" 0 "^SKIP${T}apps/api${T}lint${T}every matching path was deleted" node "$cfg" plan apps/api/src/gone.ts
has "deleted path: whole-project step still runs" 0 "^RUN${T}apps/api${T}typecheck" node "$cfg" plan apps/api/src/gone.ts
echo '{"workspaces":{"apps/api":{"typecheck":false,"lint":false,"format":false,"test":false}}}' > "$tmp/only-api.json"
DELIVERY_CONFIG="$tmp/only-api.json" has "path under no workspace is reported" 0 "^SKIP${T}-${T}workspace${T}1 path\\(s\\) under no workspace: tools/x.sh" node "$cfg" plan tools/x.sh

echo "# static-gate.sh check"
export STATIC_SKIP="test-lock drift secrets reuse"
has "runs the workspace's commands"    0 "== lint:apps/api: echo lint 'src/a.ts'" bash "$gate" check apps/api/src/a.ts
has "summary names what ran"           0 "static gate: clean — ran: typecheck:apps/api lint:apps/api format:apps/api" bash "$gate" check apps/api/src/a.ts
has "a missing step is printed as skipped" 0 "^-- typecheck:apps/web: skipped — no command for apps/web" bash "$gate" check apps/web/src/c.tsx
has "and the summary lists it"         0 "skipped: .*typecheck:apps/web format:apps/web test:apps/web" bash "$gate" check apps/web/src/c.tsx
has "nothing ran says so"              0 "static gate: clean — ran: nothing" bash "$gate" check README.md
STATIC_SKIP="$STATIC_SKIP lint" has "STATIC_SKIP takes a config step name" 0 "^-- lint:apps/api: skipped — STATIC_SKIP" bash "$gate" check apps/api/src/a.ts
write <<'JSON'
{ "workspaces": { "apps/api": { "typecheck": "pwd", "lint": "echo boom >&2; exit 3", "format": false, "test": "cat" } } }
JSON
has "a failing command fails the gate" 1 "boom" bash "$gate" check apps/api/src/a.ts
has "and the summary says FAILED"      1 "static gate: FAILED — ran: typecheck:apps/api lint:apps/api test:apps/api" bash "$gate" check apps/api/src/a.ts
has "a command that reads stdin gets none" 1 "== test:apps/api: cat" bash "$gate" check apps/api/src/a.ts
write <<'JSON'
{ "workspaces": { "apps/api": { "typecheck": "test \"$(basename \"$PWD\")\" = api", "lint": false, "format": false, "test": false } } }
JSON
has "commands run in the workspace directory" 0 "static gate: clean" bash "$gate" check apps/api/src/a.ts
unset STATIC_SKIP

echo "# config feeds the other scripts"
write <<'JSON'
{ "workspaces": { ".": {} }, "risk": { "high": ["src/reports/"], "medium": ["\\.cfg$"] }, "secrets": { "allow": ["^src/legacy/"] }, "escapes": { "allow": ["^src/legacy/"] }, "erosion": { "threshold": 3, "allow": ["^src/legacy/"] }, "shared": ["(^|/)kit/"] }
JSON
risk() { env -u TYPESAFE_API_KEY bash "$here/risk.sh" "$@"; }
has "risk.high from the config"        0 "^high +src/reports/a.md" risk src/reports/a.md
has "risk.medium from the config"      0 "^medium +a.cfg +\\(RISK_MEDIUM\\)" risk a.cfg
RISK_HIGH='nothing-matches' has "the env var still wins" 0 "^low +src/reports/a.md" risk src/reports/a.md
mkdir -p src/legacy src/kit && echo "const k = 'AKIA""ABCDEFGHIJKLMNOP'" > src/legacy/a.ts && cp src/legacy/a.ts src/b.ts
has "secrets.allow from the config"    0 "SECRETS: 0 hits" bash "$here/secret-scan.sh" src/legacy/a.ts
has "and only for what it names"       1 "src/b.ts:1" bash "$here/secret-scan.sh" src/b.ts
echo "// @ts-ignore" > src/legacy/c.ts && cp src/legacy/c.ts src/d.ts
has "escapes.allow from the config"    0 "ESCAPES: 0 flags" bash "$here/escape-scan.sh" src/legacy/c.ts
has "and only for what it names"       0 "src/d.ts:1 — checker silenced" bash "$here/escape-scan.sh" src/d.ts
echo "function f(a) { if (a) return 1; if (!a) return 2; }" > src/legacy/e.js && cp src/legacy/e.js src/f.js
git add -A && git -c user.name=test -c user.email=test@test commit -qm erosion
echo "function f(a) { if (a) return 1; if (!a) return 2; if (a > 1) return 3; }" > src/legacy/e.js && cp src/legacy/e.js src/f.js
has "erosion.threshold from the config" 0 "src/f.js:1 — complex function grew — f: 3 → 4" bash "$here/erosion-scan.sh" src/f.js
has "erosion.allow from the config"    0 "EROSION: 0 flags \\(limit 3\\)" bash "$here/erosion-scan.sh" src/legacy/e.js
echo "export const x = 1" > src/kit/x.ts
has "shared from the config"           0 "src/kit/x.ts — new file in a shared layer" bash "$here/../../reuse-guardrails/scripts/reuse-scan.sh" src/kit/x.ts

echo "# writing"
w="$tmp/w"; mkdir -p "$w" && git -C "$w" init -q && cd "$w"
has "writing defaults to ste100 with no file" 0 "^ste100$" node "$cfg" get writing
write <<'J'
{ "writing": "free", "workspaces": { ".": {} } }
J
has "writing reads the file"            0 "^free$" node "$cfg" get writing
write <<'J'
{ "writing": "caveman", "workspaces": { ".": {} } }
J
has "an unknown writing value is refused" 2 "writing must be one of: ste100, free" node "$cfg" check

echo "# init"
init="$tmp/init"; mkdir -p "$init/apps/api/prisma" "$init/apps/web" "$init/packages/empty" && git -C "$init" init -q && cd "$init"
echo '{"scripts":{"typecheck":"tsc -b"},"devDependencies":{"prettier":"3","eslint":"9"}}' > package.json
touch pnpm-lock.yaml eslint.config.mjs .prettierrc apps/api/tsconfig.json apps/api/prisma/schema.prisma
echo '{"dependencies":{"@nestjs/core":"11","@prisma/client":"6"},"devDependencies":{"jest":"29"}}' > apps/api/package.json
echo '{"dependencies":{"react":"19","next":"15"},"devDependencies":{"vitest":"2"}}' > apps/web/package.json
echo '{}' > packages/empty/package.json
has "init writes the file"             0 "wrote docs/review/delivery.json" bash "$gate" init
has "the draft validates"              0 "" node "$cfg" check
q() { node -e 'const c=JSON.parse(require("fs").readFileSync("docs/review/delivery.json","utf8"));const v=process.argv[1].split("|").reduce((o,k)=>o?.[k],c);console.log(typeof v==="string"?v:JSON.stringify(v))' "$1"; }
has "stack from the dependencies"      0 '^\["nestjs","next","react","prisma"\]$' q stack
has "root: package script, pnpm"       0 '^pnpm run typecheck$' q 'workspaces|.|typecheck|run'
has "api: tsc from its tsconfig"       0 '^pnpm exec tsc --noEmit -p tsconfig.json$' q 'workspaces|apps/api|typecheck|run'
has "api: eslint from the root config" 0 'eslint --max-warnings=0 --no-warn-ignored \{files\}' q 'workspaces|apps/api|lint|run'
has "api: prettier ignores unknown files" 0 'prettier --check --ignore-unknown \{files\}' q 'workspaces|apps/api|format'
has "api: jest"                        0 'jest --findRelatedTests' q 'workspaces|apps/api|test|run'
has "api: prisma step"                 0 'prisma validate' q 'workspaces|apps/api|prisma|run'
has "web: vitest"                      0 'vitest related --run' q 'workspaces|apps/web|test|run'
has "web: no typecheck guessed"        0 '^undefined$' q 'workspaces|apps/web|typecheck'
has "init states the writing default"   0 "\"writing\": \"ste100\"" cat docs/review/delivery.json
has "init never overwrites"            2 "exists; edit it" bash "$gate" init

echo "# init, a Java repository"
jvm="$tmp/jvm"; mkdir -p "$jvm/core/crm" "$jvm/core/model" "$jvm/web" "$jvm/tools" && git -C "$jvm" init -q && cd "$jvm"
printf "include 'crm'\ninclude 'model'\n" > core/settings.gradle
printf "plugins { id 'checkstyle' }\ndependencies { implementation 'org.springframework.boot:spring-boot-starter-data-jpa' }\n" > core/build.gradle
touch core/crm/build.gradle core/model/build.gradle core/gradlew
echo '<project><artifactId>tools</artifactId></project>' > tools/pom.xml
echo '{"dependencies":{"@angular/core":"19"}}' > web/package.json
has "init writes the file"             0 "a guess from your build files" bash "$gate" init
has "the draft validates"              0 "" node "$cfg" check
has "stack names spring and jpa"       0 '^\["angular","spring","jpa"\]$' q stack
has "one workspace per build root"     0 '^\[".","core","tools"\]$' node -e 'console.log(JSON.stringify(Object.keys(JSON.parse(require("fs").readFileSync("docs/review/delivery.json","utf8")).workspaces).sort()))'
has "gradle: compile through the wrapper" 0 '^./gradlew -q compileJava compileTestJava$' q 'workspaces|core|typecheck|run'
has "gradle: tests"                    0 '^./gradlew test$' q 'workspaces|core|test|run'
has "gradle: checkstyle when configured" 0 'checkstyleMain' q 'workspaces|core|lint|run'
has "gradle: no formatter, so none"    0 '^false$' q 'workspaces|core|format'
has "maven: no wrapper, plain mvn"     0 '^mvn -q test$' q 'workspaces|tools|test|run'
has "maven: no checkstyle, so none"    0 '^false$' q 'workspaces|tools|lint'
has "a java path plans its workspace"  0 "RUN.core.typecheck../gradlew -q compileJava compileTestJava" node "$cfg" plan core/crm/src/main/java/A.java
has "a migration runs the tests only"  0 "^RUN.core.test../gradlew test$" node "$cfg" plan core/app/src/main/resources/db/migration/V2__x.sql

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
