#!/usr/bin/env bash
# Static gate: what the toolchain enforces, and whether a change passes it.
# Runs before any reviewer is dispatched, so a diff that fails tsc or lint
# never costs a review seat.
set -uo pipefail

usage() {
  cat >&2 <<'TEXT'
bash static-gate.sh coverage [root]     once per run — what is enforced
bash static-gate.sh check [path...]     per chunk — does the change pass
bash static-gate.sh init                once per project — draft docs/review/delivery.json

`coverage` prints a table of checks and their status (error / warn / absent
/ none) and ends with an ABSENT: list for the Global Constraints block. In a
monorepo, name the workspace directory as [root].

`check` takes the changed paths from its arguments, else from stdin, else
from git: everything between DELIVERY_BASE (default HEAD) and the working
tree, deleted and untracked files included. It runs its own steps, then the
commands docs/review/delivery.json names for the workspace of each changed
path (see config.mjs). It detects nothing: without that file it refuses.

Every step ends in the summary with one status: ok, FAIL, could not run,
skipped (with the reason) or n/a (with the reason). A step that could not
run fails the gate, a flag scan included. A gate in which no failing step
ran is not clean. Exit 0 clean, 1 failed, 2 the gate itself could not start.

  DELIVERY_BASE     tree-ish the change starts from (default HEAD)
  STATIC_SKIP       space-separated steps to skip for this call: test-lock
                    revert-check drift reuse, or
                    any step name from the config
  DRIFT_FILE        the project's drift checks (default docs/review/drift.checks); see drift.sh
  TEST_LOCK_ALLOW   ERE of existing test paths a plan task names as changing
  TEST_CMD          the test runner for revert-check.sh, when it cannot be detected
RISK_HIGH and RISK_MEDIUM are not read here; see risk.sh.
TEXT
  exit 2
}

here=$(cd "$(dirname "$0")" && pwd)
skills="$here/../.."
mode="${1:-}"
shift || true
[ -n "$mode" ] || usage

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [ "$mode" = coverage ] && [ -n "${1:-}" ]; then
  if ! root=$(cd "$1" 2>/dev/null && pwd); then
    echo "coverage: no directory $1" >&2
    exit 2
  fi
fi

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
    row "script: typecheck" "none"
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
    @typescript-eslint/ban-ts-comment no-warning-comments
    @eslint-community/eslint-comments/require-description @eslint-community/eslint-comments/no-unlimited-disable
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
    eslint:@typescript-eslint/ban-ts-comment|eslint:no-warning-comments|eslint:@eslint-community/*) echo escapes ;;
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
# One line per step: name<TAB>status<TAB>note. Every step lands here once.
results=()
gate_failed=0
fail_steps_run=0

record() {
  results+=("$1"$'\t'"$2"$'\t'"${3:-}")
}

# run_step KIND NAME SHOWN command...
# KIND fail: any exit but 0 fails the gate. KIND flag: its findings are for the
# reviewer and never fail the gate; a scan that could not run (exit 2 or more) does.
run_step() {
  local kind=$1 name=$2 shown=$3 started=$SECONDS status ok=true code
  shift 3
  emit gate_step_start step="$name"

  "$@" > "$step_log" 2>&1
  code=$?
  if [ "$code" = 0 ] && grep -q ': n/a — ' "$step_log"; then
    not_applicable "$name" "$(sed -n 's/^.*: n\/a — //p' "$step_log" | tail -1)"
    emit gate_step step="$name" ok:=true s:=0
    return
  elif [ "$code" = 0 ]; then
    status=ok
  elif [ "$kind" = flag ] && [ "$code" = 1 ]; then
    status=flags
  elif [ "$code" = 2 ] && [ "$kind" != project ]; then
    status="could not run"
  else
    status=FAIL
  fi

  printf '== %s: %s\n' "$name" "$shown"
  case $status in
    ok|flags)
      echo "   $status"
      [ "$kind" = project ] || sed 's/^/   /' "$step_log"
      ;;
    *)
      echo "   $status"
      tail -40 "$step_log" | sed 's/^/   /'
      gate_failed=1
      ok=false
      ;;
  esac
  [ "$kind" = flag ] || fail_steps_run=$((fail_steps_run + 1))
  record "$name" "$status"
  emit gate_step step="$name" ok:=$ok s:=$((SECONDS - started))
}

skip_step() {
  record "$1" skipped "$2"
  printf -- '-- %s: skipped — %s\n' "$1" "$2"
}

not_applicable() {
  record "$1" n/a "$2"
  printf -- '-- %s: n/a — %s\n' "$1" "$2"
}

run_in_dir() {
  (cd "$1" && bash -c "$2") < /dev/null
}

# The gate's own steps, in the order they run. A fail step fails the gate; a
# flag step hands its lines to the reviewer and the chunk report.
fail_steps=(test-lock revert-check drift)
flag_steps=(reuse)

# Sets `step_command` and `step_shown` for one of the gate's own steps, or `step_reason` to why it has nothing to do.
own_step() {
  local drift_file="${DRIFT_FILE:-docs/review/drift.checks}"
  step_command=()
  step_reason=""
  step_shown="$1 on ${#changed[@]} path(s)"
  case $1 in
    test-lock)
      step_command=(bash "$skills/test-review/scripts/test-lock.sh" "${changed[@]}")
      ;;
    revert-check)
      if [ ${#changed_tests[@]} -eq 0 ]; then
        step_reason="no changed test file"
      else
        step_command=(bash "$skills/test-review/scripts/revert-check.sh" "${changed[@]}")
      fi
      ;;
    drift)
      if [ ! -f "$drift_file" ]; then
        step_reason="no $drift_file"
      else
        step_command=(bash "$here/drift.sh" check "${changed[@]}")
      fi
      ;;
    reuse)
      if [ ${#existing[@]} -eq 0 ]; then
        step_reason="every changed path was deleted"
      else
        step_command=(env DEP_VET=off bash "$skills/reuse-guardrails/scripts/reuse-scan.sh" "${existing[@]}")
      fi
      ;;
  esac
}

run_own_steps() {
  local kind=$1 name
  shift
  for name in "$@"; do
    if skip "$name"; then
      skip_step "$name" STATIC_SKIP
      continue
    fi
    own_step "$name"
    if [ -n "$step_reason" ]; then
      not_applicable "$name" "$step_reason"
    else
      run_step "$kind" "$name" "$step_shown" "${step_command[@]}"
    fi
  done
}

# The project's own steps, as docs/review/delivery.json names them.
run_project_steps() {
  local kind dir name text label rows
  if ! rows=$(node "$here/config.mjs" plan "${changed[@]}" 2> "$step_log"); then
    echo "== config: the plan of the project steps"
    echo "   could not run"
    tail -20 "$step_log" | sed 's/^/   /'
    record config "could not run"
    gate_failed=1
    return
  fi

  while IFS=$'\t' read -r kind dir name text; do
    [ -n "$kind" ] || continue
    label=$name
    [ "$dir" = . ] || [ "$dir" = - ] || label="$name:$dir"
    case "$kind" in
      RUN)
        if skip "$name"; then
          skip_step "$label" STATIC_SKIP
        else
          run_step project "$label" "$text" run_in_dir "$dir" "$text"
        fi
        ;;
      SKIP)
        skip_step "$label" "$text"
        ;;
    esac
  done <<< "$rows"
}

# Splits the changed paths: files that exist, files the change deleted, and
# names that are neither. A name that is neither stops the gate: it would be
# a file no step reads.
sort_paths() {
  local path base unknown=()
  base=$(changes_base)
  existing=()
  changed_tests=()
  manifests=()
  for path in "${changed[@]}"; do
    if [ -f "$path" ]; then
      existing+=("$path")
      is_test_path "$path" && changed_tests+=("$path")
      [ "$(basename "$path")" = package.json ] && manifests+=("$path")
    elif ! git cat-file -e "$base:$path" 2> /dev/null; then
      unknown+=("$path")
    fi
  done
  [ ${#unknown[@]} -eq 0 ] && return 0
  echo "check: not a file under $root and not a file the change deleted:" >&2
  printf '  %s\n' "${unknown[@]}" >&2
  echo "Give paths from the root of the repository." >&2
  return 2
}

print_summary() {
  local result name status note verdict=clean
  echo
  if [ "$gate_failed" != 0 ]; then
    verdict=FAILED
  elif [ "$fail_steps_run" = 0 ]; then
    verdict="NOT RUN"
    gate_failed=1
  fi
  echo "static gate: $verdict"
  for result in "${results[@]}"; do
    IFS=$'\t' read -r name status note <<< "$result"
    printf '  %-22s %s%s\n' "$name" "$status" "${note:+ — $note}"
  done
  case $verdict in
    FAILED)    echo "Send the output above to the implementer; no reviewer yet." ;;
    "NOT RUN") echo "No step that can fail ran, so nothing was checked. Run the typecheck and the tests of the project yourself." ;;
  esac
}

check() {
  cd "$root"
  source "$here/lib/changes.sh"
  node "$here/config.mjs" check || exit 2

  DELIVERY_TREE=$(worktree_tree) || exit 2
  export DELIVERY_TREE
  load_paths "" "$@" || exit 2
  changed=(${paths[@]+"${paths[@]}"})
  if [ ${#changed[@]} -eq 0 ]; then
    echo "check: no paths, and nothing changed since $(changes_base)" >&2
    exit 2
  fi
  sort_paths || exit 2

  step_log=$(mktemp)
  trap 'rm -f "$step_log"' EXIT
  emit gate_start paths:=${#changed[@]}
  run_own_steps fail "${fail_steps[@]}"
  run_project_steps
  run_own_steps flag "${flag_steps[@]}"

  print_summary
  if [ "$gate_failed" = 0 ]; then
    emit gate_end ok:=true
  else
    emit gate_end ok:=false
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
