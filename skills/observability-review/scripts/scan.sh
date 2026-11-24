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
if [ -z "$file" ]; then
  echo "usage: scan.sh <backend file>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

log_call="${LOG_CALL:-(this\.)?(logger|log)\.(fatal|error|warn|info|debug|trace|log|verbose)\(}"
error_call='(this\.)?(logger|log)\.error\('
secret_names="password|passwd|secret|token|apiKey|api_key|authorization|cookie|set-cookie|ssn|cardNumber|card_number|cvv|pan|privateKey|private_key${SECRETS:+|$SECRETS}"
tenant_names='tenantId|tenant_id|organizationId|orgId|workspaceId'

found_any=0

# flag LABEL [LINES] — prints a finding, with the lines that caused it when there are any
flag() {
  printf '## %s\n' "$1"
  [ -n "${2:-}" ] && printf '%s\n' "$2"
  printf '\n'
  found_any=1
}

# report LABEL REGEX — flags every line of the file that matches
report() {
  local matches
  matches=$(grep -nE "$2" "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

has() {
  grep -qE "$1" "$file"
}

# --- the logger ---------------------------------------------------------------
report "console.* — bypasses level, redaction and request id" \
  'console\.(log|error|warn|info|debug|trace)\('

has_risky_path='catch|await .*\.(post|get|put|patch|delete|send|publish|add|emit|request)\('
declares_logger='new Logger\(|private (readonly )?(logger|log)\b|@InjectPinoLogger|PinoLogger'
if has "$has_risky_path" && ! has "$log_call" && ! has "$declares_logger"; then
  flag "No logger in a file with catch blocks or external calls"
fi

report "Logger without class context — new Logger() with no name" \
  'new Logger\(\)'
report "String interpolation in a log call — fields cannot be filtered" \
  "${log_call}[^)]*\\\$\\{"
report "JSON.stringify in a log call — whole object, whatever is in it" \
  "${log_call}[^)]*JSON\\.stringify"

# --- secrets ------------------------------------------------------------------
report "Possible secret in a log call" \
  "($log_call|console\\.[a-z]+\\()[^)]*\\b($secret_names)\\b"
report "Request headers or full body in a log call" \
  "${log_call}[^)]*(req\\.headers|request\\.headers|req\\.body|request\\.body|headers\\[)"

# --- error paths --------------------------------------------------------------
# Follows the braces of each catch block and prints the ones that neither log nor pass the error on.
silent_catches() {
  LOG_CALL_REGEX=$log_call awk '
    BEGIN { log_call = ENVIRON["LOG_CALL_REGEX"] }
    /catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{/ {
      start = NR
      depth = 0
      body = ""
      in_catch = 1
    }
    in_catch {
      body = body "\n" $0
      depth += gsub(/\{/, "{") - gsub(/\}/, "}")
      if (depth <= 0 && NR > start) {
        passes_on = (body ~ /throw|rethrow|next\(|reject\(|captureException|Sentry/)
        if (body !~ log_call && !passes_on) printf "%d: catch block with no log and no throw\n", start
        in_catch = 0
      }
    }
  ' "$file"
}
silent=$(silent_catches)
[ -n "$silent" ] && flag "Silent catch — swallowed error" "$silent"

report "logger.error with a string only — no error object, no stack" \
  "${error_call}[[:space:]]*(\`[^\`]*\`|'[^']*'|\"[^\"]*\")[[:space:]]*\\)"
report "Error-level log next to a rethrow — check the boundary does not log it again" \
  "$error_call.*;[[:space:]]*throw|throw .*(logger|log)\\.error"

# --- external calls -----------------------------------------------------------
report "Outbound HTTP / SDK call — needs an outcome log or span with the remote id" \
  '(^|[^.A-Za-z0-9_$])(fetch|axios|got)\(|\b(axios|got|httpService|this\.http)\.(get|post|put|patch|delete|request)\(|\.(send|publish|sendMessage)\(|[qQ]ueue\.add\('
report "Timer or cron entry — start/end counts?" \
  '@Cron\(|@Interval\(|@Process\(|@Processor\(|@OnQueueActive|@EventPattern\(|@MessagePattern\('

# --- correlation --------------------------------------------------------------
correlation_names='reqId|requestId|correlationId|traceId|trace_id|request_id|ClsService|AsyncLocalStorage|cls\.get'
if has "$log_call" && ! has "$correlation_names"; then
  flag "Log calls present, no correlation id reference in the file — verify the logger adds it automatically"
fi
if has "$log_call" && has "$tenant_names" && ! has "${log_call}[^)]*($tenant_names)"; then
  flag "Tenant-scoped file whose log calls never carry the tenant id"
fi

# --- volume -------------------------------------------------------------------
# Prints info-level log calls within 12 lines of a loop opening.
info_logs_in_loops() {
  LOG_CALL_REGEX=$log_call awk '
    BEGIN { log_call = ENVIRON["LOG_CALL_REGEX"] }
    /^[[:space:]]*(for|while)[[:space:]]*\(|\.(forEach|map)\(/ { loop_line = NR }
    $0 ~ log_call && $0 ~ /\.(info|log)\(/ && loop_line && NR - loop_line <= 12 {
      printf "%d: info-level log inside a loop (opened line %d)\n", NR, loop_line
    }
  ' "$file"
}
in_loops=$(info_logs_in_loops)
[ -n "$in_loops" ] && flag "Per-item info log in a loop — debug, or one summary line" "$in_loops"

# --- money / delete / auth without a log --------------------------------------
sensitive_path='\.(delete|deleteMany|softDelete|remove)\(|refund|charge|payout|transfer|capture\(|canActivate|authorize|permission'
if has "$sensitive_path" && ! has "$log_call"; then
  flag "Deletion, money or auth path with no log line in the file"
fi

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
