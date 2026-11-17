#!/usr/bin/env bash
# Revert check: do the changed tests fail without the change they cover?
#
# Reverses the non-test hunks of a diff in the working tree, runs the test
# files the diff touches, restores the tree, and lists every test file that
# still passed with the code reverted. Those tests do not test the change.
#
#   bash revert-check.sh <diff-file>        # a snapshot from `git diff`
#   git diff | bash revert-check.sh -
#
# Runner is detected from package.json (vitest, jest, node --test, mocha),
# or set TEST_CMD to the command that takes test file paths as arguments.
# The tree is restored on every exit path; it is the same `git apply` the
# delivery loop already uses for redo.
set -uo pipefail

diff_arg="${1:-}"
if [ -z "$diff_arg" ]; then
  echo "usage: revert-check.sh <diff-file | ->" >&2
  exit 2
fi

work=$(mktemp -d)
snapshot="$work/all.diff"
source_diff="$work/src.diff"
if [ "$diff_arg" = "-" ]; then
  cat > "$snapshot"
else
  cp "$diff_arg" "$snapshot"
fi

# finish MESSAGE EXIT_CODE — for the ways out before the tree is touched
finish() {
  echo "$1"
  rm -rf "$work"
  exit "$2"
}

test_path='(\.(spec|test)\.[cm]?[jt]sx?$|(^|/)(__tests__|test|tests|e2e)/)'
test_files=()
source_files=()
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if [[ $path =~ $test_path ]]; then
    test_files+=("$path")
  else
    source_files+=("$path")
  fi
done < <(grep -E '^\+\+\+ b/' "$snapshot" | sed 's#^+++ b/##')

[ ${#test_files[@]} -gt 0 ] || finish "no test files in the diff — nothing to check" 0
[ ${#source_files[@]} -gt 0 ] || finish "no non-test files in the diff — nothing to revert" 0

# The hunks to reverse: only the non-test paths.
git diff -- "${source_files[@]}" > "$source_diff"
[ -s "$source_diff" ] || finish "non-test paths have no working-tree diff — is the snapshot current?" 2

detect_test_command() {
  local dependencies
  dependencies=$(node -e '
    const pkg = require("./package.json");
    console.log(Object.keys({ ...pkg.dependencies, ...pkg.devDependencies }).join(" "));
  ' 2> /dev/null)
  case " $dependencies " in
    *" vitest "*) echo "npx vitest run" ;;
    *" jest "*)   echo "npx jest --runTestsByPath" ;;
    *" mocha "*)  echo "npx mocha" ;;
    *)            echo "node --test" ;;
  esac
}
test_command="${TEST_CMD:-$(detect_test_command)}"

restore_source() {
  git apply "$source_diff" 2> /dev/null || echo "RESTORE FAILED — run: git apply $source_diff" >&2
}

if ! git apply -R "$source_diff"; then
  echo "could not reverse the source hunks" >&2
  rm -rf "$work"
  exit 2
fi
trap restore_source EXIT

still_passing=()
for test_file in "${test_files[@]}"; do
  [ -f "$test_file" ] || continue   # test deleted by the diff
  # shellcheck disable=SC2086
  if $test_command "$test_file" > "$work/out.txt" 2>&1; then
    still_passing+=("$test_file")
  fi
done

if [ ${#still_passing[@]} -eq 0 ]; then
  echo "revert check: every changed test fails without the change (${#test_files[@]} file(s))"
  exit 0
fi
echo "revert check: these tests still PASS with the change reverted — they do not test it:"
printf '  %s\n' "${still_passing[@]}"
exit 1
