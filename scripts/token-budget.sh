#!/usr/bin/env bash
# Estimates what each dispatch in this plugin loads, in tokens (bytes / 4).
# Run after editing a skill to see what the edit costs every task.
#
# Usage: bash scripts/token-budget.sh [path-to-superpowers-sdd-skill]
set -uo pipefail
cd "$(dirname "$0")/.."
sdd="${1:-$(ls -d ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/subagent-driven-development 2>/dev/null | sort -V | tail -1)}"
t() { local b=0 f; for f in "$@"; do [ -f "$f" ] && b=$((b + $(wc -c < "$f"))); done; echo $((b / 4)); }
row() { printf '  %-52s %6s\n' "$1" "$2"; }

echo "Controller start (loaded once per run)"
row "delivery-pipeline + chunked-delivery" "$(t skills/delivery-pipeline/SKILL.md skills/chunked-delivery/SKILL.md)"
[ -n "$sdd" ] && row "+ superpowers SDD SKILL.md" "$(t "$sdd/SKILL.md")"
echo
echo "Task reviewer, fixed load before the diff (every task)"
[ -n "$sdd" ] && row "SDD task-reviewer prompt" "$(t "$sdd/task-reviewer-prompt.md")"
row "review-routing" "$(t skills/review-routing/SKILL.md)"
for r in skills/*-review; do
  n=$(basename "$r"); inv="$r/INVARIANTS.md"; [ -f "$inv" ] || inv="$r/INVENTORY.md"
  row "$n: CHECKLIST + $(basename "$inv") + template project layer" "$(t "$r/CHECKLIST.md" "$inv" "templates/$n.md")"
done
echo
echo "Single-file review entry point (SKILL.md, not loaded in diff review)"
for r in skills/*-review; do row "$(basename "$r")" "$(t "$r/SKILL.md")"; done
echo
echo "Skill descriptions in every session's system prompt (chars)"
row "all skills" "$(grep -h '^description:' skills/*/SKILL.md | wc -c | tr -d ' ')"
echo
echo "Not counted: inventory.sh output (INVENTORY_LIMIT lines per section), scan.sh output, the diff itself."
