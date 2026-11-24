#!/usr/bin/env bash
# Confirms a comment cleanup changed comments and nothing else. For each file
# that differs from HEAD, staged or not, it strips the comments from the HEAD
# version and from the working version (strip.mjs) and compares what is left;
# a difference is code that changed.
#
# It errs toward reporting: text the stripper cannot place, such as an
# apostrophe in JSX text, stays in the comparison.
#
# Usage: verify.sh [path…]      default: the whole working tree
# Exit 1 when a file changed outside its comments, or was added, deleted or
# renamed. Exit 2 when the check could not run.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)

if ! root=$(git rev-parse --show-toplevel 2> /dev/null); then
  echo "verify: not a git repository" >&2
  exit 2
fi
if ! command -v node > /dev/null 2>&1; then
  echo "verify: node is not on PATH" >&2
  exit 2
fi

failed=0
changed_count=0
modified=()
came_or_went=()

while IFS= read -r -d '' status && IFS= read -r -d '' file; do
  if [ "$status" = M ]; then modified+=("$file"); else came_or_went+=("$status $file"); fi
done < <(git diff -z --name-status --no-renames HEAD -- "$@")
while IFS= read -r -d '' file; do
  came_or_went+=("? $file")
done < <(git ls-files -z --others --exclude-standard -- "$@")

if [ ${#came_or_went[@]} -gt 0 ]; then
  printf 'NOT A COMMENT CHANGE — files added, deleted or renamed:\n'
  printf '%s\n' "${came_or_went[@]}"
  echo
  failed=1
fi

for file in ${modified[@]+"${modified[@]}"}; do
  changed_count=$((changed_count + 1))

  if ! before=$(git show "HEAD:$file" | node "$here/strip.mjs" "$file") \
    || ! after=$(node "$here/strip.mjs" "$file" < "$root/$file"); then
    echo "verify: could not read $file" >&2
    exit 2
  fi
  [ "$before" = "$after" ] && continue

  printf 'CODE CHANGED — %s\n' "$file"
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep '^[<>]' | head -n 20
  echo
  failed=1
done

if [ "$failed" -eq 0 ]; then
  echo "ok: $changed_count file(s) changed, comment lines only"
else
  echo "FAILED: $changed_count file(s) changed, see above"
fi
exit "$failed"
