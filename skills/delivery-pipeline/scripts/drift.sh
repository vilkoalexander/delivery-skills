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

mode="${1:-}"; shift || true
[ -z "$mode" ] && { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$root" || exit 2
file="${DRIFT_FILE:-docs/review/drift.checks}"

trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }
field() { awk -F'::' -v n="$2" '{ print $n }' <<<"$1" | trim; }
rows() { [ -f "$file" ] && grep -vE '^[[:space:]]*(#|$)' "$file"; }
sum() { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum; fi; }
# shellcheck disable=SC2086
hashes() { find $1 -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do printf '%s  %s\n' "$(sum < "$f" | cut -c1-40)" "$f"; done; }

check() {
  [ -f "$file" ] || { echo "drift: no $file — no checks declared"; exit 0; }
  local paths=("$@") failed=0 ran=0 row name when cmd gen tmp
  tmp=$(mktemp -d)
  while IFS= read -r row; do
    name=$(field "$row" 1); when=$(field "$row" 2); cmd=$(field "$row" 3); gen=$(field "$row" 4)
    [ -n "$name" ] && [ -n "$cmd" ] || { echo "drift: bad line, want name :: when :: command — $row" >&2; failed=1; continue; }
    if [ -n "$when" ] && [ ${#paths[@]} -gt 0 ]; then
      printf '%s\n' "${paths[@]}" | grep -qE -- "$when" || continue
    fi
    ran=$((ran+1))
    printf '== drift %s: %s\n' "$name" "$cmd"
    if [ -z "$gen" ]; then
      if sh -c "$cmd" > "$tmp/out" 2>&1 < /dev/null; then echo "   ok"; else echo "   DRIFT"; tail -30 "$tmp/out" | sed 's/^/   /'; failed=1; fi
      continue
    fi
    case " $gen " in *" /"*|*..*) echo "   generated paths must be inside the repo: $gen" >&2; failed=1; continue ;; esac
    hashes "$gen" > "$tmp/before"
    # shellcheck disable=SC2086
    tar -cf "$tmp/keep.tar" $gen 2>/dev/null
    if ! sh -c "$cmd" > "$tmp/out" 2>&1 < /dev/null; then
      echo "   FAILED to run"; tail -30 "$tmp/out" | sed 's/^/   /'; failed=1
    else
      hashes "$gen" > "$tmp/after"
      if cmp -s "$tmp/before" "$tmp/after"; then echo "   ok"
      else
        echo "   DRIFT — regenerating changes these; run the command and keep the result:"
        diff "$tmp/before" "$tmp/after" | sed -nE 's/^[<>] [0-9a-f]+  //p' | sort -u | head -15 | sed 's/^/     /'
        failed=1
      fi
    fi
    # shellcheck disable=SC2086
    rm -rf $gen && tar -xf "$tmp/keep.tar" 2>/dev/null
  done < <(rows)
  rm -rf "$tmp"
  [ "$failed" -eq 0 ] && { echo "drift: clean ($ran check(s) run)"; exit 0; }
  echo "drift: FAILED"; exit 1
}

coverage() {
  local declared="" pkgs missing=()
  row() { printf '  %-44s %s\n' "$1" "$2"; }
  if [ -f "$file" ]; then
    declared=$(rows)
    while IFS= read -r r; do [ -n "$r" ] && row "$(field "$r" 1)" "$(field "$r" 3)"; done <<<"$declared"
  else
    row "$file" "none"
  fi
  pkgs=$(find . -maxdepth 4 -name package.json -not -path '*/node_modules/*' 2>/dev/null)
  dep() { [ -n "$pkgs" ] && grep -qE "\"($1)\"[[:space:]]*:" $pkgs 2>/dev/null; }
  pair() { # name, keyword that a covering check would contain
    grep -qiE -- "$2" <<<"$declared" && return 0
    row "$1" "absent"; missing+=("$1")
  }
  find . -maxdepth 5 -name schema.prisma -not -path '*/node_modules/*' 2>/dev/null | grep -q . && pair prisma-migrations 'prisma'
  dep 'openapi-typescript|orval|swagger-typescript-api|@graphql-codegen/cli|@openapitools/openapi-generator-cli' && pair generated-api-client 'openapi|orval|swagger|codegen'
  dep 'expo' && pair expo-native-deps 'expo'
  find . -maxdepth 6 -type d \( -name locales -o -name i18n -o -name translations \) -not -path '*/node_modules/*' 2>/dev/null | grep -q . && pair locale-keys 'i18n|locale|translation'
  find . -maxdepth 4 -name '.env.example' -not -path '*/node_modules/*' 2>/dev/null | grep -q . && pair env-keys '\benv'
  [ "$(wc -l <<<"$pkgs" | tr -d ' ')" -gt 1 ] && pair workspace-versions 'syncpack|manypkg'
  echo "UNDECLARED: ${missing[*]:-nothing}"
}

case "$mode" in
  check)    check "$@" ;;
  coverage) coverage ;;
  *) echo "unknown mode: $mode (check | coverage)" >&2; exit 2 ;;
esac
