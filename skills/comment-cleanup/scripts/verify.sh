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

strip() {
  sed -E \
    -e 's#\{[[:space:]]*/\*.*\*/[[:space:]]*\}##g' \
    -e 's#/\*.*\*/##g' \
    -e 's#<!--.*-->##g' \
    -e '/^[[:space:]]*(\/\/|\/\*|\*)/d' \
    -e 's#(^|[^:])//.*$#\1#' \
    -e 's/[[:space:]]+//g' \
    -e '/^$/d'
}

bad=0; n=0

moved=$(git status --porcelain -- "$@" | grep -vE '^( M|M |MM) ')
if [ -n "$moved" ]; then
  printf 'NOT A COMMENT CHANGE — files added, deleted or renamed:\n%s\n\n' "$moved"
  bad=1
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  n=$((n + 1))
  d=$(git diff -U0 -- "$f")
  minus=$(printf '%s\n' "$d" | grep '^-' | grep -v '^---' | sed 's/^-//' | strip)
  plus=$(printf '%s\n' "$d" | grep '^+' | grep -v '^+++' | sed 's/^+//' | strip)
  if [ "$minus" != "$plus" ]; then
    printf 'CODE CHANGED — %s\n' "$f"
    diff <(printf '%s\n' "$minus") <(printf '%s\n' "$plus") | grep '^[<>]' | head -n 20
    echo
    bad=1
  fi
done <<EOF
$(git diff --name-only -- "$@")
EOF

if [ "$bad" -eq 0 ]; then
  echo "ok: $n file(s) changed, comment lines only"
else
  echo "FAILED: $n file(s) changed, see above"
fi
exit "$bad"
