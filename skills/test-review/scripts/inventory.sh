#!/usr/bin/env bash
# Live test-helper inventory for test-review. Prints the runner, its setup
# files, and the helpers that already exist so the review never recommends a
# second factory or render wrapper.
#
# Usage: scripts/inventory.sh [root]
#   root defaults to the git top level.
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

indent() {
  sed 's/^/  /'
}

not_vendored() {
  grep -v node_modules
}

echo
echo "## Runner and config"
for pattern in vitest.config.* vitest.workspace.* jest.config.* .mocharc* playwright.config.* cypress.config.*; do
  for config in $pattern; do
    [ -e "$config" ] && echo "  $config"
  done
done

node -e '
  const scripts = require("./package.json").scripts || {};
  for (const name of Object.keys(scripts)) {
    if (/test|e2e|coverage/.test(name)) console.log("  script", name + ":", scripts[name]);
  }
' 2>/dev/null

setup_keys='setupFiles|setupFilesAfterEach|globalSetup'
grep -rlE "$setup_keys" vitest.config.* jest.config.* 2>/dev/null | while read -r config; do
  grep -oE "($setup_keys)[^]]*\]?" "$config" | head -3 | indent
done

echo
echo "## Helper modules"
exported_names() {
  local declaration='export (async function|function|const) '
  grep -oE "${declaration}[A-Za-z0-9_]+" "$1" | sed -E "s/^$declaration//" | sort -u | paste -sd, -
}

find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' \) \
  \( -path '*/test-utils/*' -o -path '*/testing/*' -o -path '*/fixtures/*' -o -path '*/factories/*' \
     -o -path '*/__mocks__/*' -o -path '*/mocks/*' -o -path '*/test/helpers/*' -o -path '*/tests/helpers/*' \
     -o -name 'test-utils.*' -o -name 'setup-tests.*' -o -name 'setupTests.*' -o -name 'test-setup.*' \) \
  -not -path '*/node_modules/*' -not -path '*/dist/*' 2>/dev/null | sort | while read -r file; do
  exports=$(exported_names "$file")
  printf '  %-48s %s\n' "${file#./}" "${exports:-—}"
done | cap

echo
echo "## Factories and builders exported anywhere"
builder='export (async )?(function|const) '
grep -rhoE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist "$builder(create|build|make|mock|stub|fake)[A-Z][A-Za-z0-9]*" --include='*.ts' --include='*.tsx' . 2>/dev/null \
  | not_vendored | sed -E "s/$builder//" | sort -u | indent | cap

echo
echo "## Network fixtures (msw, nock)"
grep -rlE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist 'setupServer\(|setupWorker\(|\bnock\(' --include='*.ts' --include='*.tsx' --include='*.js' . 2>/dev/null \
  | not_vendored | indent | cap

echo
echo "## Focused or skipped tests across the suite"
grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist '\b(it|test|describe)\.(only|skip)\(|\bx(it|test|describe)\(' --include='*.ts' --include='*.tsx' --include='*.js' . 2>/dev/null \
  | not_vendored | indent | cap
exit 0
