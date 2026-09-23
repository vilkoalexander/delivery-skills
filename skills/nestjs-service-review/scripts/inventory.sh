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
# reported as a count. INVENTORY_DOCS=1 adds doc-comment lines where supported.
LIMIT="${INVENTORY_LIMIT:-40}"
DOCS="${INVENTORY_DOCS:-0}"
cap() { awk -v n="$LIMIT" 'NR<=n{print;next} END{if(NR>n) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR-n, n}'; }

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
app="${1:-}"
if [ -z "$app" ]; then
  first=$(find "$PWD" "$root" -maxdepth 6 -name 'app.module.ts' -not -path '*/node_modules/*' 2>/dev/null | head -1)
  [ -n "$first" ] && app=$(dirname "$first")
fi
[ -n "$app" ] && [ -d "$app" ] || { echo "app src not found — pass it: inventory.sh <dir>" >&2; exit 1; }
echo "app src: ${app#$root/}"

echo
echo "=== shared primitives — do not rebuild"
{ for f in $(find "$app" -maxdepth 3 -type d \( -name shared -o -name common -o -name core \) 2>/dev/null); do
  for t in $(find "$f" -name '*.ts' ! -name '*.spec.ts' ! -name 'index.ts' ! -name '*.module.ts' | sort); do
    ex=$(grep -oE 'export (async )?(function|const|interface|type|class|enum) [A-Za-z0-9_]+' "$t" \
      | sed -E 's/^export (async )?(function|const|interface|type|class|enum) //' | sort -u | paste -sd, -)
    [ -n "$ex" ] && printf '  %-44s %s\n' "${t#$app/}" "$ex"
  done
done; } | cap

echo
echo "=== modules"
{ for m in $(find "$app" -name '*.module.ts' ! -name 'app.module.ts' | sort); do
  d=$(dirname "$m"); name=$(basename "$m" .module.ts)
  svc=$(find "$d" -name '*.service.ts' | wc -l | tr -d ' ')
  ctl=$(find "$d" -name '*.controller.ts' | wc -l | tr -d ' ')
  spc=$(find "$d" -name '*.spec.ts' | wc -l | tr -d ' ')
  printf '  %-24s services:%-3s controllers:%-3s specs:%s\n' "$name" "$svc" "$ctl" "$spc"
done; } | cap

echo
# REVIEW_FILES (space-separated) restricts the check to the files under review;
# otherwise every unit in the app is checked.
if [ -n "${REVIEW_FILES:-}" ]; then
  echo "=== missing specs among REVIEW_FILES (a new unit needs one)"
  units=$(printf '%s\n' $REVIEW_FILES | grep -E '\.(service|controller)\.ts$' | sort)
else
  echo "=== missing specs (a new unit here needs one)"
  units=$(find "$app" \( -name '*.service.ts' -o -name '*.controller.ts' \) | sort)
fi
missing=$(while IFS= read -r f; do
  [ -n "$f" ] || continue
  b=$(basename "$f" .ts); d=$(dirname "$f")
  [ -f "$d/$b.spec.ts" ] || [ -f "$d/__tests__/$b.spec.ts" ] || printf '  %s\n' "${f#$app/}"
done <<< "$units")
if [ -n "$missing" ]; then echo "$missing" | cap; else echo "  none"; fi

echo
echo "=== guards / interceptors / decorators in use"
grep -rhoE '@(UseGuards|UseInterceptors)\([^)]*\)' "$app" --include='*.controller.ts' 2>/dev/null | sort | uniq -c | sort -rn | sed 's/^/  /' | cap

tu=$(find "$root" -maxdepth 4 -type d -name 'test-utils' -not -path '*/node_modules/*' 2>/dev/null | head -1)
if [ -n "$tu" ]; then
  echo
  echo "=== test-utils available to specs (${tu#$root/})"
  grep -rhoE 'export (async )?(function|const) [A-Za-z0-9_]+' "$tu" 2>/dev/null \
    | sed -E 's/^export (async )?(function|const) //' | sort -u | sed 's/^/  /' | cap
fi
