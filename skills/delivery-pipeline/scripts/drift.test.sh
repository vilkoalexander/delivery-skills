#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/drift.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/docs/review" "$repo/gen" "$repo/apps/mobile" && git -C "$repo" init -q
cd "$repo" || exit 1
checks=docs/review/drift.checks

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1" "got '$2', wanted '$3'"; fi; }
has() { if grep -q -- "$2" "$tmp/out"; then ok "$1"; else nok "$1" "no '$2' in: $(cat "$tmp/out")"; fi; }
hasnt() { if grep -q -- "$2" "$tmp/out"; then nok "$1" "found '$2'"; else ok "$1"; fi; }
run() { bash "$script" "$@" > "$tmp/out" 2>&1; echo $?; }

eq "no checks file is clean" "$(run check src/a.ts)" 0
has "says nothing is declared" "no checks declared"

cat > $checks <<'EOF'
# comment

always-ok ::  :: true
mobile-only :: ^apps/mobile/ :: echo mobile broke; exit 1
piped :: ^src/ :: echo a | grep -q a || exit 1
EOF
eq "passing checks exit 0" "$(run check src/a.ts)" 0
has "counts what ran" "2 check(s) run"
hasnt "when filters by path" "mobile-only"
eq "matching path runs the failing check" "$(run check apps/mobile/App.tsx)" 1
has "prints the failing output" "mobile broke"
eq "no paths runs every check" "$(run check)" 1

echo 'v1' > gen/client.ts
echo 'keep' > gen/other.ts
cat > $checks <<'EOF'
client :: :: echo v2 > gen/client.ts :: gen
EOF
eq "a generator that changes its output is drift" "$(run check)" 1
has "names the drifted file" "gen/client.ts"
hasnt "does not name the unchanged file" "gen/other.ts"
eq "generated paths are put back" "$(cat gen/client.ts)" v1

cat > $checks <<'EOF'
client :: :: echo v1 > gen/client.ts :: gen
EOF
eq "a generator that changes nothing is clean" "$(run check)" 0

cat > $checks <<'EOF'
client :: :: echo new > gen/extra.ts :: gen
EOF
eq "a new generated file is drift" "$(run check)" 1
eq "the new file is removed again" "$([ -e gen/extra.ts ] && echo there || echo gone)" gone

cat > $checks <<'EOF'
client :: :: exit 3 :: gen
EOF
eq "a generator that fails is a failure" "$(run check)" 1
has "says it failed to run" "FAILED to run"

echo 'client :: :: true :: ../outside' > $checks
eq "generated paths outside the repo are refused" "$(run check)" 1
echo 'just a name' > $checks
eq "a malformed line fails" "$(run check)" 1

mkdir -p prisma locales
touch prisma/schema.prisma .env.example
echo '{"dependencies":{"expo":"1"}}' > apps/mobile/package.json
echo '{"devDependencies":{"orval":"1"}}' > package.json
rm $checks
run coverage >/dev/null
has "lists every undeclared pair" "UNDECLARED: prisma-migrations generated-api-client expo-native-deps locale-keys env-keys workspace-versions"
cat > $checks <<'EOF'
migrations :: prisma/ :: npx prisma migrate diff --exit-code
client :: :: npx orval :: gen
EOF
run coverage >/dev/null
has "declared checks leave the rest" "UNDECLARED: expo-native-deps locale-keys env-keys workspace-versions"
has "shows the declared command" "npx prisma migrate diff --exit-code"

eq "unknown mode is a usage error" "$(run nonsense)" 2

echo
echo "passed: $pass  failed: $fail"
[ "$fail" = 0 ]
