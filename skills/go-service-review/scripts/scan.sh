#!/usr/bin/env bash
# Mechanical pre-scan for go-service-review. Catches the deterministic smells
# so the review spends judgement on the rest. Heuristic — flags, not a verdict.
#
# `go build` and `go vet` see little of this: a server with no timeouts, a
# handler that keeps running after it wrote the error, a query built from a
# string, a goroutine nobody stops.
#
# Usage: scan.sh <path/to/file.go>
# Env:   HANDLER      ERE for what marks a handler signature
#                     (default: http.ResponseWriter, gin, echo, fiber contexts)
#        REMOTE_CALL  ERE for calls that leave the process (HTTP, object store, mail, queue)
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <file.go>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

if head -5 "$file" | grep -qE '^// Code generated .* DO NOT EDIT\.$'; then
  echo "generated file — review its source (the .templ, the .sql, the schema), not this"
  exit 0
fi

handler="${HANDLER:-http\.ResponseWriter|\*gin\.Context|echo\.Context|\*fiber\.Ctx}"
remote_call="${REMOTE_CALL:-http\.(Get|Post|Head|PostForm)\(|\.Do\(|\.PutObject\(|\.GetObject\(|smtp\.|[mM]ailer\.|\.Publish\(|\.(Send|Charge|Refund|Notify)[A-Za-z]*\(}"

found_any=0

# flag LABEL LINES — prints a finding with the lines that caused it
flag() {
  printf '## %s\n%s\n\n' "$1" "$2"
  found_any=1
}

# report LABEL REGEX — flags every line of the file that matches
report() {
  local matches
  matches=$(grep -nE -- "$2" "$file" | grep -vE '^[0-9]+:[[:space:]]*//')
  [ -n "$matches" ] && flag "$1" "$matches"
}

# report_code LABEL REGEX — like report, but text inside string literals does not count
report_code() {
  local matches
  matches=$(REGEX=$2 awk '
    /^[[:space:]]*\/\// { next }
    {
      code = $0
      gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
      gsub(/`[^`]*`/, "\"\"", code)
      if (code ~ ENVIRON["REGEX"]) printf "%d:%s\n", NR, $0
    }
  ' "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

has() {
  grep -qE -- "$1" "$file"
}

# funcs_with HAS [LACKS] [SIGNATURE] — prints "LINE: signature" for every
# top-level function whose body has a line matching HAS, no line matching
# LACKS, and whose signature matches SIGNATURE. gofmt puts "func" and the
# closing brace of a top-level function at column 0.
funcs_with() {
  HAS=$1 LACKS=${2:-} SIGNATURE=${3:-} awk '
    function close_func() {
      if (inside && found && !blocked && (ENVIRON["SIGNATURE"] == "" || signature ~ ENVIRON["SIGNATURE"])) {
        printf "%d: %s\n", start, signature
      }
      inside = 0
    }
    /^func / { close_func(); inside = 1; start = NR; signature = $0; found = 0; blocked = 0; open = ($0 ~ /[{}][[:space:]]*$/); next }
    inside && !open { signature = signature " " $0; sub(/[[:space:]]+/, " ", signature); open = ($0 ~ /[{}][[:space:]]*$/); next }
    /^\}/ { close_func(); next }
    inside && /^[[:space:]]*\/\// { next }
    inside {
      if ($0 ~ ENVIRON["HAS"]) found = 1
      if (ENVIRON["LACKS"] != "" && $0 ~ ENVIRON["LACKS"]) blocked = 1
    }
    END { close_func() }
  ' "$file"
}

# in_funcs SIGNATURE — prints "LINE: text" for every body line of a top-level
# function whose signature matches SIGNATURE.
in_funcs() {
  SIGNATURE=$1 awk '
    /^func / { inside = 1; signature = $0; open = ($0 ~ /[{}][[:space:]]*$/); next }
    inside && !open { signature = signature " " $0; open = ($0 ~ /[{}][[:space:]]*$/); next }
    /^\}/ { inside = 0; next }
    inside && /^[[:space:]]*\/\// { next }
    inside && signature ~ ENVIRON["SIGNATURE"] { printf "%d: %s\n", NR, $0 }
  ' "$file"
}

is_test=0
case "$file" in *_test.go) is_test=1 ;; esac
is_main=0
has '^package main$' && is_main=1
go_minor=$(
  dir=$(cd "$(dirname "$file")" && pwd)
  while [ "$dir" != / ]; do
    if [ -f "$dir/go.mod" ]; then
      sed -nE 's/^go 1\.([0-9]+).*/\1/p' "$dir/go.mod" | head -1
      break
    fi
    dir=$(dirname "$dir")
  done
)
go_minor=${go_minor:-0}

# --- stale APIs ---------------------------------------------------------------
report "io/ioutil — deprecated since Go 1.16; use io and os" '"io/ioutil"'
report "golang.org/x/exp slices, maps or slog — in the standard library since Go 1.21" '"golang\.org/x/exp/(slices|maps|slog)"'
report "github.com/pkg/errors — in maintenance mode; wrap with fmt.Errorf and %w" '"github\.com/pkg/errors"'
report "gorilla/csrf — CVE-2025-47909 has no fixed release; use http.CrossOriginProtection (Go 1.25) or filippo.io/csrf" '"github\.com/gorilla/csrf"'
if has '"math/rand(/v2)?"' && grep -qiE 'token|secret|password|session|nonce|otp|api_?key|salt' "$file"; then
  report "math/rand in a file that handles a secret — it is predictable; use crypto/rand" '"math/rand(/v2)?"'
fi
if [ "$go_minor" -ge 22 ]; then
  copies=$(awk 'NF == 3 && $2 == ":=" && $1 == $3 && $1 ~ /^[a-z][A-Za-z0-9]*$/ { printf "%d:%s\n", NR, $0 }' "$file")
  [ -n "$copies" ] && flag "Loop variable copy (x := x) — each iteration has its own variable since Go 1.22; delete it" "$copies"
fi

if [ "$is_test" = 0 ]; then
  # --- errors -----------------------------------------------------------------
  report_code "Error discarded with _ — handle it or state why it cannot happen" \
    '(^|[[:space:]])_ = [A-Za-z_.]+\(|, _ :?= [A-Za-z_.]+\('
  lost_wrap=$(grep -nE 'fmt\.Errorf\(.*,[[:space:]]*[a-zA-Z]*[eE]rr\)' "$file" | grep -v '%w' || true)
  [ -n "$lost_wrap" ] && flag "fmt.Errorf with an error argument and no %w — errors.Is and errors.As stop matching at this line" "$lost_wrap"
  report_code "Error compared with == or != — a wrapped error no longer matches; use errors.Is" \
    '[eE]rr (==|!=) ([a-z][A-Za-z0-9]*\.)?Err[A-Z]'
  report_code "Type assertion on an error — a wrapped error no longer matches; use errors.As (errors.AsType from Go 1.26)" \
    '[eE]rr\.\(\*?[A-Za-z.]+\)'
  report_code "Internal error text sent to the client — log it and answer with the project's error response" \
    'http\.Error\([a-z]+, *[a-zA-Z]*[eE]rr\.Error\(\)|Fprint[a-z]*\([a-z]+, .*[eE]rr(\)|\.Error\(\))|\.(String|JSON|HTML)\([^,]+, *[a-zA-Z]*[eE]rr\.Error\(\)'
  no_return=$(awk '
    function check() { if (pending && $0 !~ /^[[:space:]]*return/ && $0 !~ /^\}/) printf "%d:%s\n", pending, text; pending = 0 }
    pending && NF { check() }
    /^[[:space:]]*(http\.(Error|NotFound|Redirect)\(|[a-zA-Z.]*(render|respond|write)[A-Za-z]*Error\()/ { pending = NR; text = $0 }
  ' "$file")
  [ -n "$no_return" ] && flag "Error response with no return after it — the handler keeps running and writes a second response" "$no_return"
  if [ "$is_main" = 0 ]; then
    report_code "log.Fatal, os.Exit or panic outside package main — deferred cleanup does not run and the caller cannot recover" \
      '(^|[^A-Za-z.])(log\.Fatal[a-z]*|os\.Exit|panic)\('
    report_code "context.Background() or context.TODO() outside main — the caller's deadline and cancellation are lost" \
      'context\.(Background|TODO)\(\)'
    report "func init() — hidden start-up order and no error path; construct in main and pass it in" '^func init\(\)'
    report_code "fmt.Print in library code — use the project's logger" '(^|[^A-Za-z.])fmt\.Print(f|ln)?\('
  fi

  # --- context and deadlines --------------------------------------------------
  report_code "Database call with no context — it cannot be cancelled when the request ends; use the …Context method" \
    '\.(Query|QueryRow|Exec|Prepare|Ping)\("|\.(Query|QueryRow|Exec|Prepare)\([a-z]*([qQ]uery|[sS]ql|[sS]tmt)[,)]|\.(Begin|Ping)\(\)'
  report_code "HTTP request with no context — http.Get and http.NewRequest ignore the caller's deadline; use NewRequestWithContext" \
    'http\.(Get|Post|Head|PostForm|NewRequest)\('
  report_code "time.Sleep — it ignores cancellation; select on ctx.Done() and a timer" 'time\.Sleep\('

  # --- HTTP server and client -------------------------------------------------
  report_code "http.ListenAndServe / http.Serve — a server with no timeouts; build an http.Server and set them" \
    'http\.(ListenAndServe|ListenAndServeTLS|Serve|ServeTLS)\('
  if has 'http\.Server\{' && ! has 'ReadHeaderTimeout|ReadTimeout'; then
    report "http.Server with no ReadHeaderTimeout — a slow client holds a connection forever" 'http\.Server\{'
  fi
  if has 'http\.Client\{' && ! has '(^|[^A-Za-z])Timeout:'; then
    report "http.Client with no Timeout — a hung remote holds the goroutine forever" 'http\.Client\{'
  fi
  report_code "http.DefaultClient — it has no timeout" 'http\.DefaultClient'
  if ! has 'MaxBytesReader'; then
    report_code "Request body read with no size limit — confirm a middleware wraps it in http.MaxBytesReader" \
      'NewDecoder\((r|req|request)\.Body\)|io\.ReadAll\((r|req|request)\.Body\)|\.ParseMultipartForm\('
  fi
  unclosed=$(funcs_with '(resp|res|response|rsp), err :?= .*\.(Do|Get|Post|PostForm|Head)\(' 'Body\.Close\(\)')
  [ -n "$unclosed" ] && flag "Response body never closed in this function — the connection leaks" "$unclosed"
  report "InsecureSkipVerify — TLS verification is off" 'InsecureSkipVerify:[[:space:]]*true'
  shutdown_free=0
  if [ "$is_main" = 1 ] && has 'ListenAndServe' && ! has '\.Shutdown\('; then
    shutdown_free=1
  fi
  [ "$shutdown_free" = 1 ] && report "Server started with no Shutdown — a deploy cuts requests in flight" 'ListenAndServe'

  # --- SQL ----------------------------------------------------------------------
  report "SQL built with fmt.Sprintf or + — injection; pass values as query arguments" \
    'Sprintf\(["`][^"`]*(SELECT |INSERT |UPDATE |DELETE |WHERE |ORDER BY |select |insert |update |delete |where |order by )|(Query|QueryRow|Exec)[A-Za-z]*\([^)]*["`] *\+'
  rows_open=$(funcs_with ':?= .*\.Query(Context)?\(' '\.Close\(\)|CollectRows|CollectOneRow|CollectExactlyOneRow|ForEachRow')
  [ -n "$rows_open" ] && flag "Rows never closed in this function — the connection does not return to the pool" "$rows_open"
  rows_err=$(funcs_with '\.Next\(\)' '\.Err\(\)')
  [ -n "$rows_err" ] && flag "Rows iterated with no rows.Err() check — a failure mid-result looks like a short list" "$rows_err"
  no_rollback=$(funcs_with '\.Begin(Tx)?\(' 'Rollback\(')
  [ -n "$no_rollback" ] && flag "Transaction begun with no deferred Rollback — an early return holds the connection and the locks" "$no_rollback"
  remote_in_tx=$(funcs_with '\.Begin(Tx)?\(' '' '' | while IFS= read -r row; do
    start=${row%%:*}
    START=$start REMOTE=$remote_call awk '
      NR < ENVIRON["START"] { next }
      NR > ENVIRON["START"] && /^\}/ { exit }
      /\.Begin(Tx)?\(/ { begun = 1; next }
      /\.Commit\(/ { begun = 0 }
      begun && $0 ~ ENVIRON["REMOTE"] { printf "%d:%s\n", NR, $0 }
    ' "$file"
  done)
  [ -n "$remote_in_tx" ] && flag "Remote call between Begin and Commit — the database connection is held for the round trip" "$remote_in_tx"

  # --- concurrency --------------------------------------------------------------
  report_code "Goroutine started — name who stops it, who sees its error and what recovers its panic" \
    '^[[:space:]]*go (func\(|[A-Za-z_.]+\()'
  report_code "Package-level mutable variable — every request goroutine shares it" \
    '^var [A-Za-z_][A-Za-z0-9_]* +(= +)?(map\[|\[\][A-Za-z*]|make\(|[a-z]*[iI]nt[0-9]*( |$)|bool( |$))'
  defer_in_loop=$(awk '
    function braces(text) { gsub(/"([^"\\]|\\.)*"/, "", text); return gsub(/\{/, "{", text) - gsub(/\}/, "}", text) }
    /^[[:space:]]*\/\// { next }
    {
      while (top > 0 && depth <= level[top] && $0 ~ /^[[:space:]]*\}/) top--
      if ($0 ~ /^[[:space:]]*defer / && top > 0 && kind[top] == "for") printf "%d:%s\n", NR, $0
      if ($0 ~ /^[[:space:]]*for .*\{[[:space:]]*$/ || $0 ~ /^[[:space:]]*for \{[[:space:]]*$/) { top++; kind[top] = "for"; level[top] = depth }
      else if ($0 ~ /func\(.*\{[[:space:]]*$/) { top++; kind[top] = "func"; level[top] = depth }
      depth += braces($0)
    }
  ' "$file")
  [ -n "$defer_in_loop" ] && flag "defer inside a loop — it runs when the function returns, not each iteration" "$defer_in_loop"

  # --- templates and output -----------------------------------------------------
  report "text/template — it does not escape; HTML goes through html/template or templ" '"text/template"'
  report_code "Escaping bypass (template.HTML and friends, templ.Raw, templ.SafeURL) — prove the value never holds user input" \
    'template\.(HTML|HTMLAttr|JS|JSStr|CSS|URL|Srcset)\(|templ\.(Raw|SafeURL|SafeCSS|SafeScript)\('
  parsed_per_request=$(in_funcs "$handler" | grep -E 'template\.(New|ParseFiles|ParseGlob|ParseFS|Must)\(' || true)
  [ -n "$parsed_per_request" ] && flag "Template parsed inside a handler — it is read and parsed on every request; parse once at start-up" "$parsed_per_request"
  report_code "Template executed straight into the ResponseWriter — an error mid-render leaves half a page with status 200; render to a buffer" \
    '\.Execute(Template)?\((w|rw|writer|c\.Writer),'

  # --- htmx responses -------------------------------------------------------------
  if has 'HX-Request'; then
    has '"Vary"' || report "HX-Request decides the response with no Vary header — a cache or the back button serves the fragment as a page" 'HX-Request'
    report_code "http.Redirect in an htmx handler — the browser follows a 3xx inside the request and the page lands in the target; use HX-Redirect or HX-Location" \
      'http\.Redirect\('
  fi
  report "Status 286 — it stops polling in htmx 2 only; htmx 4 ignores it" 'WriteHeader\(286\)|Status\(286\)'
  report "HX-Trigger-After-Swap / HX-Trigger-After-Settle — removed in htmx 4" 'HX-Trigger-After-(Swap|Settle)'

  # --- identity and input -------------------------------------------------------
  report "Identity read from the request — a client sets any header, form field or query value; read it from the authenticated context" \
    '(FormValue|PostFormValue|Query\(\)\.Get|Header\.Get|Cookie)\("([xX]-)?([uU]ser|[tT]enant|[oO]rg|[aA]ccount|[oO]wner|[rR]ole)([-_]?[iI][dD])?"\)'
  sql_in_handler=$(in_funcs "$handler" | grep -E '\.(Query|QueryRow|Exec)(Context)?\(' || true)
  [ -n "$sql_in_handler" ] && flag "SQL in a handler — confirm the project layer puts data access here" "$sql_in_handler"

  # --- core Go ------------------------------------------------------------------
  report_code "Money-looking value as float — use integer minor units or a decimal type" \
    '[a-zA-Z]*([aA]mount|[pP]rice|[tT]otal|[bB]alance|[fF]ee|[cC]ost)[A-Za-z]* +(\*|\[\])?float(32|64)'
  report_code "Secret-looking value in a log call" \
    '(^|[^A-Za-z])(slog|log|logger|zap|l)\.[A-Za-z.]*(Debug|Info|Warn|Error|Print|Fatal|With)[A-Za-z]*\(.*([pP]assword|[tT]oken|[sS]ecret|[aA]uthorization|[cC]ookie|[aA]pi[kK]ey)'
fi

# --- tests --------------------------------------------------------------------
if [ "$is_test" = 1 ]; then
  no_assertion=$(funcs_with '.' '(^|[^A-Za-z])t\.(Error|Fatal|Fail|Run)|assert\.|require\.|\.Expect|cmp\.Diff|synctest\.|(^|[[:space:]])(is|qt|c)\.[A-Z]' '^func Test[A-Za-z0-9_]*\(')
  [ -n "$no_assertion" ] && flag "Test with no assertion — it passes whatever the code does" "$no_assertion"
  report "t.Skip with no reason" '\.Skip(Now)?\(\)'
  report_code "time.Sleep in a test — slow and flaky; use testing/synctest (Go 1.25) or wait on a channel" 'time\.Sleep\('
  report "sqlmock — the test passes on a query the database rejects; use the project's real-engine fixture" '"github\.com/DATA-DOG/go-sqlmock"'
  report_code "context.Background() in a test — t.Context() (Go 1.24) is cancelled when the test ends" 'context\.(Background|TODO)\(\)'
fi

# --- test coverage ------------------------------------------------------------
if [ "$is_test" = 0 ] && [ "$is_main" = 0 ]; then
  dir=$(dirname "$file")
  unit=$(basename "$file" .go)
  if ! ls "$dir"/*_test.go > /dev/null 2>&1; then
    flag "No test in this package" "  expected a _test.go file in $dir"
  elif [ ! -f "$dir/${unit}_test.go" ]; then
    flag "No ${unit}_test.go — confirm another test file of the package covers this one" "  $dir has tests, none named after this file"
  fi
fi

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
