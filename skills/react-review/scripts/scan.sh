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
[ -z "$file" ] && { echo "usage: scan.sh <component.tsx>" >&2; exit 1; }
[ -f "$file" ] || { echo "not found: $file" >&2; exit 1; }

hits=0
report() {
  # $1 = label, $2 = extended-regex
  local out
  out=$(grep -nE "$2" "$file")
  if [ -n "$out" ]; then
    printf '## %s\n%s\n\n' "$1" "$out"
    hits=1
  fi
}

# --- styling -----------------------------------------------------------------
report "Raw hex colors — use a token / theme value" \
  '#[0-9a-fA-F]{3,8}\b'
report "Arbitrary utility values — use the project's scale" \
  'className=.*-\['
if grep -qE 'className=' "$file" && grep -qE 'style=\{\{|StyleSheet\.create' "$file"; then
  printf '## Mixed styling systems — className and style objects in one file\n\n'
  hits=1
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
  '[A-Za-z0-9_\)\]]![.\[]'

# --- hygiene -----------------------------------------------------------------
report "console.* left in" \
  'console\.(log|warn|debug|info)'
report "Deep relative import — use the project's path alias" \
  "from '\.\./\.\./"
report "TODO/FIXME — confirm intentional (a project may mandate some TODO shapes)" \
  '(TODO|FIXME|XXX)'

# --- cross-cutting heuristics ------------------------------------------------
if grep -q 'ScrollView' "$file" && grep -qE '\.map\(' "$file"; then
  printf '## .map() inside a ScrollView — virtualize if the list is unbounded\n\n'
  hits=1
fi
if grep -qE '<(Pressable|TouchableOpacity|TouchableHighlight)' "$file" \
   && ! grep -q 'accessibilityRole' "$file"; then
  printf '## Interactive element with no accessibilityRole anywhere in the file\n\n'
  hits=1
fi
if grep -qE "Platform\.OS *===? *'(ios|android)'" "$file"; then
  printf '## Platform.OS branch — confirm the other platform has a path too\n\n'
  hits=1
fi

[ "$hits" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
