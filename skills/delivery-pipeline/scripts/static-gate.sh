#!/usr/bin/env bash
# Static gate: what the toolchain enforces, and whether a change passes it.
# Runs before any reviewer is dispatched, so a diff that fails tsc or lint
# never costs a review seat.
#
#   bash static-gate.sh coverage [root]     once per run — what is enforced
#   bash static-gate.sh check <path>...     per chunk — does the change pass
#   git diff --name-only | bash static-gate.sh check
#
# `coverage` prints a table of checks and their status (error / warn / absent
# / none) and ends with an ABSENT: list for the Global Constraints block.
# `check` runs the project's own typecheck, lint, format and test commands
# over the changed paths and exits non-zero with each tool's output on
# failure. Both prefer package.json scripts and fall back to the tools.
#
#   RISK_HIGH / RISK_MEDIUM are not read here; see risk.sh.
#   STATIC_SKIP   space-separated steps to skip: typecheck lint format test prisma
#   STATIC_TEST   override the related-tests command (takes file paths)
set -uo pipefail

mode="${1:-}"; shift || true
[ -z "$mode" ] && { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
has_script() { node -e 'const s=require(process.argv[1]+"/package.json").scripts||{};process.exit(s[process.argv[2]]?0:1)' "$root" "$1" 2>/dev/null; }
has_dep()    { node -e 'const p=require(process.argv[1]+"/package.json"),d={...p.dependencies,...p.devDependencies};process.exit(d[process.argv[2]]?0:1)' "$root" "$1" 2>/dev/null; }
skip()       { [[ " ${STATIC_SKIP:-} " == *" $1 "* ]]; }
any_file()   { local f; for f in "$@"; do [ -e "$f" ] && { echo "$f"; return 0; }; done; return 1; }
uniq_words() { tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' '; }

# ---------------------------------------------------------------- coverage
coverage() {
  cd "$root"
  local absent=()
  row() { printf '  %-44s %s\n' "$1" "$2"; }
  echo "Static coverage — $(basename "$root")"
  echo
  echo "## Type checking"
  if [ -f tsconfig.json ]; then
    local cfg; cfg=$(npx --no-install tsc --showConfig 2>/dev/null || cat tsconfig.json)
    local strict=0; echo "$cfg" | grep -qE '"strict"[[:space:]]*:[[:space:]]*true' && strict=1
    for opt in strict noImplicitAny strictNullChecks useUnknownInCatchVariables noUncheckedIndexedAccess exactOptionalPropertyTypes noImplicitReturns noImplicitOverride noFallthroughCasesInSwitch noPropertyAccessFromIndexSignature; do
      if echo "$cfg" | grep -qE "\"$opt\"[[:space:]]*:[[:space:]]*true"; then row "$opt" "on"
      elif [ "$strict" = 1 ] && [[ "$opt" =~ ^(noImplicitAny|strictNullChecks|useUnknownInCatchVariables)$ ]]; then row "$opt" "on (via strict)"
      else row "$opt" "absent"; absent+=("tsc:$opt"); fi
    done
    if echo "$cfg" | grep -q '"angularCompilerOptions"'; then
      echo "$cfg" | grep -qE '"strictTemplates"[[:space:]]*:[[:space:]]*true' && row "angular strictTemplates" "on" || { row "angular strictTemplates" "absent"; absent+=("tsc:strictTemplates"); }
    fi
    has_script typecheck && row "script: typecheck" "$(node -e 'console.log(require("./package.json").scripts.typecheck)')" || row "script: typecheck" "none — falls back to tsc --noEmit"
  else
    row "tsconfig.json" "none"; absent+=("typescript")
  fi

  echo
  echo "## ESLint"
  local esl; esl=$(any_file eslint.config.* .eslintrc*)
  local testplug=""; has_dep vitest && testplug=vitest; has_dep jest && testplug=jest
  if [ -n "$esl" ]; then
    row "config" "$esl"
    # One sample file per kind the rubrics care about.
    local sample kind
    for kind in 'tsx:*.tsx' 'service:*.service.ts' 'component:*.component.ts' 'spec:*.spec.ts' 'test:*.test.ts'; do
      sample=$(find . -name "${kind#*:}" -not -path '*/node_modules/*' -not -path '*/dist/*' 2>/dev/null | head -1)
      [ -n "$sample" ] || continue
      local pc; pc=$(npx --no-install eslint --print-config "$sample" 2>/dev/null)
      [ -n "$pc" ] || { row "print-config ${kind%%:*}" "failed"; continue; }
      if echo "$pc" | grep -qE '"(project|projectService)"[[:space:]]*:[[:space:]]*(true|"|\[)'; then row "type-aware (${kind%%:*})" "on"; else row "type-aware (${kind%%:*})" "absent"; absent+=("eslint:type-aware"); fi
      for rule in @typescript-eslint/no-floating-promises @typescript-eslint/no-misused-promises @typescript-eslint/no-explicit-any @typescript-eslint/no-unsafe-assignment no-console \
                  import-x/no-cycle import/no-cycle \
                  react-hooks/rules-of-hooks react-hooks/exhaustive-deps react/jsx-key jsx-a11y/alt-text \
                  @angular-eslint/prefer-standalone @angular-eslint/template/use-track-by-function @angular-eslint/template/click-events-have-key-events \
                  ${testplug:+$testplug/expect-expect $testplug/no-focused-tests $testplug/no-disabled-tests $testplug/no-conditional-expect}; do
        local lvl; lvl=$(echo "$pc" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const r=JSON.parse(s).rules[process.argv[1]];if(!r)return console.log("absent");const v=Array.isArray(r)?r[0]:r;console.log(v===2||v==="error"?"error":v===1||v==="warn"?"warn":"off")}catch{console.log("?")}})' "$rule")
        case "$rule" in
          react*|jsx-a11y*) [ "${kind%%:*}" = tsx ] || continue;;
          @angular*) [ "${kind%%:*}" = component ] || continue;;
          jest/*|vitest/*) [[ "${kind%%:*}" = spec || "${kind%%:*}" = test ]] || continue;;
          import/*) [[ "${kind%%:*}" = tsx || "${kind%%:*}" = service ]] || continue; has_dep eslint-plugin-import || continue;;
          import-x/*) [[ "${kind%%:*}" = tsx || "${kind%%:*}" = service ]] || continue; has_dep eslint-plugin-import || { has_dep eslint-plugin-import-x || continue; };;
          *) [[ "${kind%%:*}" = tsx || "${kind%%:*}" = service ]] || continue;;
        esac
        row "$rule (${kind%%:*})" "$lvl"
        [ "$lvl" = error ] || absent+=("eslint:$rule")
      done
    done
  else
    row "config" "none"; absent+=("eslint")
  fi

  echo
  echo "## Other gates"
  any_file .prettierrc* prettier.config.* >/dev/null && row "prettier" "config present" || { row "prettier" "none"; absent+=("prettier"); }
  node -e 'const s=require("./package.json").scripts||{};process.exit(/max-warnings[= ]0/.test(s.lint||"")?0:1)' 2>/dev/null && row "lint script --max-warnings=0" "on" || { row "lint script --max-warnings=0" "absent — warn never fails"; absent+=("eslint:max-warnings"); }
  if find . -name 'schema.prisma' -not -path '*/node_modules/*' | grep -q .; then row "prisma validate" "available"; else row "prisma" "no schema"; fi
  grep -qsE 'depConstraints|enforce-module-boundaries|eslint-plugin-boundaries' nx.json eslint.config.* .eslintrc* 2>/dev/null && row "module boundaries" "on" \
    || { any_file .dependency-cruiser.* >/dev/null && row "module boundaries" "dependency-cruiser" || { row "module boundaries" "absent"; absent+=("module-boundaries"); }; }
  local dead=0; for t in knip depcheck ts-prune; do has_dep "$t" && { row "$t" "installed"; dead=1; }; done
  [ "$dead" = 0 ] && { row "unused exports / deps (knip)" "absent"; absent+=("knip"); }
  if [ -f .husky/pre-commit ] || [ -f .pre-commit-config.yaml ] || [ -f lefthook.yml ]; then row "pre-commit hook" "on"; else row "pre-commit hook" "none"; absent+=("pre-commit"); fi
  has_dep lint-staged && row "lint-staged" "installed"
  any_file .gitleaks.toml .secretlintrc* >/dev/null && row "secret scan" "on" || { row "secret scan (gitleaks)" "absent"; absent+=("gitleaks"); }
  if any_file .github/workflows/*.yml .gitlab-ci.yml >/dev/null; then
    grep -lsE 'lint|tsc|typecheck' .github/workflows/*.yml .gitlab-ci.yml 2>/dev/null | head -1 | xargs -I{} echo "  ci runs lint/typecheck                       {}"
  else row "ci" "none found"; fi

  echo
  local list; list=$(printf '%s ' "${absent[@]+"${absent[@]}"}" | uniq_words)
  echo "ABSENT: ${list:-nothing — everything above is enforced}"
  echo "Rules at error above are never a review finding. Each ABSENT item is either a reviewer's job or a tooling chunk the human can choose to add."
  [ -n "$list" ] || return 0
  echo
  echo "SETUP: the strict recipe for each is in STATIC-SETUP.md next to this script —"
  local sections="" a
  for a in $list; do
    case "$a" in
      typescript|tsc:*)              sections="$sections typescript";;
      eslint|eslint:type-aware|eslint:@typescript-eslint/*|eslint:no-console|eslint:max-warnings) sections="$sections eslint";;
      eslint:react*|eslint:jsx-a11y*) sections="$sections react";;
      eslint:@angular*)               sections="$sections angular";;
      eslint:jest/*|eslint:vitest/*)  sections="$sections tests";;
      eslint:import*|module-boundaries) sections="$sections boundaries";;
      prettier)                       sections="$sections prettier";;
      knip)                           sections="$sections dead-code";;
      pre-commit|gitleaks)            sections="$sections hooks";;
    esac
  done
  echo "  sections: $(echo "$sections" | uniq_words)"
  echo "  Propose them as one tooling chunk at plan approval; do not add them unasked."
}

# ------------------------------------------------------------------- check
check() {
  cd "$root"
  local paths=("$@")
  if [ ${#paths[@]} -eq 0 ]; then while IFS= read -r l; do [ -n "$l" ] && paths+=("$l"); done; fi
  [ ${#paths[@]} -eq 0 ] && { echo "check: no paths" >&2; exit 2; }
  local existing=(); for p in "${paths[@]}"; do [ -f "$p" ] && existing+=("$p"); done
  [ ${#existing[@]} -eq 0 ] && { echo "static gate: none of the paths exist on disk — nothing to check"; exit 0; }
  local ts=() lint=() prisma=() tests=()
  for p in "${existing[@]}"; do
    case "$p" in
      *.ts|*.tsx|*.mts|*.cts) ts+=("$p"); lint+=("$p");;
      *.js|*.jsx|*.mjs|*.cjs|*.vue|*.svelte) lint+=("$p");;
      *.prisma) prisma+=("$p");;
    esac
    [[ "$p" =~ \.(spec|test)\.[cm]?[jt]sx?$ ]] && tests+=("$p")
  done
  local failed=0 log; log=$(mktemp)
  step() { # name, command...
    local name="$1"; shift
    printf '== %s: %s\n' "$name" "$*"
    if "$@" > "$log" 2>&1; then echo "   ok"; else echo "   FAIL"; tail -40 "$log" | sed 's/^/   /'; failed=1; fi
  }

  if ! skip typecheck && [ ${#ts[@]} -gt 0 ] && [ -f tsconfig.json ]; then
    if has_script typecheck; then step typecheck npm run -s typecheck; else step typecheck npx --no-install tsc --noEmit -p tsconfig.json; fi
  fi
  if ! skip lint && [ ${#lint[@]} -gt 0 ] && any_file eslint.config.* .eslintrc* >/dev/null; then
    step lint npx --no-install eslint --max-warnings=0 "${lint[@]}"
  fi
  if ! skip format && [ ${#existing[@]} -gt 0 ] && any_file .prettierrc* prettier.config.* >/dev/null; then
    step format npx --no-install prettier --check "${existing[@]}"
  fi
  if ! skip prisma && [ ${#prisma[@]} -gt 0 ]; then
    step prisma npx --no-install prisma validate
  fi
  if ! skip test && [ ${#existing[@]} -gt 0 ]; then
    if [ -n "${STATIC_TEST:-}" ]; then step test $STATIC_TEST "${existing[@]}"
    elif has_dep vitest; then step test npx --no-install vitest related --run "${existing[@]}"
    elif has_dep jest;  then step test npx --no-install jest --findRelatedTests "${existing[@]}"
    elif [ ${#tests[@]} -gt 0 ]; then step test node --test "${tests[@]}"
    elif has_script test; then step test npm test -s
    fi
  fi
  rm -f "$log"
  [ "$failed" -eq 0 ] && echo "static gate: clean" || { echo "static gate: FAILED — send the output above to the implementer; no reviewer yet"; exit 1; }
}

case "$mode" in
  coverage) coverage "$@";;
  check)    check "$@";;
  *) echo "unknown mode: $mode (coverage | check)" >&2; exit 2;;
esac
