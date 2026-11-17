#!/usr/bin/env bash
# Audits a repository against CHECKLIST.md: one PASS / MISS / MANUAL line per
# id, then a MISS: list to pick from. Reads config, never code quality.
#
#   bash audit.sh [root]          default: the git root of the cwd
#
# Ids that live in chunked-delivery (or a project's delivery-pipeline copy), review-routing or a
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

# ----------------------------------------------------------------- report
missing=()
manual=()

# row ID STATUS DETAIL — STATUS is PASS, MISS or MANUAL
row() {
  printf '  %-3s %-7s %s\n' "$1" "$2" "$3"
  case "$2" in
    MISS)   missing+=("$1") ;;
    MANUAL) manual+=("$1") ;;
  esac
}

# ----------------------------------------------------------- package.json
has_dep() {
  node -e '
    const pkg = require(process.argv[1] + "/package.json");
    const deps = { ...pkg.dependencies, ...pkg.devDependencies };
    process.exit(deps[process.argv[2]] ? 0 : 1);
  ' "$root" "$1" 2>/dev/null
}

a_script_runs() {
  node -e '
    const scripts = require(process.argv[1] + "/package.json").scripts || {};
    process.exit(Object.values(scripts).some(command => command.includes(process.argv[2])) ? 0 : 1);
  ' "$root" "$1" 2>/dev/null
}

package_json_has_key() {
  node -e '
    process.exit(require(process.argv[1] + "/package.json")[process.argv[2]] ? 0 : 1);
  ' "$root" "$1" 2>/dev/null
}

ci_mentions() {
  grep -qs "$1" .github/workflows/*.yml .gitlab-ci.yml 2>/dev/null
}

settings_have_lint_hook() {
  [ -f .claude/settings.json ] || return 1
  node -e '
    const hooks = (require(process.argv[1]).hooks || {}).PostToolUse || [];
    const lints = entry => (entry.hooks || []).some(hook => /eslint|biome|prettier|tsc|lint/.test(hook.command || ""));
    process.exit(hooks.some(lints) ? 0 : 1);
  ' "$root/.claude/settings.json" 2>/dev/null
}

# ------------------------------------------------- which skill is in force
# The file in force for a skill: the project's copy, else the plugin's.
skill_in_force() {
  local project_copy=".claude/skills/$1/SKILL.md"
  if [ -f "$project_copy" ]; then
    echo "$project_copy"
  else
    echo "$plugin/skills/$1/SKILL.md"
  fi
}

owner() {
  case "$1" in
    "$plugin"/*) echo "plugin" ;;
    *)           echo "project" ;;
  esac
}

# A skill is its SKILL.md and the references next to it. Prints a temp file holding both.
skill_text() {
  local combined
  combined=$(mktemp)
  cat "$1" "$(dirname "$1")"/references/*.md > "$combined" 2>/dev/null
  echo "$combined"
}

chunked=$(skill_in_force chunked-delivery)
pipeline=$(skill_in_force delivery-pipeline)
[ -f "$pipeline" ] || pipeline=$chunked
routing=$(skill_in_force review-routing)

pipeline_text=$(skill_text "$pipeline")
chunked_text=$(skill_text "$chunked")
trap 'rm -f "$pipeline_text" "$chunked_text"' EXIT

pipeline_owner=$(owner "$pipeline")
chunked_owner=$(owner "$chunked")
routing_owner=$(owner "$routing")

pipeline_says() {
  grep -q "$1" "$pipeline_text"
}

layers=$(ls docs/review/*.md 2>/dev/null)

# ------------------------------------------------- A — before the code exists
check_a1_constraints() {
  if pipeline_says 'inventory shows none' && pipeline_says 'fewer than two callers' && pipeline_says 'runtime dependency'; then
    row A1 PASS "reuse lines in Global Constraints ($pipeline_owner)"
  else
    row A1 MISS "Global Constraints lack the three reuse lines ($pipeline_owner $pipeline)"
  fi
}

check_a2_inventory() {
  if pipeline_says '## Inventory'; then
    row A2 PASS "inventory in implementer dispatch ($pipeline_owner)"
  else
    row A2 MISS "implementer dispatch carries no ## Inventory ($pipeline_owner $pipeline)"
  fi
}

check_a3_reuse_block() {
  if pipeline_says '## Reuse'; then
    row A3 PASS "## Reuse block in implementer report ($pipeline_owner)"
  else
    row A3 MISS "implementer report format has no ## Reuse block ($pipeline_owner $pipeline)"
  fi
}

check_a4_project_layers() {
  if [ -z "$layers" ]; then
    row A4 MISS "no docs/review/*.md — no project layer names the shared primitives"
    return
  fi
  local with_placeholders
  # shellcheck disable=SC2086
  with_placeholders=$(grep -lE '<[a-z][a-z -]+>' $layers 2>/dev/null | tr '\n' ' ')
  if [ -n "$with_placeholders" ]; then
    row A4 MISS "template placeholders still in: $with_placeholders"
  else
    row A4 PASS "$(echo "$layers" | wc -l | tr -d ' ') project layer files"
  fi
}

# ---------------------------------------------- B — while the code is written
check_b1_jscpd() {
  if ! has_dep jscpd; then
    row B1 MISS "jscpd not installed"
    return
  fi

  local config=""
  if [ -f .jscpd.json ]; then
    config=".jscpd.json"
  elif package_json_has_key jscpd; then
    config="package.json#jscpd"
  fi

  if [ -z "$config" ]; then
    row B1 MISS "jscpd installed, no .jscpd.json"
  elif a_script_runs jscpd || ci_mentions jscpd; then
    row B1 PASS "jscpd ($config) in a script or CI"
  else
    row B1 MISS "jscpd configured ($config) but no script or CI step runs it"
  fi
}

has_restricted_rule() {
  grep -qE 'no-restricted-(syntax|imports|properties|globals)' "$1"
}

check_b2_b3_eslint() {
  # Code that ships: root, apps, packages, libs (one level of nesting). Not
  # e2e harnesses or test-utils — nothing there can reinvent a helper for users.
  local configs
  configs=$(ls eslint.config.* .eslintrc* \
      {apps,packages,libs,libs/*}/*/eslint.config.* {apps,packages,libs,libs/*}/*/.eslintrc* 2>/dev/null \
    | grep -vE '(^|/)[^/]*(-e2e|e2e|test-utils|testing)/')
  if [ -z "$configs" ]; then
    row B2 MISS "no eslint config"
    row B3 MISS "no eslint config"
    return
  fi

  # A root config can carry the bans for every app. Without that, each app
  # config is judged on its own and the root one is not listed beside them.
  local root_config app_configs config without_bans=""
  root_config=$(ls eslint.config.* .eslintrc* 2>/dev/null | head -1)
  app_configs=$(printf '%s\n' "$configs" | grep -v "^$root_config$" | grep -v '^$')
  for config in ${app_configs:-$root_config}; do
    has_restricted_rule "$config" || without_bans="$without_bans $config"
  done

  if [ -n "$root_config" ] && has_restricted_rule "$root_config"; then
    row B2 PASS "hand-roll bans in $root_config"
  elif [ -z "$without_bans" ]; then
    row B2 PASS "hand-roll bans in every app config"
  else
    row B2 MISS "no no-restricted-* rule in:$without_bans"
  fi

  # shellcheck disable=SC2086
  if grep -qE 'max-lines' $configs; then
    row B3 PASS "max-lines set in $(grep -lE 'max-lines' $configs | tr '\n' ' ')"
  else
    row B3 MISS "no max-lines in any eslint config"
  fi
}

check_b4_reuse_scan_in_gate() {
  local in_pipeline=0 in_chunked=0
  grep -q 'reuse-scan' "$pipeline_text" && in_pipeline=1
  grep -q 'reuse-scan' "$chunked_text" && in_chunked=1

  if [ "$in_pipeline" = 1 ] && [ "$in_chunked" = 1 ]; then
    row B4 PASS "reuse-scan in the gate ($pipeline_owner pipeline, $chunked_owner chunked-delivery)"
    return
  fi
  local lacking=""
  [ "$in_pipeline" = 1 ] || lacking="$pipeline "
  [ "$in_chunked" = 1 ] || lacking="$lacking$chunked"
  row B4 MISS "reuse-scan missing from $lacking"
}

check_b5_lint_hook() {
  if settings_have_lint_hook; then
    row B5 PASS "PostToolUse lint hook in .claude/settings.json"
  else
    row B5 MISS "no PostToolUse hook that lints the written file"
  fi
}

# ------------------------------------------------ C — after the code exists
check_c1_reinvention_rule() {
  # Rubrics for code that can rebuild a helper: components, services, contracts.
  # Schema, infra, test and observability rubrics judge other things.
  local rubrics rubric lacking=""
  rubrics=$(ls -d .claude/skills/*-review 2>/dev/null | grep -vE '(schema|prisma|infra|test|observab|migration)')
  if [ -z "$rubrics" ]; then
    row C1 PASS "no project code rubrics — plugin rubrics carry the reinvention rule"
    return
  fi

  for rubric in $rubrics; do
    grep -qiE 'reinvent|re-implement' "$rubric"/*.md 2>/dev/null || lacking="$lacking $(basename "$rubric")"
  done
  if [ -z "$lacking" ]; then
    row C1 PASS "reinvention rule in $(echo "$rubrics" | wc -l | tr -d ' ') project rubrics"
  else
    row C1 MISS "no reinvention rule in:$lacking"
  fi
}

check_c2_reuse_scan_in_routing() {
  if grep -q 'reuse-scan' "$routing"; then
    row C2 PASS "reuse-scan in review-routing ($routing_owner)"
  else
    row C2 MISS "review-routing never runs reuse-scan ($routing_owner $routing)"
  fi
}

check_c3_duplicate_report() {
  if ! pipeline_says 'jscpd'; then
    row C3 MISS "whole-tree review never sees a duplicate report ($pipeline_owner $pipeline)"
  elif has_dep jscpd; then
    row C3 PASS "jscpd in the whole-tree review"
  else
    row C3 MISS "pipeline names jscpd but B1 fails — install it first"
  fi
}

check_c4_caught_by_hand() {
  # shellcheck disable=SC2086
  if [ -n "$layers" ] && grep -qi 'caught by hand' $layers 2>/dev/null; then
    row C4 MANUAL "Caught by hand section exists — check its newest line is younger than the last merged branch"
  else
    row C4 MANUAL "no 'Caught by hand' section in docs/review — where do hand-caught findings go?"
  fi
}

# ------------------------------------------------------------------- run
echo "Reuse guardrails — $root"
echo "  delivery-pipeline: $pipeline_owner · chunked-delivery: $chunked_owner · review-routing: $routing_owner"
echo
echo "## A — before the code exists"
check_a1_constraints
check_a2_inventory
check_a3_reuse_block
check_a4_project_layers

echo
echo "## B — while the code is written"
check_b1_jscpd
check_b2_b3_eslint
check_b4_reuse_scan_in_gate
check_b5_lint_hook

echo
echo "## C — after the code exists"
check_c1_reinvention_rule
check_c2_reuse_scan_in_routing
check_c3_duplicate_report
check_c4_caught_by_hand

echo
if [ ${#missing[@]} -eq 0 ]; then
  echo "MISS: nothing"
else
  echo "MISS: ${missing[*]}"
fi
[ ${#manual[@]} -eq 0 ] || echo "MANUAL: ${manual[*]}"
echo "Each MISS id is a section in CHECKLIST.md with the recipe. Implement only the ids the human names."
