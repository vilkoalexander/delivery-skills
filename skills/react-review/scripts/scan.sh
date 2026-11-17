#!/usr/bin/env bash
# Mechanical pre-scan for react-review. Catches the deterministic smells so the
# review spends judgement on the rest. Heuristic — flags, not a verdict.
#
# Every pattern here targets what a default ESLint setup often lacks: no
# react-hooks plugin, no jsx-key, no no-console, no a11y plugin. Check the
# project's real lint config (SKILL.md, "Tooling coverage") before reporting.
#
# Usage: scan.sh <path/to/Component.tsx>
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <component.tsx>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

found_any=0

# flag LABEL [LINES] — prints a finding, with the lines that caused it when there are any
flag() {
  printf '## %s\n' "$1"
  [ -n "${2:-}" ] && printf '%s\n' "$2"
  printf '\n'
  found_any=1
}

# report LABEL REGEX — flags every line of the file that matches
report() {
  local matches
  matches=$(grep -nE "$2" "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

has() {
  grep -qE "$1" "$file"
}

# --- styling -----------------------------------------------------------------
report "Raw hex colors — use a token / theme value" \
  '#[0-9a-fA-F]{3,8}\b'
report "Arbitrary utility values — use the project's scale" \
  'className=.*-\['
if has 'className=' && has 'style=\{\{|StyleSheet\.create'; then
  flag "Mixed styling systems — className and style objects in one file"
fi

# --- React 19 / hooks ---------------------------------------------------------
report "forwardRef — obsolete on React 19, take ref as a normal prop (skip on React 18)" \
  'forwardRef'
report "Array index as key — breaks on reorder/insert" \
  'key=\{(i|idx|index)\}'
report "useEffect — check it against the anti-pattern table in CHECKLIST §2" \
  'useEffect\('
report "Hook after an early return or inside a condition — verify rules-of-hooks by hand" \
  '^[[:space:]]*(if|for|while)[[:space:]]*\(.*\buse[A-Z]'

# --- typescript --------------------------------------------------------------
report "any / as any — type it or use unknown + guard" \
  ':[[:space:]]*any\b|as any\b'
report "Non-null assertion — handle the null instead" \
  '[]A-Za-z0-9_)]!(\.|\[)'

# --- hygiene -----------------------------------------------------------------
report "console.* left in" \
  'console\.(log|warn|debug|info)'
report "Deep relative import — use the project's path alias" \
  "from '\.\./\.\./"
report "TODO/FIXME — confirm intentional (a project may mandate some TODO shapes)" \
  '(TODO|FIXME|XXX)'

# --- cross-cutting heuristics ------------------------------------------------
if has 'ScrollView' && has '\.map\('; then
  flag ".map() inside a ScrollView — virtualize if the list is unbounded"
fi
if has '<(Pressable|TouchableOpacity|TouchableHighlight)' && ! has 'accessibilityRole'; then
  flag "Interactive element with no accessibilityRole anywhere in the file"
fi
if has "Platform\.OS *===? *'(ios|android)'"; then
  flag "Platform.OS branch — confirm the other platform has a path too"
fi

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
