#!/usr/bin/env bash
# Diff-time reuse scan. Flags what a reviewer should question before reading
# the code: a new file in a shared layer, a new export whose name already
# exists elsewhere, a new export named like a textbook helper, a dependency
# added, a hand-roll pattern in the added lines, and duplicate blocks when
# jscpd is installed. Flags, not a verdict: every one is either a finding or
# a line in the implementer's ## Reuse block.
#
#   bash reuse-scan.sh [path…]                  default: every changed path
#   git diff --name-only | bash reuse-scan.sh
#
#   REUSE_DIFF_RANGE   base..head to scan instead of the working tree vs HEAD
#   REUSE_SHARED       ERE for shared-layer directories
#                      (default: utils|lib|helpers|hooks|common|shared|components/ui)
#   REUSE_STRICT=1     exit 1 when anything was flagged
set -uo pipefail

shared="${REUSE_SHARED:-(^|/)(utils|lib|helpers|hooks|common|shared|components/ui)(/|$)}"
range="${REUSE_DIFF_RANGE:-}"
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "reuse-scan: not a git repository" >&2; exit 2; }
cd "$root"

paths=("$@")
# A harness can hand a pipe that never closes; wait one second for the first line, then fall back to git.
if [ ${#paths[@]} -eq 0 ] && [ ! -t 0 ] && IFS= read -r -t 1 l; then
  [ -n "$l" ] && paths+=("$l")
  while IFS= read -r -t 1 l; do [ -n "$l" ] && paths+=("$l"); done
fi
if [ ${#paths[@]} -eq 0 ]; then
  if [ -n "$range" ]; then while IFS= read -r l; do paths+=("$l"); done < <(git diff --name-only "$range")
  else while IFS= read -r l; do paths+=("$l"); done < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u); fi
fi
[ ${#paths[@]} -eq 0 ] && { echo "reuse-scan: nothing changed"; echo "REUSE: 0 flags"; exit 0; }

src=(); for p in "${paths[@]}"; do case "$p" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) [[ "$p" =~ \.(spec|test)\. ]] || src+=("$p");; esac; done

# Added lines of the diff, as "path:line:text".
added() {
  if [ -n "$range" ]; then git diff -U0 "$range" -- "$@"
  else git diff -U0 HEAD -- "$@"; for f in "$@"; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || { printf '+++ b/%s\n' "$f"; sed 's/^/+/' "$f"; }; done; fi |
  awk '/^\+\+\+ b\//{f=substr($0,7);n=0;next} /^@@/{split($3,a,/[,+]/);n=a[2]-1;next} /^\+/{n++;print f":"n":"substr($0,2);next} /^-/{next} {n++}'
}

total=0
section() { # title, lines
  [ -n "$2" ] || return 0
  local n; n=$(printf '%s\n' "$2" | wc -l | tr -d ' ')
  total=$((total + n))
  printf '## %s (%s)\n%s\n\n' "$1" "$n" "$2"
}

# 1. New files inside a shared layer.
new_shared=""
for p in "${src[@]+"${src[@]}"}"; do
  if [ -n "$range" ]; then git diff --diff-filter=A --name-only "$range" -- "$p" | grep -q . || continue
  else git ls-files --error-unmatch "$p" >/dev/null 2>&1 && git diff --diff-filter=A --name-only HEAD -- "$p" | grep -q . || [ -z "$(git ls-files -- "$p")" ] || continue; fi
  echo "$p" | grep -qE "$shared" && new_shared="$new_shared$p — new file in a shared layer; the ## Reuse block names what was searched"$'\n'
done
section "New shared files" "${new_shared%$'\n'}"

# 2. New exports: already exported elsewhere, or named like a textbook helper.
[ ${#src[@]} -gt 0 ] && adds=$(added "${src[@]}") || adds=""
exports=$(printf '%s\n' "$adds" | grep -oE '^[^:]+:[0-9]+:[[:space:]]*export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*' | sed -E 's/:[[:space:]]*export.*[[:space:]]([A-Za-z_$][A-Za-z0-9_$]*)$/ \1/')
textbook='^(debounce|throttle|sleep|delay|wait|retry|clamp|chunk|groupBy|group_by|uniq|unique|uniqBy|flatten|pick|omit|isEmpty|isBlank|capitalize|titleCase|slugify|truncate|deepClone|cloneDeep|deepEqual|isEqual|merge|deepMerge|formatDate|parseDate|toISO|formatMoney|formatCurrency|formatPrice|toCents|fromCents|noop|identity|range|sum|sumBy|sortBy|keyBy|memoize|once|pipe|compose|tryCatch|safeJsonParse|parseJson|assertNever|isDefined|notNull|nonNull|cn|classNames|clsx)$'
dupes=""; hand=""
while read -r loc name; do
  [ -n "$name" ] || continue
  file=${loc%%:*}
  # Same name exported from any other tracked file, case-insensitive.
  hits=$(git grep -ilE "export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+$name([^A-Za-z0-9_$]|$)" -- ':!*.spec.*' ':!*.test.*' ':!**/__tests__/**' 2>/dev/null | grep -vx "$file" | head -3 | tr '\n' ' ')
  [ -n "$hits" ] && dupes="$dupes$loc $name — already exported from $hits"$'\n'
  echo "$name" | grep -qE "$textbook" && hand="$hand$loc $name — a textbook helper; a library or the shared layer usually has it"$'\n'
done <<< "$exports"
section "New exports that already exist" "${dupes%$'\n'}"
section "New exports named like a textbook helper" "${hand%$'\n'}"

# 3. Dependencies added to any package.json in the diff.
deps=""
for p in "${paths[@]}"; do
  [[ "$(basename "$p")" = package.json ]] || continue
  # Keys present now and absent before, parsed, so formatting never matters.
  if [ -n "$range" ]; then before=$(git show "${range%%..*}:$p" 2>/dev/null); after=$(git show "${range##*..}:$p" 2>/dev/null)
  else before=$(git show "HEAD:$p" 2>/dev/null); after=$(cat "$p" 2>/dev/null); fi
  found=$(BEFORE="$before" AFTER="$after" node -e '
    const keys = s => { try { const p = JSON.parse(s || "{}"); return new Set(["dependencies","devDependencies","peerDependencies","optionalDependencies"].flatMap(k => Object.keys(p[k] || {}))); } catch { return new Set(); } };
    const b = keys(process.env.BEFORE), a = keys(process.env.AFTER);
    console.log([...a].filter(k => !b.has(k)).sort().join("\n"));' 2>/dev/null | grep -v '^$')
  [ -n "$found" ] && deps="$deps$(printf '%s\n' "$found" | sed "s|^|$p: |; s|$| — new dependency; the plan task that named it goes in the ## Reuse block|")"$'\n'
done
section "Dependencies added" "${deps%$'\n'}"

# 4. Hand-roll patterns in added lines (not exports: the inline kind).
pat=""
flag() { # label, ERE over the added text. ENVIRON, not -v: -v unescapes backslashes.
  local out; out=$(printf '%s\n' "$adds" | RE="$2" LABEL="$1" awk '{t=$0; sub(/^[^:]*:[0-9]+:/,"",t); if (t ~ ENVIRON["RE"]) print $0" — "ENVIRON["LABEL"]}' | cut -c1-200)
  [ -n "$out" ] && pat="$pat$out"$'\n'
}
flag "sleep via setTimeout; a shared delay helper or the test clock usually exists" 'new Promise\([^)]*=>[[:space:]]*setTimeout'
flag "deep clone via JSON; structuredClone or the shared helper" 'JSON\.parse\(JSON\.stringify'
flag "money formatted with toFixed(2); the money helper" '\.toFixed\(2\)'
flag "date arithmetic on getTime(); the date helper" 'getTime\(\)[[:space:]]*[-+]|[-+][[:space:]]*[A-Za-z_.]*getTime\(\)'
flag "uniq via Set spread; the collections helper" '\[\.\.\.new Set\('
flag "isEmpty via Object.keys().length; the collections helper" 'Object\.keys\([^)]*\)\.length[[:space:]]*===?[[:space:]]*0'
flag "debounce by hand; the debounce hook or helper" 'clearTimeout\([^)]*\);?[[:space:]]*[A-Za-z_.]*[[:space:]]*=[[:space:]]*setTimeout'
flag "fetch called directly; the api client" '(^|[^A-Za-z.])fetch\([`"'"'"']'
section "Hand-roll patterns in added lines" "${pat%$'\n'}"

# 5. Duplicate blocks, when the project has jscpd.
if [ ${#src[@]} -gt 0 ] && node -e 'const p=require("./package.json"),d={...p.dependencies,...p.devDependencies};process.exit(d.jscpd?0:1)' 2>/dev/null; then
  out=$(npx --no-install jscpd --silent --reporters console --format typescript,tsx,javascript,jsx "${src[@]}" 2>/dev/null | grep -E 'Clone found|^ *- ' | head -40)
  section "Duplicate blocks (jscpd)" "$out"
fi

echo "REUSE: $total flags"
[ "$total" -gt 0 ] && [ "${REUSE_STRICT:-0}" = 1 ] && exit 1
exit 0
