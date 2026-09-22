#!/usr/bin/env bash
# Live schema inventory for prisma-schema-review: every model with its tenant
# scoping, index leading columns, money fields and FK delete actions.
#
# Usage: scripts/inventory.sh [schema-dir-or-file]
#   Finds schema.prisma or prisma/models/*.prisma under the repo when omitted.
# Env:   TENANT_FIELD  tenant key column (default: tenantId; "" = single-tenant)
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TENANT="${TENANT_FIELD-tenantId}"
target="${1:-}"
if [ -z "$target" ]; then
  target=$(find "$PWD" "$root" -maxdepth 5 -name '*.prisma' -not -path '*/node_modules/*' -not -path '*/migrations/*' 2>/dev/null | head -1 | xargs -I{} dirname {})
fi
[ -n "$target" ] && [ -e "$target" ] || { echo "no .prisma files found — pass a dir or file" >&2; exit 1; }
if [ -d "$target" ]; then files=$(find "$target" -name '*.prisma' -not -path '*/migrations/*' | sort); else files="$target"; fi
echo "schema: $(echo "$files" | sed "s|$root/||" | paste -sd' ' -)"

awk -v tenant="$TENANT" '
  /^model [A-Za-z]+ / {
    name = $2; models[++n] = name
    scoped[name] = 0; money[name] = ""; idx[name] = ""; upd[name] = 0; mapped[name] = ""; order[name] = ""
    inmodel = 1; next
  }
  /^}/ { inmodel = 0; next }
  inmodel {
    if (tenant != "" && $1 == tenant) scoped[name] = 1
    if ($0 ~ /@updatedAt/) upd[name] = 1
    if ($1 ~ /(Minor|Cents)$/ || $1 == "currency" || $1 == "delta") money[name] = money[name] " " $1
    if ($0 ~ /@@index\(|@@unique\(/) {
      s = $0; sub(/.*\(\[/, "", s); sub(/\].*/, "", s); gsub(/ /, "", s)
      kind = ($0 ~ /@@unique/) ? "U" : "I"
      idx[name] = idx[name] "\n      " kind " [" s "]"
    }
    if ($0 ~ /@relation\(/ && $0 ~ /onDelete:/) {
      a = $0; sub(/.*onDelete: */, "", a); sub(/[)., ].*/, "", a)
      cnt[name "|" a]++
      if (!(name "|" a in seen)) { seen[name "|" a] = 1; order[name] = order[name] " " a }
    }
    if ($0 ~ /@@map\(/) { m = $0; sub(/.*@@map\("/, "", m); sub(/".*/, "", m); mapped[name] = m }
  }
  END {
    for (i = 1; i <= n; i++) {
      m = models[i]
      printf "\n%s  (%s)\n", m, mapped[m] ? mapped[m] : "no @@map"
      if (tenant != "")
        printf "  tenant:   %s%s\n", scoped[m] ? tenant : "NONE — must be a documented exemption", \
               upd[m] ? "   (+@updatedAt: mutable)" : "   (no @updatedAt)"
      else
        printf "  mutable:  %s\n", upd[m] ? "yes (@updatedAt)" : "no @updatedAt"
      if (money[m] != "") printf "  money:   %s\n", money[m]
      if (order[m] != "") {
        line = ""; k = split(order[m], acts, " ")
        for (j = 1; j <= k; j++) line = line sprintf(" %s×%d", acts[j], cnt[m "|" acts[j]])
        printf "  onDelete:%s\n", line
      }
      if (idx[m] != "") printf "  keys:%s\n", idx[m]
    }
  }
' $files

if [ -n "$TENANT" ]; then
  echo
  echo "=== indexes whose leading column is not $TENANT (verify each is intentional)"
  grep -hnE '@@(index|unique)\(\[' $files | grep -vE "@@(index|unique)\(\[$TENANT" | sed 's/^/  /'
fi

echo
echo "=== enums"
grep -hE '^enum [A-Za-z]+' $files | sed 's/^/  /'

mig=$(find "$(dirname "$(echo "$files" | head -1)")/.." "$root" -maxdepth 4 -type d -name migrations -path '*prisma*' 2>/dev/null | head -1)
if [ -n "$mig" ]; then
  echo
  echo "=== migrations (newest last) — never edit an applied one"
  ls "$mig" | grep -v migration_lock | tail -6 | sed 's/^/  /'
fi
