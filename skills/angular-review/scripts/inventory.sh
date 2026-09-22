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

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
targets=()
if [ -n "${1:-}" ]; then
  targets=("$1")
else
  for base in "$PWD" "$root"; do
    for c in "$base/libs" "$base/packages" "$base"/src/app/shared "$base"/src/app/core "$base"/src/app/ui; do
      [ -d "$c" ] && targets+=("$c")
    done
    [ "${#targets[@]}" -gt 0 ] && break
  done
fi
[ "${#targets[@]}" -gt 0 ] || { echo "no shared layer found — pass one: inventory.sh <dir>" >&2; exit 1; }

# One line per unit: kind, selector/name, class, first doc line.
describe() {
  local f="$1" kind sel cls doc
  if   grep -q '@Component(' "$f"; then kind=component
  elif grep -q '@Directive(' "$f"; then kind=directive
  elif grep -q '@Pipe(' "$f"; then kind=pipe
  elif grep -qE "providedIn:[[:space:]]*'root'" "$f"; then kind=service
  else return 0; fi
  sel=$(grep -oE "(selector|name):[[:space:]]*['\"][^'\"]+['\"]" "$f" | head -1 | sed -E "s/.*['\"]([^'\"]+)['\"]/\1/")
  cls=$(grep -oE 'export class [A-Za-z0-9_]+' "$f" | head -1 | sed 's/export class //')
  doc=$(grep -m1 -oE '^ \*[[:space:]]+[A-Z].*' "$f" | sed -E 's/^ \*[[:space:]]+//' | cut -c1-64)
  printf '  %-10s %-32s %s\n' "$kind" "${sel:-—}" "$cls"
  [ -n "$doc" ] && printf '  %-10s %-32s   ↳ %s\n' "" "" "$doc"
}

for t in "${targets[@]}"; do
  echo "=== ${t#$PWD/}"
  while IFS= read -r f; do describe "$f"; done < <(
    find "$t" -type f \( -name '*.ts' \) ! -name '*.spec.ts' ! -name '*.stories.ts' \
      ! -path '*/node_modules/*' ! -name 'index.ts' ! -name '*.module.ts' ! -name '*.routes.ts' | sort)
  echo
done

# Generation markers across the scanned roots — tells the reviewer which
# generation the project is on before it judges one file against it.
echo "=== API generation across scanned roots (counts of files)"
cnt() { grep -rlE "$1" "${targets[@]}" --include='*.ts' --include='*.html' 2>/dev/null | grep -v node_modules | wc -l | tr -d ' '; }
printf '  %-38s %s\n' "@Input()/@Output() decorators"        "$(cnt '@(Input|Output)\(')"
printf '  %-38s %s\n' "input()/output()/model() signals"      "$(cnt '\b(input|output|model)(\.required)?<')"
printf '  %-38s %s\n' "constructor(private …) injection"     "$(cnt 'constructor\([^)]*(private|public|protected|readonly)[[:space:]]')"
printf '  %-38s %s\n' "inject() function"                    "$(cnt '= inject\(')"
printf '  %-38s %s\n' "*ngIf/*ngFor structural directives"   "$(cnt '\*ng(If|For)')"
printf '  %-38s %s\n' "@if/@for built-in control flow"       "$(cnt '@(if|for)[[:space:]]*\(')"
printf '  %-38s %s\n' "NgModule declarations"                "$(cnt 'declarations:[[:space:]]*\[')"
printf '  %-38s %s\n' "OnPush components"                    "$(cnt 'ChangeDetectionStrategy\.OnPush')"
echo
echo "Reinvention check: does the file under review rebuild any of the above?"
