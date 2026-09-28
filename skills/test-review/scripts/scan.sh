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
[ -z "$file" ] && { echo "usage: scan.sh <test file>" >&2; exit 1; }
[ -f "$file" ] || { echo "not found: $file" >&2; exit 1; }

hits=0
report() {
  local out
  out=$(grep -nE "$2" "$file")
  if [ -n "$out" ]; then printf '## %s\n%s\n\n' "$1" "$out"; hits=1; fi
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
report "Assertion inside a condition or catch — may never run" \
  '^[[:space:]]*(if|else|catch)\b.*\{[[:space:]]*$|\.catch\(.*expect'
report "Swallowed act — try/catch around the code under test" \
  '^[[:space:]]*try[[:space:]]*\{'

# Test blocks with no assertion at all: count it/test blocks vs expect/assert.
blocks=$(grep -cE '^\s*(it|test)\(' "$file")
asserts=$(grep -cE '\b(expect|assert)[.(]' "$file")
if [ "$blocks" -gt 0 ] && [ "$asserts" -lt "$blocks" ]; then
  printf '## Fewer assertions (%s) than test blocks (%s) — some test asserts nothing\n\n' "$asserts" "$blocks"
  hits=1
fi

# --- mocking ------------------------------------------------------------------
# The subject is whatever is imported from a relative path and not a helper dir.
subject=$(grep -oE "from ['\"](\.\.?/[^'\"]+)['\"]" "$file" | grep -vE 'test-utils|testing|fixtures|factories|__mocks__|mocks|helpers' | head -1 | sed -E "s/from ['\"](.*)['\"]/\1/")
if [ -n "$subject" ]; then
  esc=$(printf '%s' "$subject" | sed 's/[.[\*^$/]/\\&/g')
  report "Mocks the module under test ($subject)" \
    "(vi|jest)\.mock\(['\"]${esc}['\"]"
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
out=$(grep -nE '\b(fetch|axios|got)\(|\bfs\.(read|write)|https?://' "$file" | grep -vE 'localhost|127\.0\.0\.1')
[ -n "$out" ] && { printf '## Real network or filesystem in a unit test\n%s\n\n' "$out"; hits=1; }

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

[ "$hits" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
