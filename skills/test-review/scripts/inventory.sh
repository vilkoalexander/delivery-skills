#!/usr/bin/env bash
# Live test-helper inventory for test-review. Prints the runner, its setup
# files, and the helpers that already exist so the review never recommends a
# second factory or render wrapper.
#
# Usage: scripts/inventory.sh [root]
#   root defaults to the git top level.
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

LIMIT="${INVENTORY_LIMIT:-40}"
cap() { awk -v n="$LIMIT" 'NR<=n{print;next} END{if(NR>n) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR-n, n}'; }

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
[ -d "$root" ] || { echo "root not found: $root" >&2; exit 1; }
cd "$root"
echo "root: $root"

echo
echo "## Runner and config"
for f in vitest.config.* vitest.workspace.* jest.config.* .mocharc* playwright.config.* cypress.config.*; do
  for m in $f; do [ -e "$m" ] && echo "  $m"; done
done
node -e 'const p=require("./package.json");const s=p.scripts||{};for(const k of Object.keys(s))if(/test|e2e|coverage/.test(k))console.log("  script",k+":",s[k])' 2>/dev/null
grep -rlE 'setupFiles|setupFilesAfterEach|globalSetup' vitest.config.* jest.config.* 2>/dev/null | while read -r c; do
  grep -oE "(setupFiles|setupFilesAfterEach|globalSetup)[^]]*\]?" "$c" | head -3 | sed 's/^/  /'
done

echo
echo "## Helper modules"
find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' \) \
  \( -path '*/test-utils/*' -o -path '*/testing/*' -o -path '*/fixtures/*' -o -path '*/factories/*' \
     -o -path '*/__mocks__/*' -o -path '*/mocks/*' -o -path '*/test/helpers/*' -o -path '*/tests/helpers/*' \
     -o -name 'test-utils.*' -o -name 'setup-tests.*' -o -name 'setupTests.*' -o -name 'test-setup.*' \) \
  -not -path '*/node_modules/*' -not -path '*/dist/*' 2>/dev/null | sort | while read -r f; do
  exports=$(grep -oE 'export (async function|function|const) [A-Za-z0-9_]+' "$f" | sed -E 's/^export (async function|function|const) //' | sort -u | paste -sd, -)
  printf '  %-48s %s\n' "${f#./}" "${exports:-—}"
done | cap

echo
echo "## Factories and builders exported anywhere"
grep -rhoE 'export (async )?(function|const) (create|build|make|mock|stub|fake)[A-Z][A-Za-z0-9]*' --include='*.ts' --include='*.tsx' . 2>/dev/null \
  | grep -v node_modules | sed -E 's/export (async )?(function|const) //' | sort -u | sed 's/^/  /' | cap

echo
echo "## Network fixtures (msw, nock)"
grep -rlE 'setupServer\(|setupWorker\(|\bnock\(' --include='*.ts' --include='*.tsx' --include='*.js' . 2>/dev/null | grep -v node_modules | sed 's/^/  /' | cap

echo
echo "## Focused or skipped tests across the suite"
grep -rnE '\b(it|test|describe)\.(only|skip)\(|\bx(it|test|describe)\(' --include='*.ts' --include='*.tsx' --include='*.js' . 2>/dev/null \
  | grep -v node_modules | sed 's/^/  /' | cap
