#!/usr/bin/env bash
# Tests for dep-vet.sh.
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

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
