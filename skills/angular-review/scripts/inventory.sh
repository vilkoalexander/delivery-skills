#!/usr/bin/env bash
# Live shared-code inventory for angular-review: every component, directive,
# pipe and root-provided service under the shared layers, with its selector,
# so the review never recommends building something that already ships.
#
# Usage: scripts/inventory.sh [src-root]
#   With no argument it scans: libs/, packages/, and src/app/{shared,core,ui}
#   under the repo root. In a monorepo pass the app: inventory.sh <app>/src
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

# Output is bounded: INVENTORY_LIMIT lines per section (default 40), overflow
# reported as a count. INVENTORY_DOCS=1 adds doc-comment lines where supported.
limit="${INVENTORY_LIMIT:-40}"
show_docs="${INVENTORY_DOCS:-0}"

cap() {
  awk -v limit="$limit" '
    NR <= limit { print; next }
    END { if (NR > limit) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR - limit, limit }
  '
}

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# The directory given, else the shared layers under the current directory, else under the repo root.
layers=()
if [ -n "${1:-}" ]; then
  layers=("$1")
else
  for base in "$PWD" "$root"; do
    for layer in "$base/libs" "$base/packages" "$base/src/app/shared" "$base/src/app/core" "$base/src/app/ui"; do
      [ -d "$layer" ] && layers+=("$layer")
    done
    [ ${#layers[@]} -gt 0 ] && break
  done
fi
if [ ${#layers[@]} -eq 0 ]; then
  echo "no shared layer found — pass one: inventory.sh <dir>" >&2
  exit 1
fi

# One line per unit: kind, selector/name, class, first doc line.
describe() {
  local file=$1 kind selector class doc
  if grep -q '@Component(' "$file"; then
    kind=component
  elif grep -q '@Directive(' "$file"; then
    kind=directive
  elif grep -q '@Pipe(' "$file"; then
    kind=pipe
  elif grep -qE "providedIn:[[:space:]]*'root'" "$file"; then
    kind=service
  else
    return 0
  fi

  selector=$(grep -oE "(selector|name):[[:space:]]*['\"][^'\"]+['\"]" "$file" | head -1 | sed -E "s/.*['\"]([^'\"]+)['\"]/\1/")
  class=$(grep -oE 'export class [A-Za-z0-9_]+' "$file" | head -1 | sed 's/export class //')
  printf '  %-10s %-32s %s\n' "$kind" "${selector:-—}" "$class"

  if [ "$show_docs" = 1 ]; then
    doc=$(grep -m1 -oE '^ \*[[:space:]]+[A-Z].*' "$file" | sed -E 's/^ \*[[:space:]]+//' | cut -c1-64)
    [ -n "$doc" ] && printf '  %-10s %-32s   ↳ %s\n' "" "" "$doc"
  fi
}

source_files() {
  find "$1" -type f -name '*.ts' \
    ! -name '*.spec.ts' ! -name '*.stories.ts' ! -name 'index.ts' ! -name '*.module.ts' ! -name '*.routes.ts' \
    ! -path '*/node_modules/*' | sort
}

for layer in "${layers[@]}"; do
  echo "=== ${layer#$PWD/}"
  source_files "$layer" | while IFS= read -r file; do
    describe "$file"
  done | cap
  echo
done

# Generation markers across the scanned roots — tells the reviewer which
# generation the project is on before it judges one file against it.
files_with() {
  grep -rlE "$1" "${layers[@]}" --include='*.ts' --include='*.html' 2>/dev/null | grep -v node_modules | wc -l | tr -d ' '
}
generation() {
  printf '  %-38s %s\n' "$1" "$(files_with "$2")"
}

echo "=== API generation across scanned roots (counts of files)"
generation "@Input()/@Output() decorators"      '@(Input|Output)\('
generation "input()/output()/model() signals"   '=[[:space:]]*(input|output|model)(\.required)?(<|\()'
generation "constructor(private …) injection"   'constructor\([^)]*(private|public|protected|readonly)[[:space:]]'
generation "inject() function"                  '= inject\('
generation "*ngIf/*ngFor structural directives" '\*ng(If|For)'
generation "@if/@for built-in control flow"     '@(if|for)[[:space:]]*\('
generation "NgModule declarations"              'declarations:[[:space:]]*\['
generation "OnPush components"                  'ChangeDetectionStrategy\.OnPush'
echo
echo "Reinvention check: does the file under review rebuild any of the above?"
