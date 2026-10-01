#!/usr/bin/env bash
# Mechanical pre-scan for comment-cleanup. Counts comment lines per file and
# flags the comments RULES.md deletes on sight. Heuristic — flags, not a
# verdict: a line can be flagged and stay, and most "what" comments are not
# flagged at all.
#
# Usage: scan.sh [path…]        default: every tracked file
#   COMMENT_EXT   extensions to scan, as a regex alternation
#                 (default ts|tsx|js|jsx|mjs|cjs)
#   COMMENT_TOP   rows in the per-file table (default 30)
set -uo pipefail

ext="${COMMENT_EXT:-ts|tsx|js|jsx|mjs|cjs}"
top="${COMMENT_TOP:-30}"
skip='(^|/)(node_modules|dist|build|coverage|vendor|generated|__generated__|__snapshots__)/|\.(min|gen|generated)\.|\.d\.ts$'

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  list=$(git ls-files -- "$@")
else
  list=$(find "${@:-.}" -type f)
fi
files=$(printf '%s\n' "$list" | grep -E "\.($ext)$" | grep -vE "$skip")
[ -z "$files" ] && { echo "no source files in scope"; exit 0; }

all=$(mktemp); tool=$(mktemp); human=$(mktemp)
trap 'rm -f "$all" "$tool" "$human"' EXIT

# A full-line comment, a block-comment body line, a JSX comment, or a trailing
# `//` that is not the tail of a URL scheme.
printf '%s\n' "$files" | tr '\n' '\0' |
  xargs -0 grep -HnE '^[[:space:]]*(//|/\*|\*)|\{/\*|[^:"'"'"'`/]//[[:space:]]' > "$all" 2>/dev/null

# Comments a tool reads. RULES.md "Never touched".
directive='eslint-(disable|enable)|@ts-(expect-error|ignore|nocheck|check)|prettier-ignore|biome-ignore|(istanbul|c8|v8) ignore|webpack[A-Z]|@vite-ignore|<reference |@(jest|vitest)-environment|sourceMappingURL|@license|@preserve|Copyright|SPDX-|@deprecated|@internal|@public'
grep -E "$directive" "$all" > "$tool"
grep -vE "$directive" "$all" > "$human"

echo "## Comment lines"
echo "$(wc -l < "$human" | tr -d ' ') to judge in $(cut -d: -f1 "$human" | sort -u | wc -l | tr -d ' ') files; $(wc -l < "$tool" | tr -d ' ') lines a tool reads, left alone"
echo
echo "## Per file, densest first (top $top)"
cut -d: -f1 "$human" | sort | uniq -c | sort -rn | head -n "$top"
echo

# $1 = label, $2 = regex matched against the comment text only, never the
# path. $3 = "cs" for a case-sensitive match; the default lowercases the text.
flag() {
  local out
  out=$(RE="$2" CS="${3:-}" awk '{
    t = $0; sub(/^[^:]*:[0-9]+:/, "", t)
    if (ENVIRON["CS"] == "") t = tolower(t)
    if (t ~ ENVIRON["RE"]) print
  }' "$human")
  [ -n "$out" ] && printf '## %s\n%s\n\n' "$1" "$out"
}

flag "Describes the change, not the code — delete" \
  '^[[:space:]]*(\/\/|\/?\*+)[[:space:]]*(added|removed|changed|fixed|refactored|updated|moved|renamed|replaced|migrated|now|new:|old:)[ :]|no longer|previously|used to be|as requested|per (the )?(plan|task|spec|review)|instead of the old'
flag "Names the outside world: ticket, PR, date, link — delete the reference" \
  'https?:\/\/|(^|[^A-Za-z0-9&])#[0-9]+([^0-9A-Za-z]|$)|(^|[^A-Za-z])(PR|pr|issue|ticket|Issue|Ticket)[ #-]*[0-9]+|(^|[^A-Za-z0-9])[A-Z][A-Z]+-[0-9][0-9]+|20[0-9][0-9]-[01][0-9]-[0-3][0-9]' cs
flag "Banner, divider or region marker — delete" \
  '[-=#~_]{4,}|\*{5,}|#(end)?region'
flag "Step number — delete, or extract a named function" \
  '^[[:space:]]*(\/\/|\*)[[:space:]]*(step[[:space:]]*)?[0-9]+[.):][[:space:]]'
flag "Looks like commented-out code — delete" \
  '^[[:space:]]*\/\/[[:space:]]*((const|let|var|import|export|return|await|function|class|if|for|while)[ (]|[})\]]|<\/?[a-z])|^[[:space:]]*\/\/.*[;{][[:space:]]*$'
out=$(grep -E 'eslint-disable|@ts-(ignore|expect-error|nocheck)' "$tool" |
  grep -vE -- '--|@ts-(ignore|expect-error|nocheck)[[:space:]:-]+[A-Za-z]')
[ -n "$out" ] && printf '## Suppression with no reason — report, do not edit\n%s\n\n' "$out"
flag "TODO / FIXME — list in the report, do not edit" \
  '(^|[^a-z])(todo|fixme|xxx|hack)([^a-z]|$)'

ts=$(grep -E '^[^:]*\.tsx?:' "$human")
if [ -n "$ts" ]; then
  out=$(printf '%s\n' "$ts" | grep -E '@(param|returns?|type)[[:space:]]*\{')
  [ -n "$out" ] && printf '## JSDoc repeating TypeScript types — delete the tag\n%s\n\n' "$out"
fi
exit 0
