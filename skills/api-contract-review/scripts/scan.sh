#!/usr/bin/env bash
# Mechanical pre-scan for api-contract-review. Accepts a file under the shared
# contract package or a whole package directory. Heuristic — flags, not a
# verdict. Written for zod; the class-validator notes are in SKILL.md.
#
# Usage: scan.sh <file-or-dir>
# Env:   CLIENT_LIBS  |-separated package dir names that reach a client bundle
#                     (default: schemas|types|utils)
set -uo pipefail

target="${1:-}"
if [ -z "$target" ]; then
  echo "usage: scan.sh <file-or-dir>" >&2
  exit 1
fi
if [ -d "$target" ]; then
  files=$(find "$target" -name '*.ts' ! -name '*.spec.ts' ! -name '*.test.ts' ! -path '*/node_modules/*' | sort)
elif [ -f "$target" ]; then
  files="$target"
else
  echo "not found: $target" >&2
  exit 1
fi
if [ -z "$files" ]; then
  echo "no .ts files under $target" >&2
  exit 1
fi

scanned=()
while IFS= read -r file; do [ -n "$file" ] && scanned+=("$file"); done <<< "$files"

target_dir=$target
[ -d "$target_dir" ] || target_dir=$(dirname "$target")
root=$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null || pwd)
client_packages="${CLIENT_LIBS:-schemas|types|utils}"
found_any=0

relative_to_root() {
  PREFIX="$root/" awk '
    index($0, ENVIRON["PREFIX"]) == 1 { $0 = substr($0, length(ENVIRON["PREFIX"]) + 1) }
    { print }
  '
}

# flag LABEL LINES — prints a finding with the lines that caused it
flag() {
  printf '## %s\n%s\n\n' "$1" "$2"
  found_any=1
}

# report LABEL REGEX — flags every line of the files that matches
report() {
  local matches
  matches=$(grep -nE "$2" "${scanned[@]}" /dev/null | relative_to_root)
  [ -n "$matches" ] && flag "$1" "$matches"
}

# --- dependency direction ----------------------------------------------------
if grep -qE "/($client_packages)(/|$)" <<< "$target"; then
  report "Backend-only import in a package that reaches a client bundle" \
    "from ['\"](node:[^'\"]*|@nestjs/[^'\"]*|@prisma/[^'\"]*|(fs|path|crypto|buffer|express|fastify)(/[^'\"]*)?)['\"]"
fi

zod_entry_points=$(grep -hoE "from ['\"]zod(/v[34])?['\"]" "${scanned[@]}" | tr '"' "'" | sort -u | wc -l | tr -d ' ')
if [ "$zod_entry_points" -gt 1 ]; then
  flag "zod imported from more than one entry point — pick 'zod' or 'zod/v4', not both" \
    "$(grep -nE "from ['\"]zod" "${scanned[@]}" /dev/null | relative_to_root)"
fi
report "Relative import with a .js suffix — correct under nodenext, breaks under bundler; check tsconfig" \
  "from ['\"]\.\.?/[A-Za-z0-9_./-]+\.js['\"]"

# --- the chain ---------------------------------------------------------------
# Prints each hand-written interface or object type that has a schema of the same name.
shapes_mirroring_a_schema() {
  local schema_dir=$1 file name camel_name
  for file in "${scanned[@]}"; do
    grep -E '^export interface [A-Z]|^export type [A-Z][A-Za-z]* *= *\{' "$file" | awk '{print $3}' | while read -r name; do
      camel_name=$(awk '{ print tolower(substr($0, 1, 1)) substr($0, 2) }' <<< "$name")
      if grep -rqE "export const (${name}|${camel_name})Schema" "$schema_dir" 2>/dev/null; then
        printf '%s: %s duplicates a schema of the same name — derive it with z.infer\n' "$file" "$name"
      fi
    done
  done
}

schema_dir=$(find "$root" -maxdepth 4 -type d -name schemas -not -path '*/node_modules/*' 2>/dev/null | head -1)
if [ -n "$schema_dir" ]; then
  mirrored=$(shapes_mirroring_a_schema "$schema_dir")
  [ -n "$mirrored" ] && flag "Hand-written shape that mirrors an existing schema" "$(relative_to_root <<< "$mirrored")"
fi
report "Generator stub — scaffolding, and in a client-consumed package it ships" \
  "^export function [a-z-]+\(\): string"

# --- request vs response schemas --------------------------------------------
# Reads each `export const xSchema = z.object({ … })` to its closing `})` and prints the
# request schemas that are not .strict() and the response schemas that are.
strictness_problems() {
  awk '
    function opens_object(line) { return line ~ /z\.object\(/ || line ~ /\.extend\(/ }

    /^export const [a-zA-Z]+Schema *=/ {
      name = $3
      body = $0 " "
      declared_at = FNR
      inside = opens_object($0)
      object_on_next_line = !inside
      next
    }
    object_on_next_line {
      if (opens_object($0)) inside = 1
      object_on_next_line = 0
    }
    inside { body = body $0 " " }
    inside && /^\}\)/ {
      is_request = (name ~ /^(create|update|list|patch)/ && name !~ /Response/)
      is_response = (name ~ /Response/)
      strict = (body ~ /\.strict\(\)/)
      if (is_request && !strict)
        printf "%s:%d: request schema %s is not .strict() — an unknown key is silently dropped\n", FILENAME, declared_at, name
      if (is_response && strict)
        printf "%s:%d: response schema %s is .strict() — serialization already strips unknown keys\n", FILENAME, declared_at, name
      inside = 0
      name = ""
      body = ""
    }
  ' "${scanned[@]}"
}
strictness=$(strictness_problems)
[ -n "$strictness" ] && flag "Request/response schema strictness" "$(relative_to_root <<< "$strictness")"

# --- money & shared primitives ----------------------------------------------
money_without_int=$(awk '
  /(amount|price|delta|total|unitPrice|fee|cost)[A-Za-z]*: *z\.number\(\)/ && !/\.int\(\)/ {
    printf "%s:%d: %s\n", FILENAME, FNR, $0
  }
' "${scanned[@]}")
[ -n "$money_without_int" ] && flag "Money field without .int() — money is integer minor units" "$(relative_to_root <<< "$money_without_int")"

inline_currency=$(grep -nE '\[A-Z\]\{3\}' "${scanned[@]}" /dev/null | relative_to_root)
[ -n "$inline_currency" ] && flag "Currency regex inline — use one shared currency schema (fine if this IS that schema)" "$inline_currency"

# Prints integer money fields with no upper bound inside create / update / patch schemas.
unbounded_request_integers() {
  awk '
    /^export const [a-zA-Z]+Schema *=/ {
      name = $3
      in_request_schema = (name ~ /^(create|update|patch)/ && name !~ /Response/)
    }
    in_request_schema && /(amount|price|delta|unitPrice|fee|cost)[A-Za-z]*: *z\.number\(\)\.int\(\)/ {
      if ($0 !~ /max|PG_INT_MAX|MAX/) printf "%s:%d: %s\n", FILENAME, FNR, $0
    }
  ' "${scanned[@]}"
}
unbounded=$(unbounded_request_integers)
[ -n "$unbounded" ] && flag "Unbounded integer on a request field — bound it to the column ceiling or it overflows as an unmapped 500" "$(relative_to_root <<< "$unbounded")"

report "z.date() in a schema — responses carry ISO strings (z.string().datetime())" \
  'z\.date\(\)'
report "limit capped in the schema — if the service clamps instead, an old client gets a page rather than a 400 (check project layer)" \
  'limit:.*\.max\('

# --- compatibility-sensitive edits -------------------------------------------
report "Deprecation marker — confirm the field is still sent until the floor build is gone" \
  '@deprecated'

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
