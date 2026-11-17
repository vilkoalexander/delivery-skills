#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/test-lib.sh"
budget="$here/token-budget.sh"
repo=$(cd "$here/.." && pwd)

tokens_of() { echo $(( $(cat "$@" | wc -c) / 4 )); }
row() { printf '%s\n' "$out" | grep -F -- "$1" | awk '{print $NF}'; }

echo "# with a superpowers skill directory"
sdd="$tmp/sdd"
mkdir -p "$sdd"
head -c 400 /dev/zero > "$sdd/SKILL.md"
head -c 800 /dev/zero > "$sdd/task-reviewer-prompt.md"
out=$(cd "$tmp" && bash "$budget" "$sdd")
eq   "exits 0"                          "$?" 0
eq   "SDD skill is bytes / 4"           "$(row '+ superpowers SDD SKILL.md')" 100
eq   "SDD reviewer prompt is bytes / 4" "$(row 'SDD task-reviewer prompt')" 200
eq   "reviewer agent matches the file"  "$(row 'reviewer agent definition')" "$(tokens_of "$repo/agents/reviewer.md")"
eq   "review-routing matches the file"  "$(row 'review-routing')" "$(tokens_of "$repo/skills/review-routing/SKILL.md")"
eq   "a row sums several files"         "$(row 'comment-cleanup: SKILL + RULES')" "$(tokens_of "$repo/skills/comment-cleanup/SKILL.md" "$repo/skills/comment-cleanup/RULES.md")"
sees "one row per review rubric"        'react-review: CHECKLIST \+ INVENTORY.md' "$out"
sees "description total is a number"    'all skills +[0-9]+$' "$out"
sees "says what is not counted"         '^Not counted: ' "$out"

echo "# without one"
out=$(HOME="$tmp/empty-home" bash "$budget")
eq     "exits 0"                 "$?" 0
misses "no SDD rows"             'SDD' "$out"
sees   "the rest is still there" 'reviewer agent definition' "$out"

finish
