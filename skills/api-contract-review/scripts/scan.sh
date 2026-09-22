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
[ -z "$target" ] && { echo "usage: scan.sh <file-or-dir>" >&2; exit 1; }
if   [ -d "$target" ]; then files=$(find "$target" -name '*.ts' ! -name '*.spec.ts' ! -name '*.test.ts' ! -path '*/node_modules/*' | sort)
elif [ -f "$target" ]; then files="$target"
else echo "not found: $target" >&2; exit 1; fi
[ -z "$files" ] && { echo "no .ts files under $target" >&2; exit 1; }

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CLIENT="${CLIENT_LIBS:-schemas|types|utils}"
hits=0
report() {
  local out
  out=$(grep -nE "$2" $files /dev/null | sed "s|$root/||")
  if [ -n "$out" ]; then printf '## %s\n%s\n\n' "$1" "$out"; hits=1; fi
}
emit() { printf '## %s\n%s\n\n' "$1" "$2"; hits=1; }

# --- dependency direction ----------------------------------------------------
if echo "$target" | grep -qE "/($CLIENT)(/|$)"; then
  report "Backend-only import in a package that reaches a client bundle" \
    "from '(node:|@nestjs|@prisma|fs|path|crypto|buffer|express|fastify)"
fi
zodroots=$(grep -hoE "from 'zod(/v[34])?'" $files | sort -u | wc -l | tr -d ' ')
[ "$zodroots" -gt 1 ] && emit "zod imported from more than one entry point — pick 'zod' or 'zod/v4', not both" "$(grep -nE "from 'zod" $files /dev/null | sed "s|$root/||")"
report "Relative import with a .js suffix — correct under nodenext, breaks under bundler; check tsconfig" \
  "from '\./[A-Za-z0-9_./-]+\.js'"

# --- the chain ---------------------------------------------------------------
schemadir=$(find "$root" -maxdepth 4 -type d -name schemas -not -path '*/node_modules/*' 2>/dev/null | head -1)
if [ -n "$schemadir" ]; then
  twin=$(for f in $files; do
    grep -E '^export interface [A-Z]|^export type [A-Z][A-Za-z]* *= *\{' "$f" | awk '{print $3}' | while read -r n; do
      lc=$(echo "$n" | awk '{ print tolower(substr($0,1,1)) substr($0,2) }')
      if grep -rqE "export const (${n}|${lc})Schema" "$schemadir" 2>/dev/null; then
        printf '%s: %s duplicates a schema of the same name — derive it with z.infer\n' "$f" "$n"
      fi
    done
  done)
  [ -n "$twin" ] && emit "Hand-written shape that mirrors an existing schema" "$(echo "$twin" | sed "s|$root/||")"
fi
report "Generator stub — scaffolding, and in a client-consumed package it ships" \
  "^export function [a-z-]+\(\): string"

# --- request vs response schemas --------------------------------------------
sch=$(awk '
  /^export const [a-zA-Z]+Schema *=/ {
    n = $3; buf = $0 " "; ln = FNR
    open = ($0 ~ /z\.object\(/ || $0 ~ /\.extend\(/)
    pend = !open
    next
  }
  pend { if ($0 ~ /z\.object\(/ || $0 ~ /\.extend\(/) open = 1; pend = 0 }
  open { buf = buf $0 " " }
  open && /^\}\)/ {
    isreq = (n ~ /^(create|update|list|patch)/ && n !~ /Response/)
    isres = (n ~ /Response/)
    strict = (buf ~ /\.strict\(\)/)
    if (isreq && !strict) printf "%s:%d: request schema %s is not .strict() — an unknown key is silently dropped\n", FILENAME, ln, n
    if (isres && strict)  printf "%s:%d: response schema %s is .strict() — serialization already strips unknown keys\n", FILENAME, ln, n
    open = 0; n = ""; buf = ""
  }
' $files)
[ -n "$sch" ] && emit "Request/response schema strictness" "$(echo "$sch" | sed "s|$root/||")"

# --- money & shared primitives ----------------------------------------------
money=$(awk '
  /(amount|price|delta|total|unitPrice|fee|cost)[A-Za-z]*: *z\.number\(\)/ {
    if ($0 !~ /\.int\(\)/) printf "%s:%d: %s\n", FILENAME, FNR, $0
  }
' $files)
[ -n "$money" ] && emit "Money field without .int() — money is integer minor units" "$(echo "$money" | sed "s|$root/||")"
cur=$(grep -nE '\[A-Z\]\{3\}' $files /dev/null | sed "s|$root/||")
[ -n "$cur" ] && emit "Currency regex inline — use one shared currency schema (fine if this IS that schema)" "$cur"
unbounded=$(awk '
  /^export const [a-zA-Z]+Schema *=/ { n = $3; req = (n ~ /^(create|update|patch)/ && n !~ /Response/) }
  req && /(amount|price|delta|unitPrice|fee|cost)[A-Za-z]*: *z\.number\(\)\.int\(\)/ {
    if ($0 !~ /max|PG_INT_MAX|MAX/) printf "%s:%d: %s\n", FILENAME, FNR, $0
  }
' $files)
[ -n "$unbounded" ] && emit "Unbounded integer on a request field — bound it to the column ceiling or it overflows as an unmapped 500" "$(echo "$unbounded" | sed "s|$root/||")"
report "z.date() in a schema — responses carry ISO strings (z.string().datetime())" \
  'z\.date\(\)'
report "limit capped in the schema — if the service clamps instead, an old client gets a page rather than a 400 (check project layer)" \
  'limit:.*\.max\('

# --- compatibility-sensitive edits -------------------------------------------
report "Deprecation marker — confirm the field is still sent until the floor build is gone" \
  '@deprecated'

[ "$hits" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
