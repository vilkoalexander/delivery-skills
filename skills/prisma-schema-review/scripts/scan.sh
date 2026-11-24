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
if [ -z "$file" ]; then
  echo "usage: scan.sh <file.prisma|migration.sql>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

tenant="${TENANT_FIELD-tenantId}"
exempt_models="${EXEMPT_MODELS:-__none__}"
ledger_tables="${LEDGER_TABLES:-__none__}"

found_any=0

# flag LABEL LINES — prints a finding with the lines that caused it
flag() {
  printf '## %s\n%s\n\n' "$1" "$2"
  found_any=1
}

# report LABEL REGEX — flags every line of the file that matches
report() {
  local matches
  matches=$(grep -nE "$2" "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

# ------------------------------------------------------------------ schema
# Prints the models with no tenant key, and the indexes of scoped models that do not lead with it.
tenant_scoping_gaps() {
  awk -v exempt="$exempt_models" -v tenant="$tenant" '
    /^model [A-Za-z_][A-Za-z0-9_]*[[:space:]]*\{/ {
      model = $2
      sub(/\{.*/, "", model)
      scoped = 0
      key_count = 0
      delete keys
      next
    }
    /^}/ {
      if (model != "") {
        if (!scoped && model !~ ("^(" exempt ")$"))
          printf "  model %s has no %s — must be a documented exemption\n", model, tenant
        for (i = 1; i <= key_count; i++)
          if (scoped && keys[i] !~ ("\\[" tenant) && keys[i] !~ /^\(unique\)/)
            printf "  model %s: index %s does not lead with %s\n", model, keys[i], tenant
      }
      model = ""
      next
    }
    model != "" {
      if ($1 == tenant) scoped = 1
      if ($0 ~ /@@(index|unique)\(\[/) {
        columns = $0
        sub(/.*(@@index|@@unique)/, "", columns)
        sub(/\).*/, ")", columns)
        kind = ($0 ~ /@@unique/) ? "(unique)" : ""
        keys[++key_count] = kind columns
      }
    }
  ' "$file"
}

scan_schema() {
  # --- money types ----------------------------------------------------------
  report "Float/Decimal in the schema — money is Int minor units (Decimal only by documented decision)" \
    '\b(Float|Decimal)\b'
  report "A stored balance column — with a ledger, balance is SUM(delta), never a column" \
    '^[[:space:]]*balance[A-Za-z]*[[:space:]]+(Int|Float|Decimal)'

  local money_without_suffix
  money_without_suffix=$(awk '
    /^[[:space:]]*(amount|price|total|unitPrice|paid|fee|cost)[A-Za-z]*[[:space:]]+(Int|Float|Decimal)/ {
      if ($1 !~ /(Minor|Cents)$/) printf "%d: %s\n", NR, $0
    }
  ' "$file")
  [ -n "$money_without_suffix" ] && flag "A money-ish field without a minor-unit suffix (Minor/Cents) — the suffix is how units are legible at every call site" "$money_without_suffix"

  # --- tenant scoping -------------------------------------------------------
  if [ -n "$tenant" ]; then
    local gaps
    gaps=$(tenant_scoping_gaps)
    [ -n "$gaps" ] && flag "Tenant scoping — verify each against the project's documented exemptions" "$gaps"
  fi

  # --- relations ------------------------------------------------------------
  local relations_without_on_delete
  relations_without_on_delete=$(grep -nE '@relation\(' "$file" \
    | grep -v 'onDelete:' \
    | grep -vE '\[\][[:space:]]*@relation' || true)
  [ -n "$relations_without_on_delete" ] && flag "@relation without an explicit onDelete — state the intent, do not inherit the default" "$relations_without_on_delete"

  # --- append-only ----------------------------------------------------------
  if [ "$ledger_tables" != "__none__" ] && grep -qE "@@map\(\"($ledger_tables)\"\)" "$file"; then
    report "@updatedAt in a file holding a ledger model — ledger rows are never updated" '@updatedAt'
  fi
  report "Ledger-looking model (delta field) — confirm it has no @updatedAt and every FK is Restrict" \
    '^[[:space:]]*delta[[:space:]]+Int'

  # --- dates ----------------------------------------------------------------
  local dates_as_timestamps
  dates_as_timestamps=$(grep -nE '^[[:space:]]*[A-Za-z]*[Dd]ate[A-Za-z]*[[:space:]]+DateTime' "$file" \
    | grep -vE '[A-Za-z]+At[[:space:]]+DateTime' \
    | grep -v '@db.Date' || true)
  [ -n "$dates_as_timestamps" ] && flag "A calendar date stored as a full timestamp — use @db.Date so no timezone can shift it" "$dates_as_timestamps"

  # --- id strategy ----------------------------------------------------------
  local id_strategies
  id_strategies=$(grep -oE '@id[[:space:]]+@default\([a-z]+\(' "$file" | sort -u | wc -l | tr -d ' ')
  [ "$id_strategies" -gt 1 ] && flag "More than one id strategy in this file — match the siblings" "$(grep -nE '@id[[:space:]]+@default' "$file")"
}

# --------------------------------------------------------------- migration
# Prints statements that lose data. A constraint dropped and added back is an FK rewrite, not data loss.
destructive_statements() {
  awk '
    /ADD CONSTRAINT "?[A-Za-z_]+"?/ {
      name = $0
      sub(/.*ADD CONSTRAINT "?/, "", name)
      sub(/"?[ (].*/, "", name)
      added_back[name] = 1
    }
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /DROP CONSTRAINT/) {
          name = lines[i]
          sub(/.*DROP CONSTRAINT "?/, "", name)
          sub(/"?[;, ].*/, "", name)
          if (name in added_back) continue
        } else if (lines[i] !~ /DROP (COLUMN|TABLE)|ALTER COLUMN[^;]*TYPE/) {
          continue
        }
        printf "%d: %s\n", i, lines[i]
      }
    }
  ' "$file"
}

# Prints UNIQUE constraints and indexes on tables this migration did not create.
unique_on_existing_tables() {
  awk '
    function bare(name) {
      sub(/[ (].*/, "", name)
      sub(/^.*\./, "", name)
      gsub(/"/, "", name)
      return name
    }
    /CREATE TABLE / {
      table = $0
      sub(/.*CREATE TABLE (IF NOT EXISTS )?/, "", table)
      created[bare(table)] = 1
    }
    /CREATE UNIQUE INDEX|ADD CONSTRAINT.*UNIQUE/ {
      table = $0
      if (!sub(/.* ON /, "", table)) sub(/.*ALTER TABLE (ONLY )?/, "", table)
      if (!(bare(table) in created)) printf "%d: %s\n", NR, $0
    }
  ' "$file"
}

# Prints each later line that uses an enum value this migration adds.
enum_values_used_when_added() {
  awk -v quote="'" '
    /ALTER TYPE .* ADD VALUE/ {
      value = $0
      sub(".*ADD VALUE " quote, "", value)
      sub(quote ".*", "", value)
      added_at[value] = NR
    }
    {
      for (value in added_at)
        if (NR > added_at[value] && $0 ~ (quote value quote))
          printf "%d: %s uses %s%s%s added at line %d\n", NR, $0, quote, value, quote, added_at[value]
    }
  ' "$file"
}

scan_migration() {
  report "Float/numeric column — money is INTEGER minor units" \
    'DOUBLE PRECISION|\bREAL\b|NUMERIC|DECIMAL'
  local not_null
  not_null=$(awk '/ADD COLUMN.*NOT NULL/ && !/DEFAULT/ { printf "%d:%s\n", NR, $0 }' "$file")
  [ -n "$not_null" ] && flag "NOT NULL added without a DEFAULT — fails on a populated table; go nullable, backfill, then SET NOT NULL" "$not_null"

  local destructive
  destructive=$(destructive_statements)
  [ -n "$destructive" ] && flag "Destructive statement — confirm the data loss is intended and documented" "$destructive"

  report "CONCURRENTLY — cannot run inside a Prisma migration transaction" 'CONCURRENTLY'

  local unique_added
  unique_added=$(unique_on_existing_tables)
  [ -n "$unique_added" ] && flag "UNIQUE added to a pre-existing table — verify production data holds no duplicates" "$unique_added"

  if [ "$ledger_tables" != "__none__" ]; then
    local ledger_writes
    ledger_writes=$(grep -nE "(UPDATE|DELETE FROM)[[:space:]]+\"?($ledger_tables)" "$file" || true)
    [ -n "$ledger_writes" ] && flag "UPDATE/DELETE on a ledger table — the ledger is append-only; insert a compensating row instead" "$ledger_writes"
  fi

  local enum_uses
  enum_uses=$(enum_values_used_when_added)
  [ -n "$enum_uses" ] && flag "An enum value is used in the same migration that adds it — Postgres requires the adding transaction to commit first; split into two migrations" "$enum_uses"

  if [ -n "$tenant" ]; then
    local other_leading_column
    other_leading_column=$(grep -nE 'CREATE (UNIQUE )?INDEX' "$file" | grep -vE "\(\"$tenant\"" || true)
    [ -n "$other_leading_column" ] && flag "Index whose leading column is not $tenant — verify the table is genuinely non-tenant" "$other_leading_column"
  fi
}

if [[ $file == *.prisma ]]; then
  scan_schema
else
  scan_migration
fi

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
