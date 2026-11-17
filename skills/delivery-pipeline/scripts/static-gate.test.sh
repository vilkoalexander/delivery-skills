#!/usr/bin/env bash
# `coverage` and the mode switch. `check` is in config.test.sh.
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
gate="$here/static-gate.sh"

echo "# modes"
new_repo empty
has "no mode prints the header" 2 'bash static-gate.sh coverage \[root\]' bash "$gate"
has "unknown mode"              2 'unknown mode: lint \(coverage \| check \| init\)' bash "$gate" lint
has "check with no paths"       2 'check: no paths' bash "$gate" check

# value NAME prints the status column of one coverage row
value() { printf '%s\n' "$out" | grep -E "^  $1 " | head -1 | sed -E "s|^  $1 +||"; }

echo "# coverage of a bare project"
new_repo bare
echo '{"name":"bare"}' > package.json
out=$(bash "$gate" coverage 2>&1); code=$?
eq   "exits 0"              "$code" 0
sees "names the project"    '^Static coverage — bare$' "$out"
eq   "no tsconfig"          "$(value tsconfig.json)" "none"
eq   "no eslint config"     "$(value config)" "none"
eq   "no prettier"          "$(value prettier)" "none"
eq   "no pre-commit hook"   "$(value 'pre-commit hook')" "none"
eq   "no ci"                "$(value ci)" "none found"
sees "absent list"          '^ABSENT: typescript eslint prettier eslint:max-warnings module-boundaries knip pre-commit gitleaks' "$out"
sees "points at the setup sections" '^  sections: typescript eslint prettier boundaries dead-code hooks' "$out"

echo "# coverage of a configured project"
new_repo strict
mkdir -p .husky .github/workflows prisma
cat > package.json <<'JSON'
{ "name": "strict",
  "scripts": { "typecheck": "tsc -p . --noEmit", "lint": "eslint . --max-warnings=0" },
  "devDependencies": { "knip": "1.0.0", "jscpd": "1.0.0", "lint-staged": "1.0.0" } }
JSON
cat > tsconfig.json <<'JSON'
{ "compilerOptions": { "strict": true, "noUncheckedIndexedAccess": true } }
JSON
echo '{}'           > .prettierrc
echo 'x'            > .husky/pre-commit
echo 'x'            > .gitleaks.toml
echo 'x'            > .dependency-cruiser.cjs
echo 'run: npm run lint' > .github/workflows/ci.yml
echo 'model A { id Int @id }' > prisma/schema.prisma
out=$(bash "$gate" coverage 2>&1)
eq   "strict is on"                   "$(value strict)" "on"
eq   "strict implies noImplicitAny"   "$(value noImplicitAny)" "on (via strict)"
eq   "an explicit option is on"       "$(value noUncheckedIndexedAccess)" "on"
eq   "an unset option is absent"      "$(value exactOptionalPropertyTypes)" "absent"
eq   "typecheck script is shown"      "$(value 'script: typecheck')" "tsc -p . --noEmit"
eq   "prettier config"                "$(value prettier)" "config present"
eq   "max-warnings"                   "$(value 'lint script --max-warnings=0')" "on"
eq   "prisma schema"                  "$(value 'prisma validate')" "available"
eq   "dependency-cruiser"             "$(value 'module boundaries')" "dependency-cruiser"
eq   "knip"                           "$(value knip)" "installed"
eq   "pre-commit hook"                "$(value 'pre-commit hook')" "on"
eq   "lint-staged"                    "$(value lint-staged)" "installed"
eq   "secret scan"                    "$(value 'secret scan')" "on"
eq   "jscpd"                          "$(value 'duplicate detection \(jscpd\)')" "installed"
sees "ci file that lints"             'ci runs lint/typecheck +\.github/workflows/ci.yml' "$out"
sees "absent keeps what is missing"   '^ABSENT: tsc:exactOptionalPropertyTypes .* eslint( |$)' "$out"
misses "absent drops what is there"   '^ABSENT:.*(prettier|knip|pre-commit|gitleaks|module-boundaries|max-warnings|tsc:strict )' "$out"

echo "# coverage reads the ESLint rules in force"
new_repo linted
mkdir -p src bin
echo '{ "devDependencies": { "vitest": "1.0.0", "eslint-plugin-import-x": "1.0.0" } }' > package.json
echo "export default []" > eslint.config.mjs
touch src/Cart.tsx src/cart.service.ts src/cart.spec.ts
# Stands in for eslint: every file gets the same resolved config.
cat > bin/npx <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"eslint --print-config"*) cat <<'JSON'
{ "languageOptions": { "parserOptions": { "projectService": true } },
  "rules": { "no-console": "error", "react-hooks/rules-of-hooks": [2], "react/jsx-key": ["warn"],
             "import-x/no-cycle": 1, "vitest/expect-expect": "off" } }
JSON
  ;;
  *) exit 1 ;;
esac
SH
chmod +x bin/npx
out=$(PATH="$PWD/bin:$PATH" bash "$gate" coverage 2>&1)
eq     "names the config"               "$(value config)" "eslint.config.mjs"
eq     "type-aware linting"             "$(value 'type-aware \(tsx\)')" "on"
eq     "a rule at error"                "$(value 'no-console \(tsx\)')" "error"
eq     "a numeric level"                "$(value 'react-hooks/rules-of-hooks \(tsx\)')" "error"
eq     "a rule at warn"                 "$(value 'react/jsx-key \(tsx\)')" "warn"
eq     "a rule that is off"             "$(value 'vitest/expect-expect \(spec\)')" "off"
eq     "a rule nobody set"              "$(value '@typescript-eslint/no-floating-promises \(service\)')" "absent"
eq     "an installed plugin's rule"     "$(value 'import-x/no-cycle \(service\)')" "warn"
misses "React rules only on tsx"        'react/jsx-key \(service\)' "$out"
misses "test rules only on tests"       'vitest/expect-expect \(tsx\)' "$out"
misses "no rows for a plugin not installed" 'react-native/|sonarjs/|import/no-cycle' "$out"
misses "only the installed test plugin" 'jest/' "$out"
sees   "a rule below error is absent"   '^ABSENT:.* eslint:react/jsx-key( |$)' "$out"
misses "a rule at error is not"         '^ABSENT:.* eslint:no-console( |$)' "$out"
sees   "sections follow the gaps"       '^  sections: typescript eslint boundaries shape react tests prettier dead-code hooks' "$out"

echo "# check runs the secret scan"
new_repo gated
echo base > README.md && commit_all
mkdir src
echo '{"workspaces":{".":{"typecheck":false,"lint":false,"format":false,"test":false}}}' > "$tmp/gate.json"
echo "const k = 'AKIA""ABCDEFGHIJKLMNOP'" > src/new.ts
out=$(DELIVERY_CONFIG="$tmp/gate.json" STATIC_SKIP="test-lock drift reuse" bash "$gate" check src/new.ts 2>&1); code=$?
eq   "a secret fails the gate"  "$code" 1
sees "under the secrets step"   '^== secrets' "$out"
sees "with the hit"             'src/new.ts:1 — AWS' "$out"
sees "and the verdict"          '^static gate: FAILED' "$out"
has  "STATIC_SKIP=secrets skips it" 0 '^-- secrets: skipped — STATIC_SKIP' env DELIVERY_CONFIG="$tmp/gate.json" STATIC_SKIP="secrets test-lock drift reuse" bash "$gate" check src/new.ts

finish
