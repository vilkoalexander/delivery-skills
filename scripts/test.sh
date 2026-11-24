#!/usr/bin/env bash
# Runs every script test in the repository, or the ones named.
#
#   bash scripts/test.sh              all of them
#   bash scripts/test.sh risk mark    only tests whose path contains a word
set -uo pipefail
cd "$(dirname "$0")/.."

failed=()
ran=0

wanted() {
  [ $# -eq 1 ] && return 0
  local path=$1 word
  shift
  for word in "$@"; do
    [[ $path == *"$word"* ]] && return 0
  done
  return 1
}

run() {
  local label=$1
  shift
  ran=$((ran + 1))
  if output=$("$@" 2>&1 < /dev/null); then
    echo "ok    $label"
  else
    echo "FAIL  $label"
    printf '%s\n' "$output" | grep -E '^(FAIL|not ok|       )' | sed 's/^/      /'
    failed+=("$label")
  fi
}

while IFS= read -r test_file; do
  [ -f "$test_file" ] || continue
  wanted "$test_file" "$@" && run "$test_file" bash "$test_file"
done < <(git ls-files --cached --others --exclude-standard -- '*.test.sh' | sort)

node_tests=skills/factory-floor/tests/factory-floor.test.ts
wanted "$node_tests" "$@" && run "$node_tests" node --test "$node_tests"

python_tests=skills/memory-dash/tests/test_memory_dash.py
wanted "$python_tests" "$@" && run "$python_tests" python3 "$python_tests"

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "$ran test files, all passed"
else
  echo "$ran test files, ${#failed[@]} failed: ${failed[*]}"
  exit 1
fi
