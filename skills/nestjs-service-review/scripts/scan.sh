#!/usr/bin/env bash
# Mechanical pre-scan for nestjs-service-review. Catches the deterministic
# smells so the review spends judgement on the rest. Heuristic — flags, not a
# verdict.
#
# Everything here is invisible to a non-type-aware ESLint setup: no
# no-floating-promises, no no-console, nothing that understands tenant scoping.
#
# Usage: scan.sh <path/to/thing.service.ts>
# Env:   TENANT_FIELD   tenant key (default: tenantId; "" = skip scoping checks)
#        EXEMPT_MODELS  Prisma model accessors deliberately unscoped, |-separated,
#                       in client-property case (user|tenant|apiToken)
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <file.ts>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

tenant="${TENANT_FIELD-tenantId}"
exempt_models="${EXEMPT_MODELS:-__none__}"

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

# --- inside a $transaction callback -----------------------------------------
# Follows the braces from each $transaction( and prints what must not be inside.
misuse_inside_transactions() {
  awk '
    in_transaction {
      if ($0 ~ /this\.prisma\./)
        printf "%d: %s  <- outer client inside tx\n", NR, $0
      if ($0 ~ /fetch\(|axios\.|https?\.request|httpService|\.publish\(|\.emit\(/)
        printf "%d: %s  <- network/queue call inside tx\n", NR, $0
      depth += gsub(/\{/, "{") - gsub(/\}/, "}")
      if (depth <= 0) in_transaction = 0
      next
    }
    /\$transaction\(/ {
      in_transaction = 1
      depth = gsub(/\{/, "{") - gsub(/\}/, "}")
    }
  ' "$file"
}
in_transaction=$(misuse_inside_transactions)
[ -n "$in_transaction" ] && flag "Inside a \$transaction callback — use tx, and no network calls" "$in_transaction"

# --- tenant scoping ----------------------------------------------------------
# prisma_calls_without METHODS WORD AFTER BEFORE [EXEMPT]
# Prints each Prisma call to one of METHODS (an ERE alternation) with no line matching WORD
# among the AFTER lines from the call on, or the BEFORE lines ahead of it.
# Calls on a model in EXEMPT (an ERE alternation) are left out.
prisma_calls_without() {
  awk -v methods="$1" -v word="$2" -v after="$3" -v before="$4" -v exempt="${5:-__none__}" '
    { lines[NR] = $0 }
    END {
      client = "(this\\.prisma|prisma|tx)\\."
      for (i = 1; i <= NR; i++) {
        if (lines[i] !~ (client "[a-zA-Z]+\\.(" methods ")\\(")) continue
        if (lines[i] ~ (client "(" exempt ")\\.")) continue
        found = 0
        for (j = i - before; j <= i + after && j <= NR; j++)
          if (j > 0 && lines[j] ~ word) found = 1
        if (!found) printf "%d: %s\n", i, lines[i]
      }
    }
  ' "$file"
}

if [ -n "$tenant" ]; then
  reads_and_writes='findFirst|findMany|findUnique|updateMany|deleteMany|update|delete|count|aggregate|groupBy'
  unscoped=$(prisma_calls_without "$reads_and_writes" "$tenant" 15 20 "$exempt_models")
  [ -n "$unscoped" ] && flag "Prisma call with no $tenant within 15 lines — verify the model is genuinely non-tenant" "$unscoped"

  unscoped_unique=$(prisma_calls_without 'findUnique' "$tenant" 5 0 "$exempt_models")
  [ -n "$unscoped_unique" ] && flag "findUnique with no $tenant — add it to the where (Prisma 5+ takes it next to the unique field); before 5 use a compound unique or findFirst" "$unscoped_unique"
fi

unbounded=$(prisma_calls_without 'findMany' 'take:' 15 0)
[ -n "$unbounded" ] && flag "findMany with no take within 15 lines — unbounded query" "$unbounded"

# --- async correctness (no type-aware lint) ----------------------------------
floating=$(grep -nE '^[[:space:]]*(this\.prisma|tx)\.[a-zA-Z]+\.' "$file" | grep -vE 'await|return|=' || true)
[ -n "$floating" ] && flag "Prisma call that is neither awaited, returned, nor assigned" "$floating"
report "async onModuleInit / onApplicationBootstrap — a rejected promise there is unhandled" \
  'async (onModuleInit|onApplicationBootstrap)\('

# --- money / ledger ----------------------------------------------------------
report "Float arithmetic near money — amounts are integer minor units" \
  'parseFloat|toFixed|Math\.round\(.*(Minor|Cents|amount)|/ *100|\* *100'

# Prints each line typing a money-named field as number when the name lacks Minor or Cents.
money_typed_as_plain_number() {
  awk '
    {
      rest = $0
      while (match(rest, /(amount|price|total|balance|fee|cost)[A-Za-z]*[[:space:]]*:[[:space:]]*number/)) {
        field = substr(rest, RSTART, RLENGTH)
        if (field !~ /(Minor|Cents)/) printf "%d: %s\n", NR, $0
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' "$file"
}
plain_money=$(money_typed_as_plain_number)
[ -n "$plain_money" ] && flag "A money-ish field typed as plain number without a minor-unit suffix" "$plain_money"

# --- errors ------------------------------------------------------------------
report "Exception thrown with a literal string — user-facing messages go through the project's i18n / messages constant" \
  'throw new [A-Za-z]*Exception\([[:space:]]*['"'"'\"`]'
report "Prisma error code literal — use a named constant" \
  "'P2[0-9]{3}'"

# --- hygiene -----------------------------------------------------------------
report "console.* — no no-console rule here, nothing else catches it" \
  'console\.(log|warn|debug|info|error)'
report "process.env read — configuration should be injected" \
  'process\.env'
report "any / as any — type it or use unknown + guard" \
  ':[[:space:]]*any\b|as any\b'
report "Non-null assertion — handle the null instead" \
  '[]A-Za-z0-9_)]!(\.|\[)'
report "\$use — Prisma middleware is deprecated on 5+; use \$extends" \
  '\$use\('

# --- controllers -------------------------------------------------------------
if [[ $file == *.controller.ts ]]; then
  report "Prisma access in a controller — belongs in the service" 'prisma\.'
  report "Route id param without a Parse*Pipe" "@Param\('[a-zA-Z]*[iI]d'\)[[:space:]]*[a-zA-Z]+:"
  report "req.* read directly — use the project's param decorator" '@Req\(\)|req\.(user|tenant|org)'
fi

# --- ForbiddenException in a service ----------------------------------------
if [[ $file == *.service.ts ]]; then
  forbidden=$(grep -nE 'throw new ForbiddenException' "$file" || true)
  [ -n "$forbidden" ] && flag "ForbiddenException in a service — confirm each is an authorization failure, not a cross-tenant miss (which must be 404)" "$forbidden"
fi

# --- spec coverage -----------------------------------------------------------
unit=$(basename "$file" .ts)
dir=$(dirname "$file")
if [[ $file == *.service.ts || $file == *.controller.ts ]]; then
  if [ ! -f "$dir/$unit.spec.ts" ] && [ ! -f "$dir/__tests__/$unit.spec.ts" ]; then
    flag "No spec for this unit" "  expected $dir/$unit.spec.ts or $dir/__tests__/$unit.spec.ts"
  fi
fi

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
