#!/usr/bin/env bash
# Audits a repository against CHECKLIST.md: one PASS / MISS / MANUAL line per
# id, then a MISS: list to pick from. Reads config, never code quality.
#
#   bash audit.sh [root]          default: the git root of the cwd
#
# Ids that live in delivery-pipeline, chunked-delivery, review-routing or a
# *-review rubric pass by inheritance when the project ships no copy of that
# skill: the plugin's own file is then the one in force. When the project
# has a copy, the copy is what is read.
#
#   PLUGIN_ROOT   this plugin's checkout; default: three levels up from here
set -uo pipefail

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
root=$(cd "$root" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
plugin="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd "$here/../../.." && pwd)}}"
cd "$root"

miss=(); manual=()
row() { # id status detail
  printf '  %-3s %-7s %s\n' "$1" "$2" "$3"
  case "$2" in MISS) miss+=("$1");; MANUAL) manual+=("$1");; esac
}
has_dep() { node -e 'const p=require(process.argv[1]+"/package.json"),d={...p.dependencies,...p.devDependencies};process.exit(d[process.argv[2]]?0:1)' "$root" "$1" 2>/dev/null; }
script_has() { node -e 'const s=require(process.argv[1]+"/package.json").scripts||{};process.exit(Object.values(s).some(v=>v.includes(process.argv[2]))?0:1)' "$root" "$1" 2>/dev/null; }

# The file in force for a skill: the project's copy, else the plugin's.
in_force() { # skill-dir-name
  local p=".claude/skills/$1/SKILL.md"
  if [ -f "$p" ]; then echo "$p"; else echo "$plugin/skills/$1/SKILL.md"; fi
}
owner() { case "$1" in "$plugin"/*) echo "plugin";; *) echo "project";; esac; }

pipeline=$(in_force delivery-pipeline)
chunked=$(in_force chunked-delivery)
routing=$(in_force review-routing)

echo "Reuse guardrails — $root"
echo "  delivery-pipeline: $(owner "$pipeline") · chunked-delivery: $(owner "$chunked") · review-routing: $(owner "$routing")"
echo
echo "## A — before the code exists"

if grep -q 'inventory shows none' "$pipeline" && grep -q 'fewer than two callers' "$pipeline" && grep -q 'runtime dependency' "$pipeline"; then
  row A1 PASS "reuse lines in Global Constraints ($(owner "$pipeline"))"
else row A1 MISS "Global Constraints lack the three reuse lines ($(owner "$pipeline") $pipeline)"; fi

if grep -q '## Inventory' "$pipeline"; then row A2 PASS "inventory in implementer dispatch ($(owner "$pipeline"))"
else row A2 MISS "implementer dispatch carries no ## Inventory ($(owner "$pipeline") $pipeline)"; fi

if grep -q '## Reuse' "$pipeline"; then row A3 PASS "## Reuse block in implementer report ($(owner "$pipeline"))"
else row A3 MISS "implementer report format has no ## Reuse block ($(owner "$pipeline") $pipeline)"; fi

layers=$(ls docs/review/*.md 2>/dev/null)
if [ -z "$layers" ]; then row A4 MISS "no docs/review/*.md — no project layer names the shared primitives"
else
  stale=$(grep -lE '<[a-z][a-z -]+>' $layers 2>/dev/null | tr '\n' ' ')
  if [ -n "$stale" ]; then row A4 MISS "template placeholders still in: $stale"
  else row A4 PASS "$(echo "$layers" | wc -l | tr -d ' ') project layer files"; fi
fi

echo
echo "## B — while the code is written"

if has_dep jscpd; then
  cfg=""; [ -f .jscpd.json ] && cfg=".jscpd.json"; [ -z "$cfg" ] && grep -q '"jscpd"' package.json && cfg="package.json#jscpd"
  if [ -z "$cfg" ]; then row B1 MISS "jscpd installed, no .jscpd.json"
  elif script_has jscpd || grep -qs jscpd .github/workflows/*.yml .gitlab-ci.yml 2>/dev/null; then row B1 PASS "jscpd ($cfg) in a script or CI"
  else row B1 MISS "jscpd configured ($cfg) but no script or CI step runs it"; fi
else row B1 MISS "jscpd not installed"; fi

# Code that ships: root, apps, packages, libs (one level of nesting). Not
# e2e harnesses or test-utils — nothing there can reinvent a helper for users.
configs=$(ls eslint.config.* .eslintrc* {apps,packages,libs,libs/*}/*/eslint.config.* {apps,packages,libs,libs/*}/*/.eslintrc* 2>/dev/null | grep -vE '(^|/)[^/]*(-e2e|e2e|test-utils|testing)/' )
if [ -z "$configs" ]; then row B2 MISS "no eslint config"; row B3 MISS "no eslint config"
else
  # A root config can carry the bans for every app. Without that, each app
  # config is judged on its own and the root one is not listed beside them.
  rootc=$(ls eslint.config.* .eslintrc* 2>/dev/null | head -1)
  appc=$(printf '%s\n' "$configs" | grep -v "^$rootc$" | grep -v '^$')
  bare=""; for c in ${appc:-$rootc}; do grep -qE 'no-restricted-(syntax|imports|properties|globals)' "$c" || bare="$bare $c"; done
  if [ -n "$rootc" ] && grep -qE 'no-restricted-(syntax|imports|properties|globals)' "$rootc"; then row B2 PASS "hand-roll bans in $rootc"
  elif [ -z "$bare" ]; then row B2 PASS "hand-roll bans in every app config"
  else row B2 MISS "no no-restricted-* rule in:$bare"; fi
  if grep -qE 'max-lines' $configs; then row B3 PASS "max-lines set in $(grep -lE 'max-lines' $configs | tr '\n' ' ')"
  else row B3 MISS "no max-lines in any eslint config"; fi
fi

if grep -q 'reuse-scan' "$pipeline" && grep -q 'reuse-scan' "$chunked"; then row B4 PASS "reuse-scan in the gate ($(owner "$pipeline") pipeline, $(owner "$chunked") chunked-delivery)"
else row B4 MISS "reuse-scan missing from $(grep -q 'reuse-scan' "$pipeline" || echo "$pipeline ")$(grep -q 'reuse-scan' "$chunked" || echo "$chunked")"; fi

if [ -f .claude/settings.json ] && node -e '
  const h=(require(process.argv[1]).hooks||{}).PostToolUse||[];
  const ok=h.some(e=>(e.hooks||[]).some(x=>/eslint|biome|prettier|tsc|lint/.test(x.command||"")));
  process.exit(ok?0:1)' "$root/.claude/settings.json" 2>/dev/null; then row B5 PASS "PostToolUse lint hook in .claude/settings.json"
else row B5 MISS "no PostToolUse hook that lints the written file"; fi

echo
echo "## C — after the code exists"

# Rubrics for code that can rebuild a helper: components, services, contracts.
# Schema, infra, test and observability rubrics judge other things.
rubrics=$(ls -d .claude/skills/*-review 2>/dev/null | grep -vE '(schema|prisma|infra|test|observab|migration)')
if [ -z "$rubrics" ]; then row C1 PASS "no project code rubrics — plugin rubrics carry the reinvention rule"
else
  lacking=""; for r in $rubrics; do
    grep -qiE 'reinvent|re-implement' "$r"/*.md 2>/dev/null || lacking="$lacking $(basename "$r")"
  done
  if [ -z "$lacking" ]; then row C1 PASS "reinvention rule in $(echo "$rubrics" | wc -l | tr -d ' ') project rubrics"
  else row C1 MISS "no reinvention rule in:$lacking"; fi
fi

if grep -q 'reuse-scan' "$routing"; then row C2 PASS "reuse-scan in review-routing ($(owner "$routing"))"
else row C2 MISS "review-routing never runs reuse-scan ($(owner "$routing") $routing)"; fi

if grep -q 'jscpd' "$pipeline" && has_dep jscpd; then row C3 PASS "jscpd in the whole-tree review"
elif grep -q 'jscpd' "$pipeline"; then row C3 MISS "pipeline names jscpd but B1 fails — install it first"
else row C3 MISS "whole-tree review never sees a duplicate report ($(owner "$pipeline") $pipeline)"; fi

if [ -n "$layers" ] && grep -qi 'caught by hand' $layers 2>/dev/null; then
  row C4 MANUAL "Caught by hand section exists — check its newest line is younger than the last merged branch"
else row C4 MANUAL "no 'Caught by hand' section in docs/review — where do hand-caught findings go?"; fi

echo
[ ${#miss[@]} -eq 0 ] && echo "MISS: nothing" || echo "MISS: ${miss[*]}"
[ ${#manual[@]} -eq 0 ] || echo "MANUAL: ${manual[*]}"
echo "Each MISS id is a section in CHECKLIST.md with the recipe. Implement only the ids the human names."
