#!/usr/bin/env bash
# Drift gate: runs the project's own checks that two copies of one fact agree
# (schema and migrations, API and its client, code and generated code).
#
#   bash drift.sh check [path...]   run each check whose `when` matches a path;
#                                   with no paths, run them all
#   bash drift.sh coverage          declared checks, and known pairs with none
#
# Checks live in docs/review/drift.checks (or DRIFT_FILE), one per line:
#
#   name :: when :: command :: generated
#
#   when       regex of changed paths that trigger the check; empty is always
#   command    run from the repo root; a non-zero exit is drift
#   generated  optional, space-separated paths the command rewrites. The
#              command is then a generator: drift is any change to those
#              paths, and they are put back as they were afterwards.
set -uo pipefail

mode="${1:-}"
shift || true
if [ -z "$mode" ]; then
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$root" || exit 2
checks_file="${DRIFT_FILE:-docs/review/drift.checks}"

# ------------------------------------------------------- the checks file
trim() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# field ROW N — the Nth `::`-separated field of one line of the checks file
field() {
  awk -F'::' -v n="$2" '{ print $n }' <<< "$1" | trim
}

declared_checks() {
  [ -f "$checks_file" ] && grep -vE '^[[:space:]]*(#|$)' "$checks_file"
}

indent() {
  sed "s/^/$1/"
}

# ------------------------------------------------------------------ check
sha1() {
  if command -v shasum > /dev/null 2>&1; then shasum; else sha1sum; fi
}

# One "hash  path" line per file under the given paths.
content_hashes() {
  # shellcheck disable=SC2086
  find $1 -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r file; do
    printf '%s  %s\n' "$(sha1 < "$file" | cut -c1-40)" "$file"
  done
}

run_quietly() {
  sh -c "$1" > "$work/out" 2>&1 < /dev/null
}

show_output() {
  tail -30 "$work/out" | indent '   '
}

# A plain check: the command's exit code says whether there is drift.
run_command_check() {
  if run_quietly "$1"; then
    echo "   ok"
    return 0
  fi
  echo "   DRIFT"
  show_output
  return 1
}

# A generator check: drift is any change the command makes to the generated paths.
# They are put back as they were afterwards.
run_generator_check() {
  local command=$1 generated=$2 status=0
  case " $generated " in
    *" /"*|*..*)
      echo "   generated paths must be inside the repo: $generated" >&2
      return 1
      ;;
  esac

  content_hashes "$generated" > "$work/before"
  # shellcheck disable=SC2086
  tar -cf "$work/keep.tar" $generated 2>/dev/null

  if ! run_quietly "$command"; then
    echo "   FAILED to run"
    show_output
    status=1
  else
    content_hashes "$generated" > "$work/after"
    if cmp -s "$work/before" "$work/after"; then
      echo "   ok"
    else
      echo "   DRIFT — regenerating changes these; run the command and keep the result:"
      diff "$work/before" "$work/after" | sed -nE 's/^[<>] [0-9a-f]+  //p' | sort -u | head -15 | indent '     '
      status=1
    fi
  fi

  # shellcheck disable=SC2086
  rm -rf $generated && tar -xf "$work/keep.tar" 2>/dev/null
  return $status
}

check() {
  if [ ! -f "$checks_file" ]; then
    echo "drift: no $checks_file — no checks declared"
    exit 0
  fi

  local changed=("$@") failed=0 ran=0 row name when command generated
  work=$(mktemp -d)
  while IFS= read -r row; do
    name=$(field "$row" 1)
    when=$(field "$row" 2)
    command=$(field "$row" 3)
    generated=$(field "$row" 4)
    if [ -z "$name" ] || [ -z "$command" ]; then
      echo "drift: bad line, want name :: when :: command — $row" >&2
      failed=1
      continue
    fi
    if [ -n "$when" ] && [ ${#changed[@]} -gt 0 ]; then
      printf '%s\n' "${changed[@]}" | grep -qE -- "$when" || continue
    fi

    ran=$((ran + 1))
    printf '== drift %s: %s\n' "$name" "$command"
    if [ -z "$generated" ]; then
      run_command_check "$command" || failed=1
    else
      run_generator_check "$command" "$generated" || failed=1
    fi
  done < <(declared_checks)
  rm -rf "$work"

  if [ "$failed" -eq 0 ]; then
    echo "drift: clean ($ran check(s) run)"
    exit 0
  fi
  echo "drift: FAILED"
  exit 1
}

# --------------------------------------------------------------- coverage
row() {
  printf '  %-44s %s\n' "$1" "$2"
}

project_has_file() {
  find . -maxdepth "$1" -name "$2" -not -path '*/node_modules/*' 2>/dev/null | grep -q .
}

project_has_locale_dir() {
  find . -maxdepth 6 -type d \( -name locales -o -name i18n -o -name translations \) -not -path '*/node_modules/*' 2>/dev/null | grep -q .
}

coverage() {
  local declared="" check manifests undeclared=()
  if [ -f "$checks_file" ]; then
    declared=$(declared_checks)
    while IFS= read -r check; do
      [ -n "$check" ] && row "$(field "$check" 1)" "$(field "$check" 3)"
    done <<< "$declared"
  else
    row "$checks_file" "none"
  fi

  manifests=$(find . -maxdepth 4 -name package.json -not -path '*/node_modules/*' 2>/dev/null)

  depends_on() {
    # shellcheck disable=SC2086
    [ -n "$manifests" ] && grep -qE "\"($1)\"[[:space:]]*:" $manifests 2>/dev/null
  }

  # expect NAME KEYWORD — a known pair needs a declared check that mentions KEYWORD
  expect() {
    grep -qiE -- "$2" <<< "$declared" && return 0
    row "$1" "absent"
    undeclared+=("$1")
  }

  project_has_file 5 schema.prisma && expect prisma-migrations 'prisma'
  depends_on 'openapi-typescript|orval|swagger-typescript-api|@graphql-codegen/cli|@openapitools/openapi-generator-cli' \
    && expect generated-api-client 'openapi|orval|swagger|codegen'
  depends_on 'expo' && expect expo-native-deps 'expo'
  project_has_locale_dir && expect locale-keys 'i18n|locale|translation'
  project_has_file 4 '.env.example' && expect env-keys '\benv'
  [ "$(wc -l <<< "$manifests" | tr -d ' ')" -gt 1 ] && expect workspace-versions 'syncpack|manypkg'

  echo "UNDECLARED: ${undeclared[*]:-nothing}"
}

case "$mode" in
  check)    check "$@" ;;
  coverage) coverage ;;
  *)
    echo "unknown mode: $mode (check | coverage)" >&2
    exit 2
    ;;
esac
