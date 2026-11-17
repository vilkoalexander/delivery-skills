#!/usr/bin/env bash
# Mechanical pre-scan for spring-service-review. Catches the deterministic
# smells so the review spends judgement on the rest. Heuristic — flags, not a
# verdict.
#
# javac and most Checkstyle setups see none of this: a proxy that never runs,
# a handler nobody authorized, a remote call that holds a database connection.
#
# Usage: scan.sh <path/to/Thing.java>
# Env:   AUTHZ        ERE for the annotations that authorize a handler
#                     (default: @PreAuthorize|@PostAuthorize|@Secured|@RolesAllowed|@PermitAll;
#                     "" = skip the check, for a project that authorizes by URL)
#        REMOTE_CALL  ERE for calls that leave the process (HTTP, object store, bot, mail)
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <File.java>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

authz="${AUTHZ-@PreAuthorize|@PostAuthorize|@Secured|@RolesAllowed|@PermitAll}"
remote_call="${REMOTE_CALL:-[hH]ttpClient|newCall\(|[rR]estTemplate|[rR]estClient|[wW]ebClient|[fF]eignClient|[mM]inioClient|[sS]3Client|\.putObject\(|\.getObject\(|[tT]elegram|[mM]ailSender|\.exchange\(|\.retrieve\(}"
proxied='@Transactional|@Async|@Cacheable|@CacheEvict|@CachePut|@Retryable|@PreAuthorize|@PostAuthorize'

found_any=0

# flag LABEL LINES — prints a finding with the lines that caused it
flag() {
  printf '## %s\n%s\n\n' "$1" "$2"
  found_any=1
}

# report LABEL REGEX — flags every line of the file that matches
report() {
  local matches
  matches=$(grep -nE -- "$2" "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

# report_code LABEL REGEX — like report, but text inside string literals does not count
report_code() {
  local matches
  matches=$(REGEX=$2 awk '
    {
      code = $0
      gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
      if (code ~ ENVIRON["REGEX"]) printf "%d:%s\n", NR, $0
    }
  ' "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

has() {
  grep -qE -- "$1" "$file"
}

# Prints one row per annotated class, field or method:
#   LINE <tab> ANNOTATIONS <tab> DECLARATION
# A declaration that wraps is joined up to its "{" or ";".
annotated_declarations() {
  awk '
    function parens(text) { return gsub(/\(/, "(", text) - gsub(/\)/, ")", text) }
    function trimmed(text) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", text); return text }
    {
      line = trimmed($0)
      if (declaration != "") {
        declaration = declaration " " line
      } else if (annotations != "" && depth > 0) {
        annotations = annotations " " line
        depth += parens(line)
        next
      } else if (line ~ /^@[A-Za-z]/ && line !~ /^@interface/) {
        annotations = annotations " " line
        depth = parens(line)
        next
      } else if (annotations == "" || line == "" || line ~ /^(\/\/|\/\*|\*)/) {
        next
      } else {
        declaration = line
        declared_at = NR
      }
      if (declaration ~ /[{;]/) {
        printf "%d\t%s\t%s\n", declared_at, trimmed(annotations), declaration
        annotations = ""
        declaration = ""
      }
    }
  ' "$file"
}

# bodies_of ANNOTATION — prints "LINE: text" for every line inside a method
# whose annotations match ANNOTATION (an ERE).
bodies_of() {
  ANNOTATION=$1 awk '
    function braces(text) { return gsub(/\{/, "{", text) - gsub(/\}/, "}", text) }
    in_body {
      depth += braces($0)
      if (depth <= 0) { in_body = 0; next }
      printf "%d: %s\n", NR, $0
      next
    }
    /^[[:space:]]*@[A-Za-z]/ {
      if ($0 ~ ENVIRON["ANNOTATION"]) wanted = 1
      annotated = 1
      next
    }
    annotated && /\{[[:space:]]*$/ {
      if (wanted && $0 !~ /(class|interface|enum|record) /) { in_body = 1; depth = braces($0) }
      annotated = 0
      wanted = 0
      next
    }
    annotated && /;[[:space:]]*$/ { annotated = 0; wanted = 0 }
  ' "$file"
}

# rows_where ANNOTATIONS_MATCH [ANNOTATIONS_LACK] — rows of $declarations, as "LINE: declaration"
rows_where() {
  printf '%s\n' "$declarations" | MATCH=$1 LACK=${2:-} awk -F'\t' '
    $2 ~ ENVIRON["MATCH"] && (ENVIRON["LACK"] == "" || $2 !~ ENVIRON["LACK"]) { printf "%s: %s\n", $1, $3 }
  '
}

is_method() {
  grep -E '\(' | grep -vE '^[0-9]+: .*\b(class|interface|enum|record) '
}

declarations=$(annotated_declarations)

is_test=0
case "$file" in
  */src/test/*|*/testFixtures/*|*Test.java|*Tests.java|*IT.java) is_test=1 ;;
esac
is_controller=0
has '^@(Rest)?Controller' && is_controller=1
is_bean=0
has '^@(Service|Component|RestController|Controller|Repository|Configuration)' && is_bean=1
is_interface=0
has '^public interface ' && is_interface=1

# --- wrong platform ----------------------------------------------------------
report "javax.* import — Spring Boot 3 is jakarta.*; this class does not load" \
  '^import javax\.(persistence|validation|servlet|transaction|ws|mail)\.|^import javax\.annotation\.(PostConstruct|PreDestroy|Resource|security)'
report "Removed Spring Security API — use a SecurityFilterChain bean and requestMatchers" \
  'WebSecurityConfigurerAdapter|\.antMatchers\(|\.mvcMatchers\(|\.authorizeRequests\('

if [ "$is_test" = 0 ]; then
  # --- proxies that never run ------------------------------------------------
  if [ "$is_interface" = 0 ]; then
    non_public=$(rows_where '@Transactional|@Async|@Cacheable|@CacheEvict' | is_method | grep -vE '^[0-9]+: public ' || true)
    [ -n "$non_public" ] && flag "Proxied annotation on a method that is not public — the proxy skips it, the annotation does nothing" "$non_public"

    final_or_static=$(rows_where "$proxied" | is_method | grep -E '^[0-9]+: (public )?(static|final) ' || true)
    [ -n "$final_or_static" ] && flag "Proxied annotation on a static or final method — it cannot be intercepted" "$final_or_static"
  fi

  # Calls to a proxied method of this class from inside the class go around the proxy.
  self_invocations() {
    local row line name
    while IFS=$'\t' read -r line _ declaration; do
      name=$(printf '%s' "$declaration" | sed -nE 's/^[^(]*[[:space:]]([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(.*/\1/p')
      [ -n "$name" ] || continue
      CALL="(^|[^.A-Za-z0-9_])$name\(|this\.$name\(" awk '
        {
          code = $0
          gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
          if (code ~ ENVIRON["CALL"]) printf "%d:%s\n", NR, $0
        }
      ' "$file" \
        | grep -vE "^$line:" \
        | grep -vE "^[0-9]+:[[:space:]]*(public|protected|private)[^=]*[[:space:]]$name\(" \
        | sed "s/\$/  <- $name is proxied/"
    done < <(printf '%s\n' "$declarations" | PROXIED=$proxied awk -F'\t' '$2 ~ ENVIRON["PROXIED"] && $3 ~ /\(/ && $3 !~ /(class|interface) /')
  }
  self_calls=$(self_invocations | sort -t: -k1,1n -u)
  [ -n "$self_calls" ] && flag "Self-invocation of a proxied method — the call skips the proxy; verify the caller already carries what the annotation adds" "$self_calls"

  # --- transactions ----------------------------------------------------------
  checked_without_rollback=$(rows_where '@Transactional' 'rollbackFor|readOnly[[:space:]]*=[[:space:]]*true' | grep -E '\) *throws ' || true)
  [ -n "$checked_without_rollback" ] && flag "@Transactional method throws a checked exception with no rollbackFor — a checked exception commits" "$checked_without_rollback"

  remote_in_transaction=$(bodies_of '@Transactional' | grep -E -- "$remote_call" || true)
  [ -n "$remote_in_transaction" ] && flag "Remote call inside a @Transactional method — the database connection is held for the round trip" "$remote_in_transaction"

  report "jakarta/javax @Transactional — use org.springframework.transaction.annotation.Transactional (readOnly, rollbackFor)" \
    '^import (jakarta|javax)\.transaction\.Transactional'

  events_in_transaction=$(bodies_of '@Transactional' | grep -E 'publishEvent\(' || true)
  [ -n "$events_in_transaction" ] && flag "Event published inside a transaction — a plain @EventListener runs before commit; side effects belong in @TransactionalEventListener(AFTER_COMMIT)" "$events_in_transaction"

  # --- beans -----------------------------------------------------------------
  field_injection=$(rows_where '@Autowired|@Inject|@Resource' | grep -vE '\(' || true)
  [ -n "$field_injection" ] && flag "Field injection — use constructor injection (final field, @RequiredArgsConstructor)" "$field_injection"

  if [ "$is_bean" = 1 ] && ! has '@ConfigurationProperties'; then
    mutable=$(grep -nE '^    (private|protected|public) [^(=]*[a-z][A-Za-z0-9]*( = [^;]*)?;' "$file" \
      | grep -vE '^[0-9]+: +(private|protected|public) (static |final )' || true)
    [ -n "$mutable" ] && flag "Mutable field in a singleton bean — shared by every request thread" "$mutable"
  fi

  # --- controllers -----------------------------------------------------------
  if [ "$is_controller" = 1 ]; then
    mapping='@(Get|Post|Put|Patch|Delete|Request)Mapping'
    if [ -n "$authz" ]; then
      class_level=$(rows_where "$authz" | grep -E '\bclass ' || true)
      if [ -z "$class_level" ]; then
        unauthorized=$(rows_where "$mapping" "$authz" | is_method || true)
        [ -n "$unauthorized" ] && flag "Handler with no authorization annotation — confirm the URL rules cover it, or that it is public on purpose" "$unauthorized"
      fi
    fi

    unvalidated=$(rows_where "$mapping" | tr ',' '\n' | awk '
      /^[0-9]+: / { line = $1; sub(/^[0-9]+: /, "") }
      /@RequestBody/ && !/@Valid/ { print line " " $0 }
    ')
    [ -n "$unvalidated" ] && flag "@RequestBody without @Valid — the constraints on the request class never run" "$unvalidated"

    entities=$(awk '
      /^import / { next }
      {
        rest = $0
        gsub(/(Response|Http|Request)Entity/, "", rest)
        if (rest ~ /[A-Za-z0-9]Entity([^A-Za-z0-9]|$)/) printf "%d:%s\n", NR, $0
      }
    ' "$file")
    [ -n "$entities" ] && flag "Entity type in a controller — a request or response must be a DTO (over-posting, lazy fields, schema leak)" "$entities"
    report "Repository in a controller — data access belongs in the service" \
      '\b[A-Z][A-Za-z0-9]*Repository\b'
    report "@Transactional in a controller — the transaction belongs to the service method" \
      '^[[:space:]]*@Transactional'
  fi

  # --- data access from a service -------------------------------------------
  report "findAll() with no page or specification — unbounded read" \
    '\.findAll\(\)'
  report "Optional.get() / orElseThrow() with no exception — a miss is a 500, not the project's not-found error" \
    '\.(find[A-Za-z]*|get[A-Za-z]*)\([^)]*\)\.get\(\)|\.orElseThrow\(\)'
  report "Request mapped straight onto an entity — every matching property is writable by the client" \
    '\.map\([a-zA-Z]*([rR]equest|[dD]to|[bB]ody)[A-Za-z]*, *[A-Z][A-Za-z0-9]*Entity\.class\)'
fi

# --- exceptions and logging --------------------------------------------------
report "catch of Exception / Throwable — catch what the call can throw" \
  'catch \((final )?(Exception|Throwable|RuntimeException) '
swallowed=$(awk '
  /catch \(/ { catch_line = NR; catch_text = $0; uses = 0; next }
  catch_line && /^[[:space:]]*\}/ { if (!uses) printf "%d: %s\n", catch_line, catch_text; catch_line = 0; next }
  catch_line && /throw |log\.[a-z]+\(.*, *[a-zA-Z]+\)|return |\.set[A-Z]|fail\(/ { uses = 1 }
' "$file")
[ -n "$swallowed" ] && flag "catch block that neither rethrows the exception nor passes it to the logger — the cause is lost" "$swallowed"
report "printStackTrace / System.out — use the logger" \
  'printStackTrace\(|System\.(out|err)\.'
report "String concatenation in a log call — use {} placeholders" \
  '\blog(ger)?\.(trace|debug|info|warn|error)\(.*" *\+'
report_code "Secret-looking value in a log call" \
  '(^|[^A-Za-z])log(ger)?\.(trace|debug|info|warn|error)\(.*([pP]assword|[tT]oken|[sS]ecret|[aA]uthorization|getCredentials)'
report "@SneakyThrows — hides a checked exception from every caller and from rollback rules" \
  '@SneakyThrows'

# --- core Java ---------------------------------------------------------------
report "String compared with == or != — use equals" \
  '(==|!=) *"|" *(==|!=)'
report "java.util.Date / Calendar / SimpleDateFormat — use java.time" \
  'new Date\(|Calendar\.getInstance|SimpleDateFormat'
[ "$is_test" = 0 ] && report "now() with no Clock or zone — depends on the server time zone and cannot be tested" \
  '(LocalDate|LocalDateTime|LocalTime|ZonedDateTime)\.now\(\)'
report "BigDecimal from a double literal, or compared with equals — use a String constructor and compareTo" \
  'new BigDecimal\([0-9]+\.[0-9]+\)|\.equals\(BigDecimal\.|BigDecimal\.[A-Z]+\.equals\('
report "Money-looking value as double or float — use BigDecimal or integer minor units" \
  '\b(double|float|Double|Float) [a-zA-Z]*([aA]mount|[pP]rice|[tT]otal|[bB]alance|[fF]ee|[cC]ost)[A-Za-z]*\b'
report "Thread.sleep / new Thread — use the scheduler or an executor bean" \
  'Thread\.sleep\(|new Thread\('

# --- tests -------------------------------------------------------------------
if [ "$is_test" = 1 ]; then
  no_assertion=$(awk '
    function braces(text) { return gsub(/\{/, "{", text) - gsub(/\}/, "}", text) }
    in_test {
      depth += braces($0)
      if ($0 ~ /assert|verify\(|andExpect|expect\(|\.should|fail\(|then\(/) asserted = 1
      if (depth <= 0) { if (!asserted) printf "%d: %s\n", test_line, test_text; in_test = 0 }
      next
    }
    /^[[:space:]]*@(Test|ParameterizedTest|RepeatedTest)([^A-Za-z]|$)/ { pending = 1; next }
    pending && /^[[:space:]]*[a-z].*\).*\{[[:space:]]*$/ { in_test = 1; depth = braces($0); asserted = 0; test_line = NR; test_text = $0; pending = 0 }
  ' "$file")
  [ -n "$no_assertion" ] && flag "Test with no assertion — it passes whatever the code does" "$no_assertion"
  report "@Disabled with no reason" '@Disabled[[:space:]]*$'
  report "@DirtiesContext — rebuilds the Spring context; fix the shared state instead" '@DirtiesContext'
  report "@MockBean / @SpyBean — each distinct set builds a new Spring context" '@(MockBean|SpyBean)'
  report "H2 in a test — it does not behave like PostgreSQL; use the project's Testcontainers base" 'jdbc:h2:|org\.h2\.|EmbeddedDatabase'
fi

# --- test coverage -----------------------------------------------------------
unit=$(basename "$file" .java)
if [ "$is_test" = 0 ] && [[ $unit =~ (Controller|ServiceImpl|Service)$ ]] && [ "$is_interface" = 0 ]; then
  root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || dirname "$file")
  tests=$(git -C "$root" ls-files --cached --others --exclude-standard -- '*.java' 2>/dev/null \
    | grep -E "/(${unit}|${unit%Impl})(Test|Tests|IT|IntegrationTest)\.java$" || true)
  [ -n "$tests" ] || flag "No test class for this unit" "  expected ${unit%Impl}Test.java under src/test"
fi

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
