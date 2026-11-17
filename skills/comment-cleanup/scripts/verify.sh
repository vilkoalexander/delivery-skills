#!/usr/bin/env bash
# Confirms a comment cleanup changed comments and nothing else. For each file
# in the working-tree diff it strips the comments from the removed lines and
# from the added lines and compares what is left; a difference is code that
# changed.
#
# Heuristic, and it errs toward reporting: the inner lines of a block comment
# written without a leading `*` read as code and are flagged. Look at those
# by hand.
#
# Usage: verify.sh [path…]      default: the whole working tree
# Exit 1 when a file changed outside its comments, or was added, deleted or
# renamed.
set -uo pipefail

# Removes comments and all whitespace, so two versions of a line compare equal when only comments differ.
strip_comments() {
  sed -E \
    -e 's#\{[[:space:]]*/\*.*\*/[[:space:]]*\}##g' \
    -e 's#/\*.*\*/##g' \
    -e 's#<!--.*-->##g' \
    -e '/^[[:space:]]*(\/\/|\/\*|\*)/d' \
    -e 's#(^|[^:])//.*$#\1#' \
    -e 's/[[:space:]]+//g' \
    -e '/^$/d'
}

# code_on_side DIFF SIGN — the code left on the removed (-) or added (+) side of a diff
code_on_side() {
  local file_header
  if [ "$2" = "-" ]; then file_header='^---'; else file_header='^+++'; fi
  printf '%s\n' "$1" | grep "^[$2]" | grep -v "$file_header" | sed 's/^.//' | strip_comments
}

failed=0
changed_count=0

added_deleted_or_renamed=$(git status --porcelain -- "$@" | grep -vE '^( M|M |MM) ')
if [ -n "$added_deleted_or_renamed" ]; then
  printf 'NOT A COMMENT CHANGE — files added, deleted or renamed:\n%s\n\n' "$added_deleted_or_renamed"
  failed=1
fi

while IFS= read -r file; do
  [ -n "$file" ] || continue
  changed_count=$((changed_count + 1))

  diff=$(git diff -U0 -- "$file")
  removed_code=$(code_on_side "$diff" -)
  added_code=$(code_on_side "$diff" +)
  [ "$removed_code" = "$added_code" ] && continue

  printf 'CODE CHANGED — %s\n' "$file"
  diff <(printf '%s\n' "$removed_code") <(printf '%s\n' "$added_code") | grep '^[<>]' | head -n 20
  echo
  failed=1
done < <(git diff --name-only -- "$@")

if [ "$failed" -eq 0 ]; then
  echo "ok: $changed_count file(s) changed, comment lines only"
else
  echo "FAILED: $changed_count file(s) changed, see above"
fi
exit "$failed"
