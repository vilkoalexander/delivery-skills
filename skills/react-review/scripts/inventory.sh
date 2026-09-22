#!/usr/bin/env bash
# Live shared-code inventory for react-review. Prints what actually exists right
# now under the conventional shared layers, so the review never recommends
# building something that already ships.
#
# Usage: scripts/inventory.sh [src-root]
#   src-root defaults to the first of: ./src, apps/*/src, packages/*/src.
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
src="${1:-}"
if [ -z "$src" ]; then
  for c in "$root/src" "$root"/apps/*/src "$root"/packages/*/src; do
    [ -d "$c" ] && { src="$c"; break; }
  done
fi
[ -n "$src" ] && [ -d "$src" ] || { echo "src root not found — pass it: inventory.sh <src-dir>" >&2; exit 1; }
echo "src root: ${src#$root/}"

# One line per module: name, exported symbols, and the first line of its doc
# comment when it has one.
list() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.tsx "$dir"/*.ts; do
    [ -e "$f" ] || continue
    local base exports doc
    base=$(basename "$f")
    case "$base" in index.ts|index.tsx|*.spec.*|*.test.*) continue;; esac
    exports=$( { grep -oE 'export (function|const|type|default function) [A-Za-z0-9_]+' "$f" \
                   | sed -E 's/^export (function|const|type|default function) //'
                 grep -oE 'export (type )?\{[^}]*\}' "$f" \
                   | sed -E 's/export (type )?\{//; s/\}//; s/,/\n/g' | tr -d ' '
               } 2>/dev/null | grep -v '^$' | sort -u | paste -sd, - || true)
    doc=$(grep -m1 -oE '^ \*[[:space:]]+[A-Z].*' "$f" | sed -E 's/^ \*[[:space:]]+//' | cut -c1-72)
    printf '  %-28s %s\n' "$base" "${exports:-—}"
    [ -n "$doc" ] && printf '  %-28s   ↳ %s\n' "" "$doc"
  done
}

for layer in components/ui components ui hooks lib utils constants shared; do
  [ -d "$src/$layer" ] || continue
  echo
  echo "=== $layer"
  list "$src/$layer"
done

if [ -d "$src/features" ]; then
  echo
  echo "=== feature-local (reused within one feature only)"
  find "$src/features" -type d \( -name components -o -name hooks -o -name lib \) 2>/dev/null \
    | sed "s|$src/||" | sort | sed 's/^/  /'
fi

echo
echo "Reinvention check: does the file under review rebuild any of the above?"
