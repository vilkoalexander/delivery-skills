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

extensions="${COMMENT_EXT:-ts|tsx|js|jsx|mjs|cjs}"
table_rows="${COMMENT_TOP:-30}"
not_source='(^|/)(node_modules|dist|build|coverage|vendor|generated|__generated__|__snapshots__)/|\.(min|gen|generated)\.|\.d\.ts$'

if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  candidates=$(git -c core.quotePath=false ls-files -- "$@")
else
  candidates=$(find "${@:-.}" -type f)
fi
files=$(printf '%s\n' "$candidates" | grep -E "\.($extensions)$" | grep -vE "$not_source")
if [ -z "$files" ]; then
  echo "no source files in scope"
  exit 0
fi

all_comments=$(mktemp)
for_tools=$(mktemp)
for_humans=$(mktemp)
trap 'rm -f "$all_comments" "$for_tools" "$for_humans"' EXIT

# A full-line comment, a block-comment body line, a JSX comment, or a trailing
# `//` that is not the tail of a URL scheme.
comment_line='^[[:space:]]*(//|/\*|\*)|\{/\*|[^:"'"'"'`/]//[[:space:]]'
printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -HnE "$comment_line" > "$all_comments" 2> /dev/null

# Comments a tool reads. RULES.md "Never touched".
directive='eslint-(disable|enable)|@ts-(expect-error|ignore|nocheck|check)|prettier-ignore|biome-ignore|(istanbul|c8|v8) ignore|webpack[A-Z]|@vite-ignore|<reference |@(jest|vitest)-environment|sourceMappingURL|@license|@preserve|Copyright|SPDX-|@deprecated|@internal|@public'
grep -E "$directive" "$all_comments" > "$for_tools"
grep -vE "$directive" "$all_comments" > "$for_humans"

count_lines() {
  wc -l | tr -d ' '
}

comments_to_judge=$(count_lines < "$for_humans")
files_to_judge=$(cut -d: -f1 "$for_humans" | sort -u | count_lines)
comments_for_tools=$(count_lines < "$for_tools")

echo "## Comment lines"
echo "$comments_to_judge to judge in $files_to_judge files; $comments_for_tools lines a tool reads, left alone"
echo
echo "## Per file, densest first (top $table_rows)"
cut -d: -f1 "$for_humans" | sort | uniq -c | sort -rn | head -n "$table_rows"
echo

section() {
  [ -n "$2" ] && printf '## %s\n%s\n\n' "$1" "$2"
}

# flag LABEL REGEX [cs] — the regex is matched against the comment text only, never the
# path. "cs" makes the match case-sensitive; the default lowercases the text first.
flag() {
  local matches
  matches=$(REGEX=$2 CASE_SENSITIVE=${3:-} awk '
    {
      text = $0
      sub(/^[^:]*:[0-9]+:/, "", text)
      if (ENVIRON["CASE_SENSITIVE"] == "") text = tolower(text)
      if (text ~ ENVIRON["REGEX"]) print
    }
  ' "$for_humans")
  section "$1" "$matches"
}

flag "Describes the change, not the code — delete" \
  '^[[:space:]]*(\/\/|\/?\*+)[[:space:]]*(added|removed|changed|fixed|refactored|updated|moved|renamed|replaced|migrated|now|new:|old:)[ :]|no longer|previously|used to be|as requested|per (the )?(plan|task|spec|review)|instead of the old'
flag "Names the outside world: ticket, PR, date, link — delete the reference" \
  'https?:\/\/|(^|[^A-Za-z0-9&])#[0-9]+([^0-9A-Za-z]|$)|(^|[^A-Za-z])(PR|pr|issue|ticket|Issue|Ticket)[ #-]*[0-9]+|(^|[^A-Za-z0-9])[A-Z][A-Z]+-[0-9][0-9]+|20[0-9][0-9]-[01][0-9]-[0-3][0-9]' cs
# Written out, not {4,}: older mawk has no interval expressions.
flag "Banner, divider or region marker — delete" \
  '[-=#~_][-=#~_][-=#~_][-=#~_]|\*\*\*\*\*|#(end)?region'
flag "Step number — delete, or extract a named function" \
  '^[[:space:]]*(\/\/|\*)[[:space:]]*(step[[:space:]]*)?[0-9]+[.):][[:space:]]'
flag "Looks like commented-out code — delete" \
  '^[[:space:]]*\/\/[[:space:]]*((const|let|var|import|export|return|await|function|class|if|for|while)[ (]|[})\]]|<\/?[a-z])|^[[:space:]]*\/\/.*[;{][[:space:]]*$'

suppression='eslint-disable|@ts-(ignore|expect-error|nocheck)'
with_a_reason='--|@ts-(ignore|expect-error|nocheck)[[:space:]:-]+[A-Za-z]'
section "Suppression with no reason — report, do not edit" \
  "$(grep -E "$suppression" "$for_tools" | grep -vE -- "$with_a_reason")"

flag "TODO / FIXME — list in the report, do not edit" \
  '(^|[^a-z])(todo|fixme|xxx|hack)([^a-z]|$)'

section "JSDoc repeating TypeScript types — delete the tag" \
  "$(grep -E '^[^:]*\.tsx?:' "$for_humans" | grep -E '@(param|returns?|type)[[:space:]]*\{')"
exit 0
