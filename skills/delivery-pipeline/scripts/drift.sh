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
#   when       ERE of changed paths that trigger the check; empty is always
#   command    run from the repo root; a non-zero exit is drift
#   generated  optional, space-separated paths the command rewrites. The
#              command is then a generator: drift is any change to those
#              paths, and they are put back as they were afterwards.
#
# A field separator is `::` with space around it. Exit 0 clean, 1 drift,
# 2 when a line of the file is malformed or a check could not be run.
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

# field ROW N — the Nth field of one line of the checks file. A separator is `::` with
# space around it, so a command can hold `std::move` or `a::b`.
field() {
  N=$2 perl -ne 'chomp; @f = split /(?<!\S)::(?!\S)/, $_, -1; print $f[$ENV{N} - 1] // "", "\n"' <<< "$1" | trim
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
  find "$@" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r file; do
    printf '%s  %s\n' "$(sha1 < "$file" | cut -c1-40)" "$file"
  done
}

run_quietly() {
  bash -c "$1" > "$work/out" 2>&1 < /dev/null
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
  local command=$1 status=0 path
  generated=()
  read -r -a generated <<< "$2"
  for path in "${generated[@]}"; do
    case "$path" in
      /*|*..*|-*)
        echo "   generated paths must be inside the repo: $path" >&2
        return 2
        ;;
    esac
  done

  content_hashes "${generated[@]}" > "$work/before"
  if ! tar -cf "$work/keep.tar" "${generated[@]}" 2> "$work/out"; then
    echo "   could not save ${generated[*]} before the run, so the command was not run"
    show_output
    return 2
  fi
  kept=yes

  if ! run_quietly "$command"; then
    echo "   FAILED to run"
    show_output
    status=1
  else
    content_hashes "${generated[@]}" > "$work/after"
    if cmp -s "$work/before" "$work/after"; then
      echo "   ok"
    else
      echo "   DRIFT — regenerating changes these; run the command and keep the result:"
      diff "$work/before" "$work/after" | sed -nE 's/^[<>] [0-9a-f]+  //p' | sort -u | head -15 | indent '     '
      status=1
    fi
  fi

  put_back
  return $status
}

# Puts the generated paths back as they were before the command ran.
put_back() {
  [ "${kept:-no}" = yes ] || return 0
  kept=no
  rm -rf -- "${generated[@]}" && tar -xf "$work/keep.tar"
}

check() {
  if [ ! -f "$checks_file" ]; then
    echo "drift: no $checks_file — no checks declared"
    exit 0
  fi

  local changed=("$@") failed=0 broken=0 ran=0 row name when command outputs status
  work=$(mktemp -d)
  trap 'put_back; rm -rf "$work"' EXIT
  trap 'exit 130' INT TERM
  while IFS= read -r row; do
    name=$(field "$row" 1)
    when=$(field "$row" 2)
    command=$(field "$row" 3)
    outputs=$(field "$row" 4)
    if [ -z "$name" ] || [ -z "$command" ] || [ -n "$(field "$row" 5)" ]; then
      echo "drift: bad line, want name :: when :: command [:: generated paths] — $row" >&2
      broken=1
      continue
    fi
    if [ -n "$when" ]; then
      printf '' | grep -E -- "$when" > /dev/null 2>&1
      if [ $? -gt 1 ]; then
        echo "drift: the pattern of $name does not compile — $when" >&2
        broken=1
        continue
      fi
      if [ ${#changed[@]} -gt 0 ]; then
        printf '%s\n' "${changed[@]}" | grep -qE -- "$when" || continue
      fi
    fi

    ran=$((ran + 1))
    printf '== drift %s: %s\n' "$name" "$command"
    if [ -z "$outputs" ]; then
      run_command_check "$command"
    else
      run_generator_check "$command" "$outputs"
    fi
    status=$?
    [ "$status" = 1 ] && failed=1
    [ "$status" -gt 1 ] && broken=1
  done < <(declared_checks)

  if [ "$broken" = 1 ]; then
    echo "drift: could not run every check"
    exit 2
  fi
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
