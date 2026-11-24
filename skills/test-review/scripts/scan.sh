#!/usr/bin/env bash
# Mechanical pre-scan for test-review. Catches the deterministic smells so the
# review spends judgement on whether the tests can fail. Heuristic — flags,
# not a verdict.
#
# Every pattern targets what a project without eslint-plugin-jest/vitest
# lacks: no expect-expect, no no-focused-tests, no no-conditional-expect.
#
# Usage: scan.sh <path/to/thing.test.ts>
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <test file>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

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

# --- can it fail --------------------------------------------------------------
report "Focused or skipped test left in" \
  '\b(it|test|describe)\.(only|skip)\(|\bx(it|test|describe)\(|\bf(it|test|describe)\('
report "Tautological assertion — cannot fail" \
  'expect\(true\)\.toBe\(true\)|expect\(false\)\.toBe\(false\)|expect\(([A-Za-z_.]+)\)\.toBe\(\1\)'
report "Weak assertion — passes for any non-empty result, check a value is asserted somewhere" \
  'toBeDefined\(\)|toBeTruthy\(\)|not\.toBeNull\(\)|not\.toBeUndefined\(\)|assert\.ok\(|assert\(|toBeInstanceOf\('
report "Assertion on a mock call — fine as a second assertion, not the first" \
  'toHaveBeenCalled(Times|With)?\('
# Prints the if, else and catch lines whose block holds an assertion.
conditional_assertions() {
  awk '
    function braces(text) { return gsub(/\{/, "{", text) - gsub(/\}/, "}", text) }
    /^[[:space:]]*(\}[[:space:]]*)?(if|else|catch)([^A-Za-z0-9_]|$)/ || /\.catch\(/ {
      if ($0 ~ /(expect|assert)[.(]/) { printf "%d:%s\n", NR, $0; next }
      if ($0 ~ /\{[[:space:]]*$/ && !open) { open = NR; text = $0; depth = 0; seen = 0 }
    }
    open {
      if (NR > open && $0 ~ /(expect|assert)[.(]/) seen = 1
      depth = (NR == open) ? 1 : depth + braces($0)
      if (depth <= 0 && NR > open) {
        if (seen) printf "%d:%s\n", open, text
        open = 0
      }
    }
  ' "$file"
}
conditional=$(conditional_assertions)
[ -n "$conditional" ] && flag "Assertion inside a condition or catch — may never run" "$conditional"
report "Swallowed act — try/catch around the code under test" \
  '^[[:space:]]*try[[:space:]]*\{'

# Test blocks with no assertion at all: count it/test blocks vs expect/assert.
test_blocks=$(grep -E '^[[:space:]]*(it|test)(\.[A-Za-z]+)*[(`]' "$file" | grep -cvE '^[[:space:]]*(it|test)\.(skip|todo)\b')
assertions=$(grep -cE '\b(expect|assert)[.(]' "$file")
if [ "$test_blocks" -gt 0 ] && [ "$assertions" -lt "$test_blocks" ]; then
  flag "Fewer assertions ($assertions) than test blocks ($test_blocks) — some test asserts nothing"
fi

# --- mocking ------------------------------------------------------------------
# The subject is whatever is imported from a relative path and not a helper dir.
helper_dirs='test-utils|testing|fixtures|factories|__mocks__|mocks|helpers'
subject=$(grep -oE "from ['\"](\.\.?/[^'\"]+)['\"]" "$file" \
  | grep -vE "$helper_dirs" \
  | head -1 \
  | sed -E "s/from ['\"](.*)['\"]/\1/")
if [ -n "$subject" ]; then
  subject_regex=$(printf '%s' "$subject" | sed 's/[.[\*^$/]/\\&/g')
  report "Mocks the module under test ($subject)" \
    "(vi|jest)\.mock\(['\"]${subject_regex}['\"]"
fi
report "Mock typed any — shape can drift from the real dependency" \
  'as any\b.*(mock|Mock)|(mock|Mock).*as any\b|: any = .*(mock|jest\.fn|vi\.fn)'
report "spyOn on the subject's own method — tests the wiring, not the result" \
  'spyOn\((service|component|sut|subject|instance)\b'

# --- determinism --------------------------------------------------------------
report "Real time — use fake timers or await the condition" \
  'setTimeout\(r|setTimeout\(resolve|new Promise\(\(?r(esolve)?\)? *=> *setTimeout|\bsleep\(|\bdelay\('
report "Long waitFor timeout — usually hides a race" \
  'waitFor\(.*timeout: *[0-9]{4,}'
report "Random data without a seed" \
  'Math\.random\(|faker\.[a-z]+\.[a-zA-Z]+\('
report "Module-level mutable state — check it is reset in beforeEach" \
  '^(let|var) [A-Za-z_]+ *= *(\[\]|\{\}|new Map|new Set|0|null)'

real_io=$(grep -nE '\b(fetch|axios|got)(\.[a-z]+)?\(|\bfs\.(read|write)|\b(request|supertest)\([^)]*https?://' "$file" | grep -vE 'localhost|127\.0\.0\.1')
[ -n "$real_io" ] && flag "Real network or filesystem in a unit test" "$real_io"

# --- snapshots ----------------------------------------------------------------
report "Snapshot — proves unchanged, not correct; check it is not the only assertion" \
  'toMatch(Inline)?Snapshot\('

# --- naming -------------------------------------------------------------------
report "Test name describes a method or is empty of behaviour" \
  "(it|test)\(['\"](works|should work|test|calls [a-zA-Z]+|returns|handles|it works|renders)['\"]"

# --- hygiene ------------------------------------------------------------------
report "console.* in a test" \
  'console\.(log|warn|debug|info)'
report "TODO/FIXME — confirm intentional" \
  '(TODO|FIXME|XXX)'

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
