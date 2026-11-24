#!/usr/bin/env bash
# Live backend inventory for nestjs-service-review: shared primitives that
# already exist, the module map, and which units are missing a spec.
#
# Usage: scripts/inventory.sh [app-src]
#   app-src is the directory holding the NestJS modules (e.g. src/app or
#   <app>/src). Auto-detected from the first *.module.ts found when omitted.
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

# Output is bounded: INVENTORY_LIMIT lines per section (default 40), overflow
# reported as a count.
limit="${INVENTORY_LIMIT:-40}"

cap() {
  awk -v limit="$limit" '
    NR <= limit { print; next }
    END { if (NR > limit) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR - limit, limit }
  '
}

indent() {
  sed 's/^/  /'
}

count_files() {
  find "$1" -name "$2" | wc -l | tr -d ' '
}

# Prints the names a file exports, comma-separated. $2 is the alternation of declaration kinds.
exported_names() {
  local declaration="export (async )?($2) "
  grep -rhoE "${declaration}[A-Za-z0-9_]+" "$1" 2>/dev/null | sed -E "s/^$declaration//" | LC_ALL=C sort -u
}

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
app="${1:-}"
if [ -z "$app" ]; then
  app_module=$(find "$PWD" "$root" -maxdepth 6 -name 'app.module.ts' -not -path '*/node_modules/*' 2>/dev/null | head -1)
  [ -n "$app_module" ] && app=$(dirname "$app_module")
fi
if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "app src not found — pass it: inventory.sh <dir>" >&2
  exit 1
fi
echo "app src: ${app#$root/}"

shared_primitives() {
  local dir file exports
  while IFS= read -r dir; do
    while IFS= read -r file; do
      exports=$(exported_names "$file" 'function|const|interface|type|class|enum' | paste -sd, -)
      [ -n "$exports" ] && printf '  %-44s %s\n' "${file#"$app"/}" "$exports"
    done < <(find "$dir" -name '*.ts' ! -name '*.spec.ts' ! -name 'index.ts' ! -name '*.module.ts' | sort)
  done < <(find "$app" -maxdepth 3 -type d \( -name shared -o -name common -o -name core \) 2>/dev/null)
}

modules() {
  local module dir
  while IFS= read -r module; do
    dir=$(dirname "$module")
    printf '  %-24s services:%-3s controllers:%-3s specs:%s\n' \
      "$(basename "$module" .module.ts)" \
      "$(count_files "$dir" '*.service.ts')" \
      "$(count_files "$dir" '*.controller.ts')" \
      "$(count_files "$dir" '*.spec.ts')"
  done < <(find "$app" -name '*.module.ts' ! -name 'app.module.ts' | sort)
}

# Reads unit paths on stdin; prints the ones with no spec beside them or in __tests__.
units_without_a_spec() {
  local unit name dir
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    name=$(basename "$unit" .ts)
    dir=$(dirname "$unit")
    [ -f "$dir/$name.spec.ts" ] || [ -f "$dir/__tests__/$name.spec.ts" ] || printf '  %s\n' "${unit#$app/}"
  done
}

echo
echo "=== shared primitives — do not rebuild"
shared_primitives | cap

echo
echo "=== modules"
modules | cap

echo
# REVIEW_FILES (space-separated) restricts the check to the files under review;
# otherwise every unit in the app is checked.
if [ -n "${REVIEW_FILES:-}" ]; then
  echo "=== missing specs among REVIEW_FILES (a new unit needs one)"
  # shellcheck disable=SC2086
  units=$(printf '%s\n' $REVIEW_FILES | grep -E '\.(service|controller)\.ts$' | sort)
else
  echo "=== missing specs (a new unit here needs one)"
  units=$(find "$app" \( -name '*.service.ts' -o -name '*.controller.ts' \) | sort)
fi
without_spec=$(units_without_a_spec <<< "$units")
if [ -n "$without_spec" ]; then
  echo "$without_spec" | cap
else
  echo "  none"
fi

echo
echo "=== guards and interceptors in use"
grep -rhoE '@(UseGuards|UseInterceptors)\([^)]*\)' "$app" --include='*.controller.ts' 2>/dev/null \
  | sort | uniq -c | sort -rn | indent | cap

test_utils=$(find "$root" -maxdepth 4 -type d -name 'test-utils' -not -path '*/node_modules/*' 2>/dev/null | head -1)
if [ -n "$test_utils" ]; then
  echo
  echo "=== test-utils available to specs (${test_utils#$root/})"
  exported_names "$test_utils" 'function|const' | indent | cap
fi
