#!/usr/bin/env bash
# Mechanical pre-scan for observability-review. Catches the deterministic
# smells so the review spends judgement on whether the path is debuggable.
# Heuristic — flags, not a verdict.
#
# Nothing in lint knows whether a catch logs, whether a log carries the
# request id, or whether a secret is in a log field. This does, roughly.
#
# Usage: scan.sh <path/to/thing.service.ts>
# Env:   LOG_CALL   regex for the project's log call (default: matches
#                   logger.<level>( / log.<level>( / this.logger.<level>()
#        SECRETS    extra |-separated field names that must never be logged
set -uo pipefail

file="${1:-}"
[ -z "$file" ] && { echo "usage: scan.sh <backend file>" >&2; exit 1; }
[ -f "$file" ] || { echo "not found: $file" >&2; exit 1; }

LOG="${LOG_CALL:-(this\.)?(logger|log)\.(fatal|error|warn|info|debug|trace|log|verbose)\(}"
SECRET="password|passwd|secret|token|apiKey|api_key|authorization|cookie|set-cookie|ssn|cardNumber|card_number|cvv|pan|privateKey|private_key${SECRETS:+|$SECRETS}"

hits=0
report() {
  local out
  out=$(grep -nE "$2" "$file")
  if [ -n "$out" ]; then printf '## %s\n%s\n\n' "$1" "$out"; hits=1; fi
}

# --- the logger ---------------------------------------------------------------
report "console.* — bypasses level, redaction and request id" \
  'console\.(log|error|warn|info|debug|trace)\('
if grep -qE 'catch|await .*\.(post|get|put|patch|delete|send|publish|add|emit|request)\(' "$file" \
   && ! grep -qE "$LOG" "$file" && ! grep -qE 'new Logger\(|private (readonly )?(logger|log)\b|@InjectPinoLogger|PinoLogger' "$file"; then
  printf '## No logger in a file with catch blocks or external calls\n\n'; hits=1
fi
report "Logger without class context — new Logger() with no name" \
  'new Logger\(\)'
report "String interpolation in a log call — fields cannot be filtered" \
  "$LOG[^)]*\\\$\\{"
report "JSON.stringify in a log call — whole object, whatever is in it" \
  "$LOG[^)]*JSON\\.stringify"

# --- secrets ------------------------------------------------------------------
report "Possible secret in a log call" \
  "($LOG|console\\.[a-z]+\\()[^)]*\\b($SECRET)\\b"
report "Request headers or full body in a log call" \
  "$LOG[^)]*(req\\.headers|request\\.headers|req\\.body|request\\.body|headers\\[)"

# --- error paths --------------------------------------------------------------
# catch blocks: empty, or with neither a log nor a throw in the next 6 lines.
awk -v log="$LOG" '
  /catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{/ { start=NR; depth=0; body=""; inblk=1 }
  inblk { body = body "\n" $0
          n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth += n - m
          if (depth <= 0 && NR > start) {
            if (body !~ log && body !~ /throw|rethrow|next\(|reject\(|captureException|Sentry/) printf "%d: catch block with no log and no throw\n", start
            inblk=0 } }
' "$file" | { out=$(cat); [ -n "$out" ] && { printf '## Silent catch — swallowed error\n%s\n\n' "$out"; hits=1; }; }
report "logger.error with a string only — no error object, no stack" \
  "(this\\.)?(logger|log)\\.error\\([[:space:]]*(\`[^\`]*\`|'[^']*'|\"[^\"]*\")[[:space:]]*\\)"
report "Error-level log next to a rethrow — check the boundary does not log it again" \
  "(this\\.)?(logger|log)\\.error\\(.*;[[:space:]]*throw|throw .*(logger|log)\\.error"

# --- external calls -----------------------------------------------------------
report "Outbound HTTP / SDK call — needs an outcome log or span with the remote id" \
  '\b(fetch|axios|got|httpService|this\.http)\.(get|post|put|patch|delete|request)?\(|\.(send|publish|sendMessage|add)\('
report "Timer or cron entry — start/end counts?" \
  '@Cron\(|@Interval\(|@Process\(|@Processor\(|@OnQueueActive|@EventPattern\(|@MessagePattern\('

# --- correlation --------------------------------------------------------------
if grep -qE "$LOG" "$file" && ! grep -qE 'reqId|requestId|correlationId|traceId|trace_id|request_id|ClsService|AsyncLocalStorage|cls\.get' "$file"; then
  printf '## Log calls present, no correlation id reference in the file — verify the logger adds it automatically\n\n'; hits=1
fi
if grep -qE "$LOG" "$file" && grep -qE 'tenantId|tenant_id|organizationId|orgId|workspaceId' "$file"; then
  if ! grep -qE "$LOG[^)]*(tenantId|tenant_id|organizationId|orgId|workspaceId)" "$file"; then
    printf '## Tenant-scoped file whose log calls never carry the tenant id\n\n'; hits=1
  fi
fi

# --- volume -------------------------------------------------------------------
awk -v log="$LOG" '
  /^[[:space:]]*(for|while)[[:space:]]*\(|\.(forEach|map)\(/ { loop=NR }
  $0 ~ log && $0 ~ /\.(info|log)\(/ && loop && NR-loop <= 12 { printf "%d: info-level log inside a loop (opened line %d)\n", NR, loop }
' "$file" | { out=$(cat); [ -n "$out" ] && { printf '## Per-item info log in a loop — debug, or one summary line\n%s\n\n' "$out"; hits=1; }; }

# --- money / delete / auth without a log --------------------------------------
if grep -qE '\.(delete|deleteMany|softDelete|remove)\(|refund|charge|payout|transfer|capture\(|canActivate|authorize|permission' "$file" && ! grep -qE "$LOG" "$file"; then
  printf '## Deletion, money or auth path with no log line in the file\n\n'; hits=1
fi

[ "$hits" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
