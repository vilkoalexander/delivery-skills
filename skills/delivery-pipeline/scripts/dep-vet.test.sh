#!/usr/bin/env bash
# Tests for dep-vet.sh, secret-scan.sh and the mixed-chunk line of risk.sh.
#
#   bash skills/delivery-pipeline/scripts/dep-vet.test.sh
#
# Talks to dep-vet.fixture.mjs on loopback, never to the real registry.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
node "$here/dep-vet.fixture.mjs" > "$tmp/port" & server=$!
trap 'kill $server 2>/dev/null; wait $server 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
export DEP_REGISTRY="http://127.0.0.1:$(cat "$tmp/port")" DEP_OSV="http://127.0.0.1:$(cat "$tmp/port")"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1"; printf '%s\n' "$2" | sed 's/^/       /'; }
# vet NAME EXPECTED_EXIT PATTERN args... — pattern "" means no output at all
vet() {
  local name=$1 want=$2 pat=$3 out code; shift 3
  out=$(bash "$here/dep-vet.sh" "$@" 2>&1); code=$?
  if [ "$code" != "$want" ]; then nok "$name" "exit $code, wanted $want"$'\n'"$out"
  elif [ -z "$pat" ] && [ -n "$out" ]; then nok "$name" "expected silence"$'\n'"$out"
  elif [ -n "$pat" ] && ! printf '%s' "$out" | grep -qE -- "$pat"; then nok "$name" "no match for $pat"$'\n'"$out"
  else ok "$name"; fi
}

echo "# dep-vet.sh"
vet "old package is clean"            0 ""                                  lodash
vet "scoped package is clean"         0 ""                                  @scope/tool@1.0.0
vet "unknown name blocks"             1 "^BLOCK lodahs — not in the registry" lodahs
vet "young package blocks"            1 "^BLOCK young-pkg@0.0.1 — package first published 3 days ago" young-pkg
vet "fresh version blocks"            1 "^BLOCK fresh-version@2.0.0 — this version was published 1 days ago" fresh-version
vet "older pin of it is clean"        0 ""                                  fresh-version@1.0.0
vet "range vets its base version"     0 ""                                  'fresh-version@^1.0.0'
vet "install script flags"            0 "^FLAG has-script@1.0.0 — runs postinstall" has-script
vet "advisory flags"                  0 "^FLAG lodash@4.17.20 — 1 known advisory: GHSA" lodash@4.17.20
vet "malware advisory blocks"         1 "^BLOCK evil-pkg@1.0.0 — reported as malware: MAL-2025-0001" evil-pkg
vet "git spec flags"                  0 "^FLAG github:a/b — not a registry package" github:a/b
vet "local path is ignored"           0 ""                                  ./packages/ui
vet "workspace spec is ignored"       0 ""                                  'ui@workspace:*'
vet "alias vets the real package"     1 "^BLOCK lodahs"                     'lo@npm:lodahs@1.0.0'
vet "one bad spec blocks the set"     1 "^BLOCK lodahs"                     lodash lodahs
DEP_VET_ALLOW='^@acme/' vet "allowed scope is not vetted" 0 ""              @acme/private
echo '{"deps":{"allow":["^@acme/"],"minAgeDays":2,"minVersionDays":2}}' > "$tmp/deps.json"
DELIVERY_CONFIG="$tmp/deps.json" vet "deps.allow from the config" 0 ""        @acme/private
DELIVERY_CONFIG="$tmp/deps.json" vet "deps age limits from the config" 0 ""   young-pkg@0.0.1
DEP_VET=off vet "off prints nothing"  0 ""                                  lodahs
DEP_REGISTRY="http://127.0.0.1:1" vet "dead registry skips, never blocks" 0 "^SKIP lodash" lodash

repo="$tmp/repo"; mkdir -p "$repo/apps/web" && git -C "$repo" init -q
echo '{"dependencies":{"lodash":"^4.17.21"}}' > "$repo/package.json"
echo '{"dependencies":{"lodash":"^4.17.21"}}' > "$repo/apps/web/package.json"
git -C "$repo" add . && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init
cd "$repo"
vet "diff: nothing changed"           0 ""                                  --diff
echo '{"dependencies":{"lodash":"^4.17.21","lodahs":"^1.0.0"}}' > package.json
vet "diff: added dep is vetted"       1 "^BLOCK lodahs"                     --diff
echo '{"dependencies":{"lodash":"4.17.20"}}' > package.json
vet "diff: re-versioned dep is vetted" 0 "^FLAG lodash@4.17.20"             --diff
git checkout -q package.json
echo '{"dependencies":{"lodash":"^4.17.21"},"devDependencies":{"young-pkg":"0.0.1"}}' > apps/web/package.json
vet "diff: workspace package.json"    1 "^BLOCK young-pkg"                  --diff
vet "diff: named file only"           0 ""                                  --diff package.json
out=$(bash "$here/../../reuse-guardrails/scripts/reuse-scan.sh" apps/web/package.json 2>&1)
printf '%s' "$out" | grep -q "## Dependency vetting (1)" && printf '%s' "$out" | grep -q "BLOCK young-pkg" && ok "reuse-scan carries the vetting" || nok "reuse-scan carries the vetting" "$out"
git checkout -q apps/web/package.json

echo "# secret-scan.sh"
# scan NAME EXPECTED_EXIT PATTERN FILE CONTENT
scan() {
  local name=$1 want=$2 pat=$3 file=$4 out code
  mkdir -p "$(dirname "$file")"; printf '%s\n' "$5" > "$file"
  out=$(bash "$here/secret-scan.sh" "$file" 2>&1); code=$?
  rm -f "$file"
  if [ "$code" != "$want" ]; then nok "$name" "exit $code, wanted $want"$'\n'"$out"
  elif ! printf '%s' "$out" | grep -qE -- "$pat"; then nok "$name" "no match for $pat"$'\n'"$out"
  elif printf '%s' "$out" | grep -qF -- "$5" && [ "$want" = 1 ]; then nok "$name" "output repeats the secret"$'\n'"$out"
  else ok "$name"; fi
}
aws="AKIA""ABCDEFGHIJKLMNOP"
scan "AWS key id"                  1 "src/a.ts:1 — AWS access key id" src/a.ts "const k = '$aws'"
scan "private key block"           1 "private key block"       src/key.ts '-----BEGIN RSA PRIVATE ''KEY-----'
scan "GitHub token"                1 "GitHub token"            src/a.ts "token: 'ghp_""0123456789abcdefghijABCDEFGHIJ012345'"
scan "Stripe live key"             1 "Stripe live key"         src/a.ts "sk_""live_0123456789abcdefABCD"
scan "sk- key"                     1 "API key"                 src/a.ts "const c = new Client('sk-""ant-0123456789abcdef0123456789abcdef')"
scan "vendor key in a test file"   1 "AWS access key id"       src/a.spec.ts "const k = '$aws'"
scan "literal on a secret key"     1 "literal assigned"        src/config.ts "  apiKey: 'f3a9c1d27b6e4085a1c2'"
scan "password in a URL"           1 "password in a URL"       src/db.ts "const url = 'postgres://app:hunter2secret@db.internal:5432/app'"
scan "JWT"                         1 "JSON web token"          src/a.ts "const t = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop'"
scan "committed env file"          1 "committed env file"      .env.production "STRIPE_SECRET=whsec1234567890"
scan "env read is clean"           0 "SECRETS: 0 hits"         src/config.ts "  apiKey: process.env.API_KEY,"
scan "short label is clean"        0 "SECRETS: 0 hits"         src/form.ts "  password: 'Password1',"
scan "config path is clean"        0 "SECRETS: 0 hits"         src/config.ts "  secretKey: 'config.auth.secret.value',"
scan "placeholder URL is clean"    0 "SECRETS: 0 hits"         src/db.ts "const url = 'postgres://user:changeme@db:5432/app'"
scan "localhost URL is clean"      0 "SECRETS: 0 hits"         src/db.ts "const url = 'postgres://app:hunter2secret@localhost:5432/app'"
scan "JWT in a test is clean"      0 "SECRETS: 0 hits"         src/a.spec.ts "const t = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop'"
scan "env example is clean"        0 "SECRETS: 0 hits"         .env.example "STRIPE_SECRET=whsec1234567890"
scan "lockfile is not scanned"     0 "SECRETS: 0 hits"         package-lock.json "\"integrity\": \"$aws\""
SECRET_ALLOW='src/legacy/' scan "allowed path is clean" 0 "SECRETS: 0 hits" src/legacy/a.ts "const k = '$aws'"

echo '{"workspaces":{".":{"typecheck":false,"lint":false,"format":false,"test":false}}}' > "$tmp/gate.json"
mkdir -p src && echo "const k = '$aws'" > src/old.ts
git add . && git -c user.name=t -c user.email=t@t commit -qm old
echo "export const x = 1" >> src/old.ts
out=$(bash "$here/secret-scan.sh" src/old.ts 2>&1); code=$?
[ "$code" = 0 ] && ok "a secret already committed is not this change's" || nok "a secret already committed is not this change's" "$out"
git checkout -q src/old.ts
echo "const k2 = '$aws'" > src/new.ts
out=$(DELIVERY_CONFIG="$tmp/gate.json" STATIC_SKIP="test-lock drift reuse" bash "$here/static-gate.sh" check src/new.ts 2>&1); code=$?
[ "$code" = 1 ] && printf '%s' "$out" | grep -q "== secrets" && printf '%s' "$out" | grep -q "src/new.ts:1 — AWS" && ok "the gate fails on a secret" || nok "the gate fails on a secret" "$out"
out=$(DELIVERY_CONFIG="$tmp/gate.json" STATIC_SKIP="secrets test-lock drift reuse" bash "$here/static-gate.sh" check src/new.ts 2>&1); code=$?
[ "$code" = 0 ] && ok "STATIC_SKIP=secrets skips it" || nok "STATIC_SKIP=secrets skips it" "$out"
rm -f src/new.ts

echo "# risk.sh mixed chunk"
risk() { env -u TYPESAFE_API_KEY bash "$here/risk.sh" "$@" 2>&1; }
mixed() { # name, want (yes|no), paths...
  local name=$1 want=$2 out; shift 2
  out=$(risk "$@")
  if printf '%s\n' "$out" | grep -q '^mixed: '; then [ "$want" = yes ] && ok "$name" || nok "$name" "$out"
  else [ "$want" = no ] && ok "$name" || nok "$name" "$out"; fi
}
mixed "bump alone is not mixed"       no  package.json pnpm-lock.yaml
mixed "bump with source is mixed"     yes package.json src/a.ts src/b.ts
mixed "workspace package.json counts" yes apps/web/package.json src/a.ts
mixed "no dependency change, no line" no  src/a.ts

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
