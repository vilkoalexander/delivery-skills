#!/usr/bin/env bash
# Live contract inventory for api-contract-review: the schema→dto→type chain
# per entity, who consumes each package, barrel gaps, and a Prisma↔schema enum
# drift cross-check when a Prisma schema exists.
#
# Usage: scripts/inventory.sh [contract-dir]
#   contract-dir holds the schemas/, dto/, types/, utils/ packages (e.g.
#   libs/shared or packages). Auto-detected when omitted.
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

yes_or_no() {
  if [ "$1" != 0 ]; then echo yes; else echo NO; fi
}

count_lines() {
  wc -l | tr -d ' '
}

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
contracts="${1:-}"
if [ -z "$contracts" ]; then
  for candidate in "$root/libs/shared" "$root/packages/shared" "$root/packages/contracts" "$root/packages" "$root/libs"; do
    if [ -d "$candidate/schemas" ] || [ -d "$candidate/types" ]; then
      contracts="$candidate"
      break
    fi
  done
fi
if [ -z "$contracts" ] || [ ! -d "$contracts" ]; then
  echo "contract dir not found — pass it: inventory.sh <dir>" >&2
  exit 1
fi
echo "contract dir: ${contracts#$root/}"

apps=$(find "$root" -maxdepth 2 -type d -name apps -not -path '*/node_modules/*' | head -1)
scope=$(grep -ohE '"name": *"@[a-z0-9-]+/' "$contracts"/*/package.json 2>/dev/null | head -1 | grep -oE '@[a-z0-9-]+' || echo '@shared')

chain_coverage() {
  local schema entity dto_count type_count
  for schema in "$contracts"/schemas/src/lib/*.schema.ts "$contracts"/schemas/src/*.schema.ts; do
    [ -e "$schema" ] || continue
    entity=$(basename "$schema" .schema.ts)
    dto_count=$(find "$contracts/dto" -name "$entity.dto.ts" 2>/dev/null | count_lines)
    type_count=$(find "$contracts/types" -name "$entity*.ts" 2>/dev/null | count_lines)
    printf '  %-20s schema:yes  dto:%-4s type:%s\n' "$entity" "$(yes_or_no "$dto_count")" "$(yes_or_no "$type_count")"
  done
}

# One line per contract package: how many imports each app has, and the two that should not exist.
consumption_per_app() {
  local package app app_name imports line
  local package_dir
  for package_dir in "$contracts"/*/; do
    [ -d "$package_dir" ] || continue
    package=$(basename "$package_dir")
    line="  $scope/$(printf '%-12s' "$package")"
    for app in "$apps"/*/; do
      app_name=$(basename "$app")
      imports=$(grep -rho "$scope/$package\b" "$app/src" 2>/dev/null | count_lines)
      line="$line $app_name:$imports"
      [ "$imports" != 0 ] || continue

      if [ "$package" = dto ] && ! grep -rqE "from ['\"]@nestjs" "$app/src" 2>/dev/null; then
        line="$line <-- dto in a non-Nest app"
      fi
      if [ "$package" = test-utils ] && grep -rqE "$scope/test-utils" "$app/src" \
          --include='*.ts' --include='*.tsx' --exclude='*.spec.*' --exclude='*.test.*' --exclude-dir='__tests__' 2>/dev/null; then
        line="$line <-- test-utils in app code"
      fi
    done
    echo "$line"
  done
}

files_missing_from_a_barrel() {
  local package package_dir barrel file name
  for package_dir in "$contracts"/*/; do
    [ -d "$package_dir" ] || continue
    package=$(basename "$package_dir")
    barrel="$contracts/$package/src/index.ts"
    [ -f "$barrel" ] || continue
    for file in "$contracts/$package"/src/lib/*.ts; do
      [ -e "$file" ] || continue
      name=$(basename "$file" .ts)
      case "$name" in
        *.spec|*.test) continue ;;
      esac
      grep -qF -e "./lib/$name'" -e "./lib/$name\"" "$barrel" || printf '  %s/src/lib/%s.ts not exported from index.ts\n' "$package" "$name"
    done
  done
}

# Prints each Prisma enum value that no z.enum([...]) in the schemas package lists.
enum_drift() {
  # Flatten every schema file in bash with quoted paths; awk receives the text
  # as data. Building a shell command string inside awk would let a path with
  # a quote in it run as shell.
  local zod_values
  zod_values=$(find "$contracts/schemas/src" -name '*.ts' -exec cat {} + 2>/dev/null | tr '\n' ' ' \
    | grep -oE "z\.enum\(\[[^]]*\]" | grep -oE "['\"][A-Za-z_][A-Za-z0-9_]*['\"]" | tr -d "'\"" | sort -u | paste -sd' ' -)

  awk -v zod_values="$zod_values" '
    BEGIN {
      count = split(zod_values, values, " ")
      for (i = 1; i <= count; i++) in_zod[values[i]] = 1
    }
    /^enum [A-Za-z]+/ { enum = $2; next }
    enum != "" && /^}/ { enum = ""; next }
    enum != "" && /^  [A-Z][A-Z0-9_]*/ {
      if (!($1 in in_zod))
        printf "  %s.%s exists in Prisma but in no schema enum — a row carrying it fails serialization\n", enum, $1
    }
  ' "${prisma_files[@]}"
}

echo
echo "=== chain coverage (schema → dto → type)"
chain_coverage | cap

if [ -n "$apps" ]; then
  echo
  echo "=== consumption per app (nothing usually enforces these boundaries)"
  consumption_per_app | cap
fi

echo
echo "=== backend-only imports inside client-consumed packages (must be empty)"
grep -rnE "from ['\"](node:[^'\"]*|@nestjs/[^'\"]*|@prisma/[^'\"]*|(fs|path|crypto|buffer|express|fastify)(/[^'\"]*)?)['\"]" \
  "$contracts"/schemas/src "$contracts"/types/src "$contracts"/utils/src --include='*.ts' 2>/dev/null \
  | grep -v node_modules | while IFS= read -r line; do printf '%s\n' "${line#"$root"/}"; done | indent | cap

echo
echo "=== zod entry points in use (must be one)"
grep -rhoE "from ['\"]zod(/v[34])?['\"]" "$contracts" ${apps:+"$apps"} --include='*.ts' --include='*.tsx' 2>/dev/null | tr '"' "'" | sort | uniq -c | indent

echo
echo "=== files missing from a barrel"
files_missing_from_a_barrel | cap

prisma_files=()
while IFS= read -r file; do [ -n "$file" ] && prisma_files+=("$file"); done < <(
  find "$root" -maxdepth 5 -name '*.prisma' -not -path '*/node_modules/*' -not -path '*/migrations/*' 2>/dev/null | head -50)
if [ ${#prisma_files[@]} -gt 0 ] && [ -d "$contracts/schemas" ]; then
  echo
  echo "=== Prisma ↔ schema enum drift (enums are hand-mirrored; nothing enforces it)"
  enum_drift | cap
  echo "  (values covered by any schema enum are not listed; split create/response enums are expected)"
fi
