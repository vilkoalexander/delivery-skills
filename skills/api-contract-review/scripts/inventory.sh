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
# reported as a count. INVENTORY_DOCS=1 adds doc-comment lines where supported.
LIMIT="${INVENTORY_LIMIT:-40}"
DOCS="${INVENTORY_DOCS:-0}"
cap() { awk -v n="$LIMIT" 'NR<=n{print;next} END{if(NR>n) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR-n, n}'; }

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
lib="${1:-}"
if [ -z "$lib" ]; then
  for c in "$root/libs/shared" "$root/packages/shared" "$root/packages/contracts" "$root/packages" "$root/libs"; do
    [ -d "$c/schemas" ] || [ -d "$c/types" ] && { lib="$c"; break; }
  done
fi
[ -n "$lib" ] && [ -d "$lib" ] || { echo "contract dir not found — pass it: inventory.sh <dir>" >&2; exit 1; }
echo "contract dir: ${lib#$root/}"
apps=$(find "$root" -maxdepth 2 -type d -name apps -not -path '*/node_modules/*' | head -1)
scope=$(grep -ohE '"name": *"@[a-z0-9-]+/' "$lib"/*/package.json 2>/dev/null | head -1 | grep -oE '@[a-z0-9-]+' || echo '@shared')

echo
echo "=== chain coverage (schema → dto → type)"
{ for s in "$lib"/schemas/src/lib/*.schema.ts "$lib"/schemas/src/*.schema.ts; do
  [ -e "$s" ] || continue
  e=$(basename "$s" .schema.ts)
  d=$(find "$lib/dto" -name "$e.dto.ts" 2>/dev/null | wc -l | tr -d ' ')
  t=$(find "$lib/types" -name "$e*.ts" 2>/dev/null | wc -l | tr -d ' ')
  printf '  %-20s schema:yes  dto:%-4s type:%s\n' "$e" \
    "$([ "$d" != 0 ] && echo yes || echo NO)" \
    "$([ "$t" != 0 ] && echo yes || echo NO)"
done; } | cap

if [ -n "$apps" ]; then
  echo
  echo "=== consumption per app (nothing usually enforces these boundaries)"
  { for l in $(ls "$lib"); do
    [ -d "$lib/$l" ] || continue
    line="  $scope/$(printf '%-12s' "$l")"
    for a in "$apps"/*/; do
      n=$(basename "$a")
      c=$(grep -rho "$scope/$l\b" "$a/src" 2>/dev/null | wc -l | tr -d ' ')
      line="$line $n:$c"
      [ "$l" = "dto" ] && [ "$c" != "0" ] && ! grep -rqE "from '@nestjs" "$a/src" 2>/dev/null && line="$line <-- dto in a non-Nest app"
      [ "$l" = "test-utils" ] && [ "$c" != "0" ] && grep -rqE "$scope/test-utils" "$a/src" --include='*.ts' --include='*.tsx' --exclude='*.spec.*' --exclude='*.test.*' --exclude-dir='__tests__' 2>/dev/null && line="$line <-- test-utils in app code"
    done
    echo "$line"
  done; } | cap
fi

echo
echo "=== backend-only imports inside client-consumed packages (must be empty)"
grep -rnE "from '(node:|@nestjs|@prisma|fs|path|crypto|buffer|express|fastify)" \
  "$lib"/schemas/src "$lib"/types/src "$lib"/utils/src --include='*.ts' 2>/dev/null | grep -v node_modules | sed "s|$root/||" | sed 's/^/  /' | cap

echo
echo "=== zod entry points in use (must be one)"
grep -rhoE "from 'zod(/v[34])?'" "$lib" "$apps" --include='*.ts' --include='*.tsx' 2>/dev/null | sort | uniq -c | sed 's/^/  /'

echo
echo "=== files missing from a barrel"
{ for l in $(ls "$lib"); do
  idx="$lib/$l/src/index.ts"; [ -f "$idx" ] || continue
  for f in "$lib/$l"/src/lib/*.ts; do
    [ -e "$f" ] || continue
    b=$(basename "$f" .ts)
    case "$b" in *.spec|*.test) continue;; esac
    grep -q "\./lib/$b'" "$idx" || printf '  %s/src/lib/%s.ts not exported from index.ts\n' "$l" "$b"
  done
done; } | cap

prisma=$(find "$root" -maxdepth 5 -name '*.prisma' -not -path '*/node_modules/*' -not -path '*/migrations/*' 2>/dev/null | head -50)
if [ -n "$prisma" ] && [ -d "$lib/schemas" ]; then
  echo
  echo "=== Prisma ↔ schema enum drift (enums are hand-mirrored; nothing enforces it)"
  # Flatten every schema file in bash with quoted paths; awk receives the text
  # as data. Building a shell command string inside awk would let a path with
  # a quote in it run as shell.
  zod_values=$(find "$lib/schemas/src" -name '*.ts' -exec cat {} + 2>/dev/null | tr '\n' ' ' \
    | grep -oE "z\.enum\(\[[^]]*\]" | grep -oE "'[A-Za-z_][A-Za-z0-9_]*'" | tr -d "'" | sort -u | paste -sd' ' -)
  awk -v zodlist="$zod_values" '
    BEGIN { n = split(zodlist, arr, " "); for (i = 1; i <= n; i++) zod[arr[i]] = 1 }
    /^enum [A-Za-z]+/ { e = $2; next }
    e != "" && /^}/ { e = ""; next }
    e != "" && /^  [A-Z][A-Z0-9_]*/ {
      v = $1
      if (!(v in zod)) printf "  %s.%s exists in Prisma but in no schema enum — a row carrying it fails serialization\n", e, v
    }
  ' $prisma | cap
  echo "  (values covered by any schema enum are not listed; split create/response enums are expected)"
fi
