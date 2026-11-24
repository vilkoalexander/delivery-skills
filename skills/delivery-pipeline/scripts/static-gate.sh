#!/usr/bin/env bash
# Static gate: what the toolchain enforces, and whether a change passes it.
# Runs before any reviewer is dispatched, so a diff that fails tsc or lint
# never costs a review seat.
#
#   bash static-gate.sh coverage [root]     once per run — what is enforced
#   bash static-gate.sh check <path>...     per chunk — does the change pass
#   git diff --name-only | bash static-gate.sh check
#   bash static-gate.sh init                once per project — draft docs/review/delivery.json
#
# `coverage` prints a table of checks and their status (error / warn / absent
# / none) and ends with an ABSENT: list for the Global Constraints block.
# `check` runs the commands docs/review/delivery.json names for the workspace
# each changed path is in (see config.mjs) and exits non-zero with each tool's
# output on failure. It detects nothing: without that file it refuses, and a
# step with no command is printed as skipped, never counted as passing.
#
#   RISK_HIGH / RISK_MEDIUM are not read here; see risk.sh.
#   STATIC_SKIP   space-separated steps to skip for this call: test-lock drift secrets reuse escapes erosion, or any step name from the config
#   SECRET_ALLOW  regex over `path:line:text` for added lines secret-scan.sh must not count
#   ESCAPE_ALLOW  the same for escape-scan.sh
#   EROSION_ALLOW  regex over `path:function` for functions erosion-scan.sh must not count
#   DRIFT_FILE   the project's drift checks (default docs/review/drift.checks); see drift.sh
#   TEST_LOCK_ALLOW  regex of existing test paths a plan task names as changing
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
skills="$here/../.."
mode="${1:-}"
shift || true
if [ -z "$mode" ]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

has_script() {
  node -e '
    const scripts = require(process.argv[1] + "/package.json").scripts || {};
    process.exit(scripts[process.argv[2]] ? 0 : 1);
  ' "$root" "$1" 2>/dev/null
}

has_dep() {
  node -e '
    const pkg = require(process.argv[1] + "/package.json");
    const deps = { ...pkg.dependencies, ...pkg.devDependencies };
    process.exit(deps[process.argv[2]] ? 0 : 1);
  ' "$root" "$1" 2>/dev/null
}

lint_script_fails_on_warnings() {
  node -e '
    const scripts = require("./package.json").scripts || {};
    process.exit(/max-warnings[= ]0/.test(scripts.lint || "") ? 0 : 1);
  ' 2>/dev/null
}

skip() {
  [[ " ${STATIC_SKIP:-} " == *" $1 "* ]]
}

first_existing() {
  local file
  for file in "$@"; do
    if [ -e "$file" ]; then
      echo "$file"
      return 0
    fi
  done
  return 1
}

exists_any() {
  first_existing "$@" > /dev/null
}

emit() {
  local event="$skills/chunked-delivery/scripts/event.sh"
  [ -f "$event" ] || return 0
  bash "$event" gate "$@" || true
}

unique_words() {
  tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' '
}

row() {
  printf '  %-44s %s\n' "$1" "$2"
}

# ---------------------------------------------------------------- coverage
absent=()

mark_absent() {
  absent+=("$1")
}

json_true() {
  grep -qE "\"$2\"[[:space:]]*:[[:space:]]*true" <<< "$1"
}

coverage_typescript() {
  echo "## Type checking"
  if [ ! -f tsconfig.json ]; then
    row "tsconfig.json" "none"
    mark_absent "typescript"
    return
  fi

  local config option
  local options="strict noImplicitAny strictNullChecks useUnknownInCatchVariables noUncheckedIndexedAccess exactOptionalPropertyTypes noImplicitReturns noImplicitOverride noFallthroughCasesInSwitch noPropertyAccessFromIndexSignature"
  local implied_by_strict='^(noImplicitAny|strictNullChecks|useUnknownInCatchVariables)$'
  config=$(npx --no-install tsc --showConfig 2>/dev/null || cat tsconfig.json)

  for option in $options; do
    if json_true "$config" "$option"; then
      row "$option" "on"
    elif json_true "$config" strict && [[ $option =~ $implied_by_strict ]]; then
      row "$option" "on (via strict)"
    else
      row "$option" "absent"
      mark_absent "tsc:$option"
    fi
  done

  if grep -q '"angularCompilerOptions"' <<< "$config"; then
    if json_true "$config" strictTemplates; then
      row "angular strictTemplates" "on"
    else
      row "angular strictTemplates" "absent"
      mark_absent "tsc:strictTemplates"
    fi
  fi

  if has_script typecheck; then
    row "script: typecheck" "$(node -e 'console.log(require("./package.json").scripts.typecheck)')"
  else
    row "script: typecheck" "none — falls back to tsc --noEmit"
  fi
}

# Prints error, warn, off, absent, or ? for one rule of a resolved ESLint config on stdin.
rule_level() {
  node -e '
    let text = "";
    process.stdin.on("data", chunk => (text += chunk)).on("end", () => {
      try {
        const rule = JSON.parse(text).rules[process.argv[1]];
        if (!rule) return console.log("absent");
        const level = Array.isArray(rule) ? rule[0] : rule;
        if (level === 2 || level === "error") return console.log("error");
        if (level === 1 || level === "warn") return console.log("warn");
        console.log("off");
      } catch {
        console.log("?");
      }
    });
  ' "$1"
}

# Does this rule say anything about a file of this kind, in this project?
rule_applies() {
  local rule=$1 kind=$2
  local app_code=0 test_code=0
  [[ $kind == tsx || $kind == service ]] && app_code=1
  [[ $kind == spec || $kind == test ]] && test_code=1

  case "$rule" in
    react-native/*)   [ "$kind" = tsx ] && { has_dep react-native || has_dep expo; } ;;
    sonarjs/*)        [ "$app_code" = 1 ] && has_dep eslint-plugin-sonarjs ;;
    react*|jsx-a11y*) [ "$kind" = tsx ] ;;
    @angular*)        [ "$kind" = component ] ;;
    jest/*|vitest/*)  [ "$test_code" = 1 ] ;;
    import/*)         [ "$app_code" = 1 ] && has_dep eslint-plugin-import ;;
    import-x/*)       [ "$app_code" = 1 ] && { has_dep eslint-plugin-import || has_dep eslint-plugin-import-x; } ;;
    *)                [ "$app_code" = 1 ] ;;
  esac
}

coverage_eslint() {
  echo "## ESLint"
  local config_file
  config_file=$(first_existing eslint.config.* .eslintrc*)
  if [ -z "$config_file" ]; then
    row "config" "none"
    mark_absent "eslint"
    return
  fi
  row "config" "$config_file"

  local rules="
    @typescript-eslint/no-floating-promises @typescript-eslint/no-misused-promises
    @typescript-eslint/no-explicit-any @typescript-eslint/no-unsafe-assignment no-console
    import-x/no-cycle import/no-cycle
    complexity max-depth max-params sonarjs/cognitive-complexity
    react-native/no-inline-styles react-native/no-color-literals react-native/no-unused-styles
    react-hooks/rules-of-hooks react-hooks/exhaustive-deps react/jsx-key jsx-a11y/alt-text
    @angular-eslint/prefer-standalone @angular-eslint/template/use-track-by-function
    @angular-eslint/template/click-events-have-key-events"
  local test_plugin=""
  has_dep vitest && test_plugin=vitest
  has_dep jest && test_plugin=jest
  if [ -n "$test_plugin" ]; then
    rules="$rules $test_plugin/expect-expect $test_plugin/no-focused-tests $test_plugin/no-disabled-tests $test_plugin/no-conditional-expect"
  fi

  # One sample file per kind the rubrics care about.
  local kind_and_glob kind sample resolved rule level
  for kind_and_glob in 'tsx:*.tsx' 'service:*.service.ts' 'component:*.component.ts' 'spec:*.spec.ts' 'test:*.test.ts'; do
    kind=${kind_and_glob%%:*}
    sample=$(find . -name "${kind_and_glob#*:}" -not -path '*/node_modules/*' -not -path '*/dist/*' 2>/dev/null | head -1)
    [ -n "$sample" ] || continue

    resolved=$(npx --no-install eslint --print-config "$sample" 2>/dev/null)
    if [ -z "$resolved" ]; then
      row "print-config $kind" "failed"
      continue
    fi

    if grep -qE '"(project|projectService)"[[:space:]]*:[[:space:]]*(true|"|\[)' <<< "$resolved"; then
      row "type-aware ($kind)" "on"
    else
      row "type-aware ($kind)" "absent"
      mark_absent "eslint:type-aware"
    fi

    for rule in $rules; do
      rule_applies "$rule" "$kind" || continue
      level=$(rule_level "$rule" <<< "$resolved")
      row "$rule ($kind)" "$level"
      [ "$level" = error ] || mark_absent "eslint:$rule"
    done
  done
}

coverage_other_gates() {
  echo "## Other gates"

  if exists_any .prettierrc* prettier.config.*; then
    row "prettier" "config present"
  else
    row "prettier" "none"
    mark_absent "prettier"
  fi

  if lint_script_fails_on_warnings; then
    row "lint script --max-warnings=0" "on"
  else
    row "lint script --max-warnings=0" "absent — warn never fails"
    mark_absent "eslint:max-warnings"
  fi

  if find . -name 'schema.prisma' -not -path '*/node_modules/*' | grep -q .; then
    row "prisma validate" "available"
  else
    row "prisma" "no schema"
  fi

  if grep -qsE 'depConstraints|enforce-module-boundaries|eslint-plugin-boundaries' nx.json eslint.config.* .eslintrc* 2>/dev/null; then
    row "module boundaries" "on"
  elif exists_any .dependency-cruiser.*; then
    row "module boundaries" "dependency-cruiser"
  else
    row "module boundaries" "absent"
    mark_absent "module-boundaries"
  fi

  local tool dead_code_tool=0
  for tool in knip depcheck ts-prune; do
    if has_dep "$tool"; then
      row "$tool" "installed"
      dead_code_tool=1
    fi
  done
  if [ "$dead_code_tool" = 0 ]; then
    row "unused exports / deps (knip)" "absent"
    mark_absent "knip"
  fi

  if [ -f .husky/pre-commit ] || [ -f .pre-commit-config.yaml ] || [ -f lefthook.yml ]; then
    row "pre-commit hook" "on"
  else
    row "pre-commit hook" "none"
    mark_absent "pre-commit"
  fi

  if has_dep lint-staged; then
    row "lint-staged" "installed"
  fi

  if exists_any .gitleaks.toml .secretlintrc*; then
    row "secret scan" "on"
  else
    row "secret scan (gitleaks)" "absent"
    mark_absent "gitleaks"
  fi

  if has_dep jscpd; then
    row "duplicate detection (jscpd)" "installed"
  else
    row "duplicate detection (jscpd)" "absent — reuse-guardrails B1"
  fi
  row "reuse guardrails" "bash $skills/reuse-guardrails/scripts/audit.sh"

  if exists_any .github/workflows/*.yml .gitlab-ci.yml; then
    local ci_file
    ci_file=$(grep -lsE 'lint|tsc|typecheck' .github/workflows/*.yml .gitlab-ci.yml 2>/dev/null | head -1)
    [ -z "$ci_file" ] || row "ci runs lint/typecheck" "$ci_file"
  else
    row "ci" "none found"
  fi
}

coverage_drift() {
  echo "## Drift checks"
  local report undeclared
  report=$(bash "$here/drift.sh" coverage)
  grep -v '^UNDECLARED:' <<< "$report"
  for undeclared in $(sed -n 's/^UNDECLARED: //p' <<< "$report"); do
    [ "$undeclared" = nothing ] || mark_absent "drift:$undeclared"
  done
}

# The STATIC-SETUP.md section that holds the recipe for one absent item.
setup_section() {
  case "$1" in
    typescript|tsc:*) echo typescript ;;
    eslint|eslint:type-aware|eslint:@typescript-eslint/*|eslint:no-console|eslint:max-warnings) echo eslint ;;
    eslint:complexity|eslint:max-depth|eslint:max-params|eslint:sonarjs/*|eslint:react-native/*) echo shape ;;
    eslint:react*|eslint:jsx-a11y*)   echo react ;;
    eslint:@angular*)                 echo angular ;;
    eslint:jest/*|eslint:vitest/*)    echo tests ;;
    eslint:import*|module-boundaries) echo boundaries ;;
    prettier)                         echo prettier ;;
    knip)                             echo dead-code ;;
    pre-commit|gitleaks)              echo hooks ;;
    drift:*)                          echo drift ;;
  esac
}

coverage_summary() {
  local absent_list item sections=""
  absent_list=$(printf '%s ' ${absent[@]+"${absent[@]}"} | unique_words)
  echo "ABSENT: ${absent_list:-nothing — everything above is enforced}"
  echo "Rules at error above are never a review finding. Each ABSENT item is either a reviewer's job or a tooling chunk the human can choose to add."
  [ -n "$absent_list" ] || return 0

  echo
  echo "SETUP: the strict recipe for each is in STATIC-SETUP.md next to this script —"
  for item in $absent_list; do
    sections="$sections $(setup_section "$item")"
  done
  echo "  sections: $(echo "$sections" | unique_words)"
  echo "  Propose them as one tooling chunk at plan approval; do not add them unasked."
}

coverage() {
  cd "$root"
  echo "Static coverage — $(basename "$root")"
  echo
  coverage_typescript
  echo
  coverage_eslint
  echo
  coverage_other_gates
  echo
  coverage_drift
  echo
  coverage_summary
}

# ------------------------------------------------------------------- check
steps_run=()
steps_skipped=()
gate_failed=0

# run_step NAME SHOWN command... — SHOWN is what the report prints after the name
run_step() {
  local name=$1 shown=$2 started=$SECONDS ok=true
  shift 2
  printf '== %s: %s\n' "$name" "$shown"
  emit gate_step_start step="$name"
  steps_run+=("$name")

  if "$@" > "$step_log" 2>&1; then
    echo "   ok"
  else
    echo "   FAIL"
    tail -40 "$step_log" | sed 's/^/   /'
    gate_failed=1
    ok=false
  fi
  emit gate_step step="$name" ok:=$ok s:=$((SECONDS - started))
}

skip_step() {
  steps_skipped+=("$1")
  printf -- '-- %s: skipped — %s\n' "$1" "$2"
}

run_in_dir() {
  (cd "$1" && bash -c "$2") < /dev/null
}

# test-lock, drift and secrets: the gate's own steps, before the project's.
check_built_in_steps() {
  local lock="$skills/test-review/scripts/test-lock.sh"
  if skip test-lock; then
    skip_step test-lock STATIC_SKIP
  elif [ -f "$lock" ]; then
    run_step test-lock "bash $lock ${changed[*]}" bash "$lock" "${changed[@]}"
  fi

  if skip drift; then
    skip_step drift STATIC_SKIP
  elif [ -f "${DRIFT_FILE:-docs/review/drift.checks}" ]; then
    run_step drift "bash $here/drift.sh check ${changed[*]}" bash "$here/drift.sh" check "${changed[@]}"
  fi

  if skip secrets; then
    skip_step secrets STATIC_SKIP
  elif [ ${#existing[@]} -gt 0 ]; then
    run_step secrets "bash $here/secret-scan.sh ${existing[*]}" bash "$here/secret-scan.sh" "${existing[@]}"
  fi
}

# The project's own steps, as docs/review/delivery.json names them.
check_project_steps() {
  local kind dir name text label
  while IFS=$'\t' read -r kind dir name text; do
    label=$name
    [ "$dir" = . ] || [ "$dir" = - ] || label="$name:$dir"
    case "$kind" in
      RUN)
        if skip "$name"; then
          skip_step "$label" STATIC_SKIP
        else
          run_step "$label" "$text" run_in_dir "$dir" "$text"
        fi
        ;;
      SKIP)
        skip_step "$label" "$text"
        ;;
    esac
  done < <(node "$here/config.mjs" plan "${changed[@]}")
}

# Reuse flags ride along to the reviewer and the chunk report; they never
# fail the gate (REUSE_STRICT=1 on the scan itself does, when wanted).
check_reuse() {
  local scan="$skills/reuse-guardrails/scripts/reuse-scan.sh"
  skip reuse && return 0
  [ -f "$scan" ] && [ ${#existing[@]} -gt 0 ] || return 0

  printf '== reuse scan\n'
  emit gate_step_start step=reuse
  bash "$scan" "${existing[@]}" | sed 's/^/   /'
  emit gate_step step=reuse ok:=true s:=0
}

# Escape flags ride along the same way: a silenced checker or a deferred fix
# is for a reviewer to judge (ESCAPE_STRICT=1 on the scan itself fails).
check_escapes() {
  skip escapes && return 0
  [ ${#existing[@]} -gt 0 ] || return 0

  printf '== escape scan\n'
  emit gate_step_start step=escapes
  ESCAPE_STRICT= bash "$here/escape-scan.sh" "${existing[@]}" | sed 's/^/   /'
  emit gate_step step=escapes ok:=true s:=0
}

# Erosion flags ride along too: a function that was complex and grew is for a
# reviewer to judge (EROSION_STRICT=1 on the scan itself fails).
check_erosion() {
  skip erosion && return 0
  [ ${#existing[@]} -gt 0 ] || return 0

  printf '== erosion scan\n'
  emit gate_step_start step=erosion
  EROSION_STRICT= bash "$here/erosion-scan.sh" "${existing[@]}" | sed 's/^/   /'
  emit gate_step step=erosion ok:=true s:=0
}

check() {
  cd "$root"
  changed=("$@")
  if [ ${#changed[@]} -eq 0 ]; then
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && changed+=("$line")
    done
  fi
  if [ ${#changed[@]} -eq 0 ]; then
    echo "check: no paths" >&2
    exit 2
  fi
  node "$here/config.mjs" check || exit 2

  existing=()
  local path
  for path in "${changed[@]}"; do
    [ -f "$path" ] && existing+=("$path")
  done

  step_log=$(mktemp)
  emit gate_start paths:=${#changed[@]}
  check_built_in_steps
  check_project_steps
  rm -f "$step_log"
  check_reuse
  check_escapes
  check_erosion

  local summary="ran: ${steps_run[*]:-nothing}"
  [ ${#steps_skipped[@]} -gt 0 ] && summary="$summary; skipped: ${steps_skipped[*]}"
  if [ "$gate_failed" -eq 0 ]; then
    emit gate_end ok:=true
    echo "static gate: clean — $summary"
  else
    emit gate_end ok:=false
    echo "static gate: FAILED — $summary. Send the output above to the implementer; no reviewer yet"
    exit 1
  fi
}

case "$mode" in
  coverage) coverage "$@" ;;
  check)    check "$@" ;;
  init)     cd "$root" && node "$here/config.mjs" init ;;
  *)
    echo "unknown mode: $mode (coverage | check | init)" >&2
    exit 2
    ;;
esac
