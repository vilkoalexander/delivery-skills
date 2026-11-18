#!/usr/bin/env bash
# Shared by the *.test.sh files: source it, write checks, call `finish` last.
#
#   has NAME EXIT PATTERN command...   exit code and output (ERE; "" means silence)
#   lacks NAME PATTERN command...      output does not match
#   sees NAME PATTERN TEXT             text already captured matches
#   misses NAME PATTERN TEXT           text already captured does not match
#   eq NAME GOT WANT
#   under TITLE                        the lines of $out below the heading that starts with TITLE
#   new_repo NAME                      empty git repo under $tmp, and cd into it
#   commit_all                         commit everything in the current repo
set -uo pipefail

# Physical path: git prints /private/var/… on macOS where mktemp prints /var/….
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
export DELIVERY_RUN_DIR="$tmp/runs" DELIVERY_EVENTS_DIR="$tmp/events" DEP_VET=off
unset TYPESAFE_API_KEY
# Several scripts read paths from stdin when it is not a terminal.
exec < /dev/null

pass=0
fail=0

ok() {
  pass=$((pass + 1))
  echo "ok   - $1"
}

nok() {
  fail=$((fail + 1))
  echo "FAIL - $1"
  printf '%s\n' "$2" | sed 's/^/       /'
}

# A here-string, not a pipe: with pipefail, grep -q leaving early fails the writer and the match with it.
matches() {
  grep -qE -- "$1" <<< "$2"
}

eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else nok "$1" "got '$2', wanted '$3'"; fi
}

sees() {
  if matches "$2" "$3"; then ok "$1"; else nok "$1" "no match for $2"$'\n'"$3"; fi
}

misses() {
  if matches "$2" "$3"; then nok "$1" "unexpected match for $2"$'\n'"$3"; else ok "$1"; fi
}

has() {
  local name=$1 want=$2 pattern=$3 out code
  shift 3
  out=$("$@" 2>&1 < /dev/null)
  code=$?
  if [ "$code" != "$want" ]; then
    nok "$name" "exit $code, wanted $want"$'\n'"$out"
  elif [ -z "$pattern" ] && [ -n "$out" ]; then
    nok "$name" "expected silence"$'\n'"$out"
  elif [ -n "$pattern" ] && ! matches "$pattern" "$out"; then
    nok "$name" "no match for $pattern"$'\n'"$out"
  else
    ok "$name"
  fi
}

lacks() {
  local name=$1 pattern=$2 out
  shift 2
  out=$("$@" 2>&1 < /dev/null)
  misses "$name" "$pattern" "$out"
}

# Headings are "## Title" or "=== Title". ENVIRON, not -v: -v rewrites backslashes.
under() {
  printf '%s\n' "$out" | TITLE=$1 awk '
    /^(## |=== )/ {
      on = (index($0, "## " ENVIRON["TITLE"]) == 1 || index($0, "=== " ENVIRON["TITLE"]) == 1)
      next
    }
    on && NF
  '
}

new_repo() {
  mkdir -p "$tmp/$1"
  cd "$tmp/$1" || exit 1
  git init -q
}

commit_all() {
  git add -A
  git -c user.name=test -c user.email=test@test commit -qm "${1:-base}"
}

finish() {
  echo
  echo "passed: $pass  failed: $fail"
  [ "$fail" = 0 ]
}
