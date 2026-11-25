#!/usr/bin/env bash
# Live inventory for htmx-review: the htmx version and how it is loaded,
# extensions, which major's syntax the templates use, the partials that
# already exist, targets that match no id, and the server side of the
# contract.
#
# Usage: scripts/inventory.sh [root]
#   root is the repository or application directory. Defaults to the git
#   root of the current directory.
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

or_none() {
  awk '{ print; seen = 1 } END { if (!seen) print "  none" }'
}

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
if [ ! -d "$root" ]; then
  echo "not a directory: $root" >&2
  exit 1
fi
cd "$root" || exit 1
echo "root: $root"

skip=(-not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' -not -path '*/dist/*' -not -path '*/testdata/*')
templates=$(find . \( -name '*.html' -o -name '*.gohtml' -o -name '*.tmpl' -o -name '*.templ' \) "${skip[@]}" 2>/dev/null | sed 's|^\./||' | sort)
go_sources=$(find . -name '*.go' "${skip[@]}" -not -name '*_templ.go' -not -name '*_test.go' 2>/dev/null | sed 's|^\./||' | sort)

template_files=()
go_files=()
while IFS= read -r file; do [ -n "$file" ] && template_files+=("$file"); done <<< "$templates"
while IFS= read -r file; do [ -n "$file" ] && go_files+=("$file"); done <<< "$go_sources"

# /dev/null keeps grep off stdin when the list is empty.
in_templates() { grep "$@" ${template_files[@]+"${template_files[@]}"} /dev/null 2>/dev/null; }
in_go()        { grep "$@" ${go_files[@]+"${go_files[@]}"} /dev/null 2>/dev/null; }

count() {
  in_templates -hoE -- "$1" | wc -l | tr -d ' '
}

echo
echo "=== htmx (2 and 4 differ in defaults, attribute names and events)"
{
  in_templates -noE '<script[^>]*(htmx|idiomorph)[^>]*>' | sed -E 's/<script[^>]*src="([^"]*)"[^>]*>/\1/'
  grep -hoE '"(htmx\.org|htmx-ext-[a-z-]+|idiomorph)": *"[^"]+"' package.json ./*/package.json 2>/dev/null
  find . -name 'htmx*.js' "${skip[@]}" 2>/dev/null | while IFS= read -r js; do
    printf '%s  version %s\n' "${js#./}" "$(grep -oE 'version: ?["'"'"'][0-9.]+' "$js" | grep -oE '[0-9.]+$' | head -1)"
  done
} | indent | cap | or_none
in_templates -nE '<meta[^>]*name="htmx-config"' | sed -E 's/[[:space:]]+/ /g' | indent | cap
in_templates -hoE 'hx-ext="[^"]*"' | sort | uniq -c | sort -rn | indent

echo
echo "=== which major the templates are written for"
printf '  %-58s %s\n' "htmx 2 only: hx-disabled-elt, hx-ext, htmx 2 event names" "$(count 'hx-disabled-elt=|hx-ext=|htmx:[a-z]+[A-Z][A-Za-z]*|hx-on::?[a-z]+-[a-z]+')"
printf '  %-58s %s\n' "htmx 4 only: :inherited, hx-ignore, hx-status:, colon events " "$(count 'hx-[a-z-]+:inherited|hx-ignore|hx-status:|htmx:[a-z]+:[a-z]+|hx-(action|config)=')"
printf '  %-58s %s\n' "htmx 1 leftovers: hx-on=\"\", hx-ws, hx-sse" "$(count 'hx-on="|[[:space:]]hx-(ws|sse)="')"

echo
echo "=== templates"
printf '%s\n' "$templates" | awk -F. 'NF > 1 { kinds[$NF]++ } END { for (kind in kinds) printf "  .%-8s %d\n", kind, kinds[kind] }' | sort | or_none
in_templates -lE '<html' | sed 's/^/  layout    /' | cap

echo
echo "=== partials and components — do not rebuild"
{
  in_templates -oE '\{\{-? *(define|block) "[^"]+"' | sed -E 's/^([^:]+):\{\{-? *(define|block) "([^"]+)"/\3  \1/'
  in_templates -oE '^templ (\([^)]*\) )?[A-Za-z0-9_]+\(' | sed -E 's/^([^:]+):templ (\([^)]*\) )?([A-Za-z0-9_]+)\(/\3  \1/'
} | sort -u | awk '{ printf "  %-32s %s\n", $1, $2 }' | cap | or_none

echo
echo "=== attributes in use"
in_templates -hoE '[[:space:]]hx-[a-z-]+(:[a-z0-9:-]+)?=' | sed -E 's/^[[:space:]]+//; s/=$//' | sort | uniq -c | sort -rn | indent | cap | or_none

echo
echo "=== hx-target ids that no template defines"
defined=$(in_templates -hoE '[[:space:]]id="[A-Za-z0-9_-]+"' | sed -E 's/.*id="([^"]+)"/\1/' | sort -u)
dynamic=$(in_templates -hoE '[[:space:]]id="[A-Za-z0-9_-]*\{' | sed -E 's/.*id="([^{]*)\{/\1/' | sort -u)
in_templates -oE 'hx-(target|indicator|include|select-oob|swap-oob)(:inherited)?="[^"]*#[A-Za-z0-9_-]+"' \
  | sed -E 's/^([^:]+):.*#([A-Za-z0-9_-]+)"$/\2 \1/' | sort -u | while read -r id where; do
    grep -qxF -- "$id" <<< "$defined" && continue
    known=0
    while IFS= read -r prefix; do
      [ -n "$prefix" ] && [ "${id#"$prefix"}" != "$id" ] && known=1
    done <<< "$dynamic"
    [ "$known" = 0 ] && printf '  #%-28s %s\n' "$id" "$where"
  done | cap | or_none

echo
echo "=== server side of the contract"
reads=$(in_go -lE 'HX-Request' | paste -sd' ' -)
echo "  reads HX-Request: ${reads:-none}"
if [ -n "$reads" ]; then
  # shellcheck disable=SC2086
  varies=$(grep -lE '"Vary"' $reads 2>/dev/null | paste -sd' ' -)
  echo "  sets Vary there:  ${varies:-none}"
fi
in_go -hoE '"HX-[A-Za-z-]+"' | sort | uniq -c | sort -rn | indent | cap
if in_go -qE 'CrossOriginProtection|csrf\.Protect|nosurf\.New|filippo\.io/csrf'; then
  in_go -lE 'CrossOriginProtection|csrf\.Protect|nosurf\.New|filippo\.io/csrf' | sed 's/^/  CSRF defence: /'
else
  echo "  CSRF defence: none found in Go"
fi
in_templates -noE 'hx-headers(:inherited)?=.[^>]*[cC][sS][rR][fF][^>]*' | cut -c1-140 | sed 's/^/  CSRF header: /' | cap
policy=$( { in_go -lE 'Content-Security-Policy'; in_templates -lE 'Content-Security-Policy'; } | paste -sd' ' -)
echo "  Content-Security-Policy: ${policy:-none found}"

echo
echo "=== other client-side code beside htmx"
printf '  %-28s %s\n' "Alpine (x-data)" "$(count '[[:space:]]x-data')"
printf '  %-28s %s\n' "hyperscript (_=\"…\")" "$(count '[[:space:]]_="')"
printf '  %-28s %s\n' "Datastar (data-on-, data-signals)" "$(count '[[:space:]]data-(on-|signals)')"
printf '  %-28s %s\n' "inline <script> blocks" "$(count '<script>')"
