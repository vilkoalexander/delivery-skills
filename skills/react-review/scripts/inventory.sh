#!/usr/bin/env bash
# Live shared-code inventory for react-review. Prints what actually exists right
# now under the conventional shared layers, so the review never recommends
# building something that already ships.
#
# Usage: scripts/inventory.sh [src-root]
#   src-root defaults to the first of: ./src, apps/*/src, packages/*/src.
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

# Output is bounded: INVENTORY_LIMIT lines per section (default 40), overflow
# reported as a count. INVENTORY_DOCS=1 adds doc-comment lines where supported.
show_docs="${INVENTORY_DOCS:-0}"
limit="${INVENTORY_LIMIT:-40}"

cap() {
  awk -v limit="$limit" '
    NR <= limit { print; next }
    END { if (NR > limit) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR - limit, limit }
  '
}

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
src="${1:-}"
if [ -z "$src" ]; then
  for candidate in "$root/src" "$root"/apps/*/src "$root"/packages/*/src; do
    if [ -d "$candidate" ]; then
      src="$candidate"
      break
    fi
  done
fi
if [ -z "$src" ] || [ ! -d "$src" ]; then
  echo "src root not found — pass it: inventory.sh <src-dir>" >&2
  exit 1
fi
echo "src root: ${src#$root/}"

# Prints the names a module exports, comma-separated: declarations and `export { … }` lists.
exported_names() {
  local declaration='export (function|const|type|default function) '
  {
    grep -oE "${declaration}[A-Za-z0-9_]+" "$1" | sed -E "s/^$declaration//"
    grep -oE 'export (type )?\{[^}]*\}' "$1" | sed -E 's/export (type )?\{//; s/\}//' | tr ',' '\n' | tr -d ' '
  } 2>/dev/null | grep -v '^$' | sort -u | paste -sd, -
}

# One line per module: name, exported symbols, and the first line of its doc
# comment when it has one.
list_modules() {
  local dir=$1 file name exports doc
  for file in "$dir"/*.tsx "$dir"/*.ts; do
    [ -e "$file" ] || continue
    name=$(basename "$file")
    case "$name" in
      index.ts|index.tsx|*.spec.*|*.test.*) continue ;;
    esac

    exports=$(exported_names "$file")
    printf '  %-28s %s\n' "$name" "${exports:-—}"

    if [ "$show_docs" = 1 ]; then
      doc=$(grep -m1 -oE '^ \*[[:space:]]+[A-Z].*' "$file" | sed -E 's/^ \*[[:space:]]+//' | cut -c1-72)
      [ -n "$doc" ] && printf '  %-28s   ↳ %s\n' "" "$doc"
    fi
  done
}

for layer in components/ui components ui hooks lib utils constants shared; do
  [ -d "$src/$layer" ] || continue
  echo
  echo "=== $layer"
  list_modules "$src/$layer" | cap
done

if [ -d "$src/features" ]; then
  echo
  echo "=== feature-local (reused within one feature only)"
  find "$src/features" -type d \( -name components -o -name hooks -o -name lib \) 2>/dev/null \
    | while IFS= read -r dir; do printf '%s\n' "${dir#"$src"/}"; done | sort | sed 's/^/  /' | cap
fi

echo
echo "Reinvention check: does the file under review rebuild any of the above?"
