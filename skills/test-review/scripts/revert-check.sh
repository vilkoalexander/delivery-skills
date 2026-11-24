#!/usr/bin/env bash
# Revert check: do the changed tests fail without the change they cover?
#
#   bash revert-check.sh [path...]        default: every changed path
#
# Runs the changed test files with the change, and each one must pass. Then it
# puts the changed files that are not tests back to the base, runs the tests
# again, restores the tree, and lists every test file that still passed. Those
# tests do not test the change.
#
# Exit 0: every changed test fails without the change, or there is nothing to
# check. Exit 1: a test passes either way. Exit 2: could not check (no runner,
# a test that fails with the change). Exit 3: the tree could not be restored.
#
#   DELIVERY_BASE   tree-ish the change starts from (default HEAD)
#   TEST_CMD        the command that takes test file paths as arguments
#                   (default: detected from package.json: vitest, jest, mocha, node --test)
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "revert-check: not a git repository" >&2
  exit 2
fi
cd "$root"
source "$here/../../delivery-pipeline/scripts/lib/changes.sh"

base=$(changes_base)
after=$(worktree_tree) || exit 2
export DELIVERY_TREE=$after
load_paths "" "$@" || exit 2

test_files=()
source_files=()
for path in ${paths[@]+"${paths[@]}"}; do
  [ -n "$(changes_diff "" --name-only -- "$path")" ] || continue
  if is_test_path "$path"; then
    [ -f "$path" ] && test_files+=("$path")
  else
    source_files+=("$path")
  fi
done

if [ ${#test_files[@]} -eq 0 ]; then
  echo "revert check: n/a — no changed test file"
  exit 0
fi
if [ ${#source_files[@]} -eq 0 ]; then
  echo "revert check: n/a — no changed file that is not a test, nothing to revert"
  exit 0
fi

detect_test_command() {
  [ -f package.json ] || return 1
  local dependencies
  dependencies=$(node -e '
    const pkg = require("./package.json");
    console.log(Object.keys({ ...pkg.dependencies, ...pkg.devDependencies }).join(" "));
  ' 2> /dev/null) || return 1
  case " $dependencies " in
    *" vitest "*) echo "npx vitest run" ;;
    *" jest "*)   echo "npx jest --runTestsByPath" ;;
    *" mocha "*)  echo "npx mocha" ;;
    *)            echo "node --test" ;;
  esac
}
if ! test_command="${TEST_CMD:-$(detect_test_command)}" || [ -z "$test_command" ]; then
  echo "revert check: n/a — no runner rule for this project; set TEST_CMD"
  exit 0
fi

log=$(mktemp)
passes() {
  # shellcheck disable=SC2086
  $test_command "$1" > "$log" 2>&1 < /dev/null
}

broken=()
for test_file in "${test_files[@]}"; do
  passes "$test_file" || broken+=("$test_file")
done
if [ ${#broken[@]} -gt 0 ]; then
  echo "revert check: could not check — these tests do not pass with the change (runner: $test_command):"
  printf '  %s\n' "${broken[@]}"
  tail -5 "$log" | sed 's/^/    /'
  rm -f "$log"
  exit 2
fi

restored=no
restore() {
  [ "$restored" = no ] || return 0
  restored=yes
  restore_paths "$after" "${source_files[@]}"
  if [ "$(DELIVERY_TREE= worktree_tree)" != "$after" ]; then
    echo "RESTORE FAILED — the tree is not as it was. The change is the tree $after:" >&2
    echo "  git diff $after   shows what differs; git restore --source=$after --worktree -- <path> puts a file back" >&2
    restored=failed
  fi
}
finish() {
  restore
  rm -f "$log"
  [ "$restored" = failed ] && exit 3
}
trap finish EXIT
trap 'exit 130' INT TERM

if ! restore_paths "$base" "${source_files[@]}"; then
  echo "revert check: could not put the changed files back to the base" >&2
  exit 2
fi

still_passing=()
for test_file in "${test_files[@]}"; do
  passes "$test_file" && still_passing+=("$test_file")
done
restore
[ "$restored" = failed ] && exit 3

if [ ${#still_passing[@]} -eq 0 ]; then
  echo "revert check: every changed test fails without the change (${#test_files[@]} file(s))"
  exit 0
fi
echo "revert check: these tests still PASS with the change reverted — they do not test it:"
printf '  %s\n' "${still_passing[@]}"
exit 1
