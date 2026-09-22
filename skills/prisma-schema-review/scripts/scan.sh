#!/usr/bin/env bash
# Mechanical pre-scan for prisma-schema-review. Works on a *.prisma file or a
# migration.sql. Heuristic — flags, not a verdict.
#
# Nothing in a Prisma toolchain checks any of this: prisma validate covers
# syntax and relation well-formedness, not tenant scoping, money types, ledger
# immutability or lock duration.
#
# Usage: scan.sh <file.prisma | migration.sql>
# Env:   TENANT_FIELD   tenant key column (default: tenantId). Set to "" for a
#                       single-tenant schema to skip the scoping checks.
#        EXEMPT_MODELS  models deliberately without the tenant key, |-separated
#        LEDGER_TABLES  append-only tables by @@map name, |-separated
set -uo pipefail

file="${1:-}"
[ -z "$file" ] && { echo "usage: scan.sh <file.prisma|migration.sql>" >&2; exit 1; }
[ -f "$file" ] || { echo "not found: $file" >&2; exit 1; }

TENANT="${TENANT_FIELD-tenantId}"
EXEMPT="${EXEMPT_MODELS:-__none__}"
LEDGER="${LEDGER_TABLES:-__none__}"

hits=0
report() {
  local out
  out=$(grep -nE "$2" "$file")
  if [ -n "$out" ]; then printf '## %s\n%s\n\n' "$1" "$out"; hits=1; fi
}
emit() { printf '## %s\n%s\n\n' "$1" "$2"; hits=1; }

if [[ "$file" == *.prisma ]]; then
  # --- money types ----------------------------------------------------------
  report "Float/Decimal in the schema — money is Int minor units (Decimal only by documented decision)" \
    '\b(Float|Decimal)\b'
  report "A stored balance column — with a ledger, balance is SUM(delta), never a column" \
    '^[[:space:]]*balance[A-Za-z]*[[:space:]]+(Int|Float|Decimal)'
  money=$(awk '
    /^[[:space:]]*(amount|price|total|unitPrice|paid|fee|cost)[A-Za-z]*[[:space:]]+(Int|Float|Decimal)/ {
      if ($1 !~ /(Minor|Cents)$/) printf "%d: %s\n", NR, $0
    }
  ' "$file")
  [ -n "$money" ] && emit "A money-ish field without a minor-unit suffix (Minor/Cents) — the suffix is how units are legible at every call site" "$money"

  # --- tenant scoping -------------------------------------------------------
  if [ -n "$TENANT" ]; then
    scope=$(awk -v exempt="$EXEMPT" -v tenant="$TENANT" '
      /^model [A-Za-z]+ / { m = $2; ws = 0; delete keys; nk = 0; next }
      /^}/ {
        if (m != "") {
          if (!ws && m !~ ("^(" exempt ")$"))
            printf "  model %s has no %s — must be a documented exemption\n", m, tenant
          for (i = 1; i <= nk; i++)
            if (ws && keys[i] !~ ("\\[" tenant) && keys[i] !~ /^\(unique\)/)
              printf "  model %s: index %s does not lead with %s\n", m, keys[i], tenant
        }
        m = ""; next
      }
      m != "" {
        if ($1 == tenant) ws = 1
        if ($0 ~ /@@(index|unique)\(\[/) {
          s = $0; kind = ($0 ~ /@@unique/) ? "(unique)" : ""
          sub(/.*(@@index|@@unique)/, "", s); sub(/\).*/, ")", s); keys[++nk] = kind s
        }
      }
    ' "$file")
    [ -n "$scope" ] && emit "Tenant scoping — verify each against the project's documented exemptions" "$scope"
  fi

  # --- relations ------------------------------------------------------------
  norel=$(grep -nE '@relation\(' "$file" | grep -v 'onDelete:' | grep -vE '\[\][[:space:]]*@relation' || true)
  [ -n "$norel" ] && emit "@relation without an explicit onDelete — state the intent, do not inherit the default" "$norel"

  # --- append-only ----------------------------------------------------------
  if [ "$LEDGER" != "__none__" ] && grep -qE "@@map\(\"($LEDGER)\"\)" "$file"; then
    report "@updatedAt in a file holding a ledger model — ledger rows are never updated" '@updatedAt'
  fi
  report "Ledger-looking model (delta field) — confirm it has no @updatedAt and every FK is Restrict" \
    '^[[:space:]]*delta[[:space:]]+Int'

  # --- dates ----------------------------------------------------------------
  dt=$(grep -nE '^[[:space:]]*[A-Za-z]*[Dd]ate[A-Za-z]*[[:space:]]+DateTime' "$file" \
    | grep -vE '[A-Za-z]+At[[:space:]]+DateTime' | grep -v '@db.Date' || true)
  [ -n "$dt" ] && emit "A calendar date stored as a full timestamp — use @db.Date so no timezone can shift it" "$dt"

  # --- id strategy ----------------------------------------------------------
  ids=$(grep -oE '@id[[:space:]]+@default\([a-z]+\(' "$file" | sort -u | wc -l | tr -d ' ')
  [ "$ids" -gt 1 ] && emit "More than one id strategy in this file — match the siblings" "$(grep -nE '@id[[:space:]]+@default' "$file")"

else
  # --- migration.sql --------------------------------------------------------
  report "Float/numeric column — money is INTEGER minor units" \
    'DOUBLE PRECISION|\bREAL\b|NUMERIC|DECIMAL'
  report "NOT NULL added without a DEFAULT — fails on a populated table; go nullable, backfill, then SET NOT NULL" \
    'ADD COLUMN[^;]*NOT NULL([^;]*)$'
  destructive=$(awk '
    /ADD CONSTRAINT "?[A-Za-z_]+"?/ { c = $0; sub(/.*ADD CONSTRAINT "?/, "", c); sub(/"?[ (].*/, "", c); readded[c] = 1 }
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (L[i] ~ /DROP CONSTRAINT/) {
          c = L[i]; sub(/.*DROP CONSTRAINT "?/, "", c); sub(/"?[;, ].*/, "", c)
          if (c in readded) continue   # an FK rewrite, not data loss
        } else if (L[i] !~ /DROP (COLUMN|TABLE)|ALTER COLUMN[^;]*TYPE/) continue
        printf "%d: %s\n", i, L[i]
      }
    }
  ' "$file")
  [ -n "$destructive" ] && emit "Destructive statement — confirm the data loss is intended and documented" "$destructive"
  report "CONCURRENTLY — cannot run inside a Prisma migration transaction" 'CONCURRENTLY'
  uniq=$(awk '
    /CREATE TABLE "?[a-z_]+"?/ { t = $0; sub(/.*CREATE TABLE "?/, "", t); sub(/"?[ (].*/, "", t); new[t] = 1 }
    /CREATE UNIQUE INDEX|ADD CONSTRAINT.*UNIQUE/ {
      t = $0; sub(/.*ON "?/, "", t); sub(/"?[ (].*/, "", t)
      if (!(t in new)) printf "%d: %s\n", NR, $0
    }
  ' "$file")
  [ -n "$uniq" ] && emit "UNIQUE added to a pre-existing table — verify production data holds no duplicates" "$uniq"

  if [ "$LEDGER" != "__none__" ]; then
    led=$(grep -nE "(UPDATE|DELETE FROM)[[:space:]]+\"?($LEDGER)" "$file" || true)
    [ -n "$led" ] && emit "UPDATE/DELETE on a ledger table — the ledger is append-only; insert a compensating row instead" "$led"
  fi

  enumadd=$(awk '
    /ALTER TYPE .* ADD VALUE/ { v = $0; sub(/.*ADD VALUE '"'"'/, "", v); sub(/'"'"'.*/, "", v); added[v] = NR }
    { for (v in added) if (NR > added[v] && $0 ~ ("'"'"'" v "'"'"'")) printf "%d: %s uses '"'"'%s'"'"' added at line %d\n", NR, $0, v, added[v] }
  ' "$file")
  [ -n "$enumadd" ] && emit "An enum value is used in the same migration that adds it — Postgres requires the adding transaction to commit first; split into two migrations" "$enumadd"

  if [ -n "$TENANT" ]; then
    idx=$(grep -nE 'CREATE (UNIQUE )?INDEX' "$file" | grep -vE "\(\"$TENANT\"" || true)
    [ -n "$idx" ] && emit "Index whose leading column is not $TENANT — verify the table is genuinely non-tenant" "$idx"
  fi
fi

[ "$hits" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
