#!/usr/bin/env bash
# Live schema inventory for prisma-schema-review: every model with its tenant
# scoping, index leading columns, money fields and FK delete actions.
#
# Usage: scripts/inventory.sh [schema-dir-or-file]
#   Finds schema.prisma or prisma/models/*.prisma under the repo when omitted.
# Env:   TENANT_FIELD  tenant key column (default: tenantId; "" = single-tenant)
# Reporting script: a grep with no match is a normal outcome, not an error.

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

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
tenant="${TENANT_FIELD-tenantId}"

target="${1:-}"
if [ -z "$target" ]; then
  first_schema=$(find "$PWD" "$root" -maxdepth 5 -name '*.prisma' -not -path '*/node_modules/*' -not -path '*/migrations/*' 2>/dev/null | head -1)
  [ -n "$first_schema" ] && target=$(dirname "$first_schema")
fi
if [ -z "$target" ] || [ ! -e "$target" ]; then
  echo "no .prisma files found — pass a dir or file" >&2
  exit 1
fi
if [ -d "$target" ]; then
  files=$(find "$target" -name '*.prisma' -not -path '*/migrations/*' | sort)
else
  files="$target"
fi
echo "schema: $(echo "$files" | sed "s|$root/||" | paste -sd' ' -)"

# One block per model: table name, tenant key, mutability, money fields, delete actions, keys.
describe_models() {
  # shellcheck disable=SC2086
  awk -v tenant="$tenant" -v limit="$limit" '
    /^model [A-Za-z]+ / {
      model = $2
      models[++model_count] = model
      scoped[model] = 0; mutable[model] = 0
      money[model] = ""; keys[model] = ""; table[model] = ""; delete_actions[model] = ""
      in_model = 1
      next
    }
    /^}/ { in_model = 0; next }

    in_model && tenant != "" && $1 == tenant { scoped[model] = 1 }
    in_model && /@updatedAt/                 { mutable[model] = 1 }
    in_model && ($1 ~ /(Minor|Cents)$/ || $1 == "currency" || $1 == "delta") {
      money[model] = money[model] " " $1
    }
    in_model && /@@index\(|@@unique\(/ {
      columns = $0
      sub(/.*\(\[/, "", columns); sub(/\].*/, "", columns); gsub(/ /, "", columns)
      kind = ($0 ~ /@@unique/) ? "U" : "I"
      keys[model] = keys[model] "\n      " kind " [" columns "]"
    }
    in_model && /@relation\(/ && /onDelete:/ {
      action = $0
      sub(/.*onDelete: */, "", action); sub(/[)., ].*/, "", action)
      uses[model "|" action]++
      if (uses[model "|" action] == 1) delete_actions[model] = delete_actions[model] " " action
    }
    in_model && /@@map\(/ {
      name = $0
      sub(/.*@@map\("/, "", name); sub(/".*/, "", name)
      table[model] = name
    }

    END {
      for (i = 1; i <= model_count; i++) {
        if (i > limit) {
          printf "\n  … +%d more models (raise INVENTORY_LIMIT=%d, or pass the changed file)\n", model_count - limit, limit
          break
        }
        model = models[i]
        printf "\n%s  (%s)\n", model, table[model] ? table[model] : "no @@map"

        if (tenant != "")
          printf "  tenant:   %s%s\n", \
            scoped[model] ? tenant : "NONE — must be a documented exemption", \
            mutable[model] ? "   (+@updatedAt: mutable)" : "   (no @updatedAt)"
        else
          printf "  mutable:  %s\n", mutable[model] ? "yes (@updatedAt)" : "no @updatedAt"

        if (money[model] != "") printf "  money:   %s\n", money[model]

        if (delete_actions[model] != "") {
          summary = ""
          action_count = split(delete_actions[model], actions, " ")
          for (j = 1; j <= action_count; j++)
            summary = summary sprintf(" %s×%d", actions[j], uses[model "|" actions[j]])
          printf "  onDelete:%s\n", summary
        }
        if (keys[model] != "") printf "  keys:%s\n", keys[model]
      }
    }
  ' $files
}

describe_models

if [ -n "$tenant" ]; then
  echo
  echo "=== indexes whose leading column is not $tenant (verify each is intentional)"
  # shellcheck disable=SC2086
  grep -hnE '@@(index|unique)\(\[' $files | grep -vE "@@(index|unique)\(\[$tenant" | indent | cap
fi

echo
echo "=== enums"
# shellcheck disable=SC2086
grep -hE '^enum [A-Za-z]+' $files | indent | cap

schema_dir=$(dirname "$(echo "$files" | head -1)")
migrations=$(find "$schema_dir/.." "$root" -maxdepth 4 -type d -name migrations -path '*prisma*' 2>/dev/null | head -1)
if [ -n "$migrations" ]; then
  echo
  echo "=== migrations (newest last) — never edit an applied one"
  ls "$migrations" | grep -v migration_lock | tail -6 | indent
fi
