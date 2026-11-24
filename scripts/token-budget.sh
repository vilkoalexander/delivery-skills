#!/usr/bin/env bash
# Estimates what each dispatch in this plugin loads, in tokens (bytes / 4).
# Run after editing a skill to see what the edit costs every task.
#
# Usage: bash scripts/token-budget.sh [path-to-superpowers-sdd-skill]
set -uo pipefail
cd "$(dirname "$0")/.."

latest_sdd_skill() {
  ls -d ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/subagent-driven-development 2>/dev/null \
    | sort -V | tail -1
}
sdd="${1:-$(latest_sdd_skill)}"

# tokens FILE... — the files that exist, summed, at four bytes a token
tokens() {
  local bytes=0 file
  for file in "$@"; do
    if [ -f "$file" ]; then
      bytes=$((bytes + $(wc -c < "$file")))
    else
      echo "token-budget: no such file, not counted: $file" >&2
    fi
  done
  echo $((bytes / 4))
}

# row LABEL FILE... — one line of the table
row() {
  local label=$1
  shift
  printf '  %-52s %6s\n' "$label" "$(tokens "$@")"
}

chunked=skills/chunked-delivery
references=$chunked/references
screens=skills/react-screen-authoring
cleanup=skills/comment-cleanup
guardrails=skills/reuse-guardrails

echo "Controller start (loaded once per run)"
row "chunked-delivery: SKILL + writing + plan" $chunked/SKILL.md $references/writing.md $references/plan.md
[ -n "$sdd" ] && row "+ superpowers SDD SKILL.md" "$sdd/SKILL.md"

echo
echo "Task reviewer, fixed load before the diff (every task)"
[ -n "$sdd" ] && row "SDD task-reviewer prompt" "$sdd/task-reviewer-prompt.md"
row "reviewer agent definition" agents/reviewer.md
row "verifier agent definition" agents/verifier.md
row "review-routing" skills/review-routing/SKILL.md
for rubric in skills/*-review; do
  name=$(basename "$rubric")
  inventory="$rubric/INVARIANTS.md"
  [ -f "$inventory" ] || inventory="$rubric/INVENTORY.md"
  row "$name: CHECKLIST + $(basename "$inventory") + template project layer" \
    "$rubric/CHECKLIST.md" "$inventory" "templates/$name.md"
done

echo
echo "Single-file review entry point (SKILL.md, not loaded in diff review)"
for rubric in skills/*-review; do
  row "$(basename "$rubric")" "$rubric/SKILL.md"
done

echo
echo "Implementer, loaded before a new screen is written (only those tasks)"
row "react-screen-authoring: SKILL + CHECKLIST + react-review INVENTORY.md + template project layer" \
  $screens/SKILL.md $screens/CHECKLIST.md skills/react-review/INVENTORY.md templates/react-screen-authoring.md

echo
echo "Loaded only when a comment cleanup is asked for"
row "comment-cleanup: SKILL + RULES" $cleanup/SKILL.md $cleanup/RULES.md

echo
echo "Loaded only when a verify recipe is written or updated"
row "verify-recipe: SKILL + both templates" skills/verify-recipe/SKILL.md templates/verify.md templates/verify-feature.md

echo
echo "Controller, loaded only when its condition is true"
for reference in final static-gate cross-model risk-content long-run models review-map; do
  row "chunked-delivery/references/$reference.md" "$references/$reference.md"
done

echo
echo "Loaded only when a tooling chunk is proposed"
row "delivery-pipeline/STATIC-SETUP.md" skills/delivery-pipeline/STATIC-SETUP.md
row "reuse-guardrails: SKILL + CHECKLIST" $guardrails/SKILL.md $guardrails/CHECKLIST.md

echo
echo "Skill descriptions in every session's system prompt (chars)"
description_chars=$(grep -h '^description:' skills/*/SKILL.md | wc -c | tr -d ' ')
printf '  %-52s %6s\n' "all skills" "$description_chars"

echo
echo "Not counted: inventory.sh output (INVENTORY_LIMIT lines per section), scan.sh output, the diff itself."
