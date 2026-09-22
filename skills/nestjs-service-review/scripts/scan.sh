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
[ -z "$file" ] && { echo "usage: scan.sh <file.ts>" >&2; exit 1; }
[ -f "$file" ] || { echo "not found: $file" >&2; exit 1; }

TENANT="${TENANT_FIELD-tenantId}"
UNSCOPED="${EXEMPT_MODELS:-__none__}"

hits=0
report() {
  local out
  out=$(grep -nE "$2" "$file")
  if [ -n "$out" ]; then printf '## %s\n%s\n\n' "$1" "$out"; hits=1; fi
}
emit() { printf '## %s\n%s\n\n' "$1" "$2"; hits=1; }

# --- inside a $transaction callback -----------------------------------------
tx=$(awk '
  intx {
    if ($0 ~ /this\.prisma\./)
      printf "%d: %s  <- outer client inside tx\n", NR, $0
    if ($0 ~ /fetch\(|axios\.|https?\.request|httpService|\.publish\(|\.emit\(/)
      printf "%d: %s  <- network/queue call inside tx\n", NR, $0
    d += gsub(/\{/,"{") - gsub(/\}/,"}")
    if (d <= 0) intx = 0
    next
  }
  /\$transaction\(/ { intx = 1; d = gsub(/\{/,"{") - gsub(/\}/,"}") }
' "$file")
[ -n "$tx" ] && emit "Inside a \$transaction callback — use tx, and no network calls" "$tx"

# --- tenant scoping ----------------------------------------------------------
if [ -n "$TENANT" ]; then
  noscope=$(awk -v unscoped="$UNSCOPED" -v tenant="$TENANT" '
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (L[i] !~ /(this\.prisma|prisma|tx)\.[a-zA-Z]+\.(findFirst|findMany|findUnique|updateMany|deleteMany|update|delete|count|aggregate|groupBy)\(/) continue
        if (L[i] ~ ("(this\\.prisma|prisma|tx)\\.(" unscoped ")\\.")) continue
        found = 0
        for (j = i; j <= i + 15 && j <= NR; j++) if (L[j] ~ tenant) found = 1
        for (j = i - 20; j < i; j++) if (j > 0 && L[j] ~ tenant) found = 1
        if (!found) printf "%d: %s\n", i, L[i]
      }
    }
  ' "$file")
  [ -n "$noscope" ] && emit "Prisma call with no $TENANT within 15 lines — verify the model is genuinely non-tenant" "$noscope"

  fu=$(awk -v unscoped="$UNSCOPED" -v tenant="$TENANT" '
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (L[i] !~ /(this\.prisma|prisma|tx)\.[a-zA-Z]+\.findUnique\(/) continue
        if (L[i] ~ ("(this\\.prisma|prisma|tx)\\.(" unscoped ")\\.")) continue
        scoped = 0
        for (j = i; j <= i + 5 && j <= NR; j++) if (L[j] ~ tenant) scoped = 1
        if (!scoped) printf "%d: %s\n", i, L[i]
      }
    }
  ' "$file")
  [ -n "$fu" ] && emit "findUnique with no $TENANT — only a compound unique including the tenant key can be tenant-scoped; otherwise use findFirst" "$fu"
fi

unbounded=$(awk '
  { L[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      if (L[i] !~ /(this\.prisma|prisma|tx)\.[a-zA-Z]+\.findMany\(/) continue
      found = 0
      for (j = i; j <= i + 15 && j <= NR; j++) if (L[j] ~ /take:/) found = 1
      if (!found) printf "%d: %s\n", i, L[i]
    }
  }
' "$file")
[ -n "$unbounded" ] && emit "findMany with no take within 15 lines — unbounded query" "$unbounded"

# --- async correctness (no type-aware lint) ----------------------------------
unawaited=$(grep -nE '^[[:space:]]*(this\.prisma|tx)\.[a-zA-Z]+\.' "$file" \
  | grep -vE 'await|return|=' || true)
[ -n "$unawaited" ] && emit "Prisma call that is neither awaited, returned, nor assigned" "$unawaited"
report "async ngOnInit / async lifecycle-style hook — a rejected promise there is unhandled" \
  'async (onModuleInit|onApplicationBootstrap)\('

# --- money / ledger ----------------------------------------------------------
report "Float arithmetic near money — amounts are integer minor units" \
  'parseFloat|toFixed|Math\.round\(.*(Minor|Cents|amount)|/ *100|\* *100'
money=$(awk '
  {
    line = $0
    while (match(line, /(amount|price|total|balance|fee|cost)[A-Za-z]*[[:space:]]*:[[:space:]]*number/)) {
      tok = substr(line, RSTART, RLENGTH)
      if (tok !~ /(Minor|Cents)/) printf "%d: %s\n", NR, $0
      line = substr(line, RSTART + RLENGTH)
    }
  }
' "$file")
[ -n "$money" ] && emit "A money-ish field typed as plain number without a minor-unit suffix" "$money"

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
  '[A-Za-z0-9_\)\]]![.\[]'
report "\$use — Prisma middleware is deprecated on 5+; use \$extends" \
  '\$use\('

# --- controllers -------------------------------------------------------------
if [[ "$file" == *.controller.ts ]]; then
  report "Prisma access in a controller — belongs in the service" 'prisma\.'
  report "Route id param without a Parse*Pipe" "@Param\('[a-zA-Z]*[iI]d'\)[[:space:]]*[a-zA-Z]+:"
  report "req.* read directly — use the project's param decorator" '@Req\(\)|req\.(user|tenant|org)'
fi

# --- ForbiddenException in a service ----------------------------------------
if [[ "$file" == *.service.ts ]]; then
  fb=$(grep -nE 'throw new ForbiddenException' "$file" || true)
  [ -n "$fb" ] && emit "ForbiddenException in a service — confirm each is an authorization failure, not a cross-tenant miss (which must be 404)" "$fb"
fi

# --- spec coverage -----------------------------------------------------------
b=$(basename "$file" .ts); d=$(dirname "$file")
if [[ "$file" == *.service.ts || "$file" == *.controller.ts ]]; then
  if [ ! -f "$d/$b.spec.ts" ] && [ ! -f "$d/__tests__/$b.spec.ts" ]; then
    emit "No spec for this unit" "  expected $d/$b.spec.ts or $d/__tests__/$b.spec.ts"
  fi
fi

[ "$hits" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
