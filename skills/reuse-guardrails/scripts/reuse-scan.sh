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
#   REUSE_SHARED       ERE for shared-layer directories (default: `shared` in
#                      docs/review/delivery.json, else utils|lib|helpers|hooks|common|shared|components/ui)
#   REUSE_STRICT=1     exit 1 when anything was flagged
#   DEP_VET=off        skip the registry and advisory lookup for changed dependencies
# Exits 2 when it could not scan (bad pattern, bad range, invalid config).
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
pipeline="$here/../../delivery-pipeline/scripts"

if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "reuse-scan: not a git repository" >&2
  exit 2
fi
cd "$root"
source "$pipeline/lib/changes.sh"

shared="${REUSE_SHARED:-}"
[ -n "$shared" ] || shared=$(config_get shared) || exit 2
shared="${shared:-(^|/)(utils|lib|helpers|hooks|common|shared|components/ui)(/|$)}"
valid_ere "REUSE_SHARED (shared)" "$shared" || exit 2
range="${REUSE_DIFF_RANGE:-}"
before_ref=$(changes_base)
[ -n "$range" ] && before_ref=${range%%..*}

load_paths "$range" "$@" || exit 2
if [ ${#paths[@]} -eq 0 ]; then
  echo "reuse-scan: nothing changed"
  echo "REUSE: 0 flags"
  exit 0
fi

sources=()
manifests=()
for path in "${paths[@]}"; do
  case "$path" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
      is_test_path "$path" || sources+=("$path")
      ;;
  esac
  [ "$(basename "$path")" = package.json ] && manifests+=("$path")
done

added=""
if [ ${#sources[@]} -gt 0 ]; then
  added=$(added_lines "$range" "${sources[@]}") || exit 2
fi

# ---------------------------------------------------------------- sections
total=0

# section TITLE LINES — prints the lines under a counted heading; nothing when there are none
section() {
  local title=$1 lines=${2%$'\n'} count
  [ -n "$lines" ] || return 0
  count=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
  total=$((total + count))
  printf '## %s (%s)\n%s\n\n' "$title" "$count" "$lines"
}

is_new_file() {
  ! git cat-file -e "$before_ref:$1" 2> /dev/null
}

new_shared_files() {
  local path found=""
  for path in ${sources[@]+"${sources[@]}"}; do
    is_new_file "$path" || continue
    grep -qE "$shared" <<< "$path" || continue
    found+="$path — new file in a shared layer; the ## Reuse block names what was searched"$'\n'
  done
  section "New shared files" "$found"
}

# New exports: already exported elsewhere, or named like a textbook helper.
new_exports() {
  local identifier='[A-Za-z_$][A-Za-z0-9_$]*'
  local export_keywords='export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+'
  local textbook='^(debounce|throttle|sleep|delay|wait|retry|clamp|chunk|groupBy|group_by|uniq|unique|uniqBy|flatten|pick|omit|isEmpty|isBlank|capitalize|titleCase|slugify|truncate|deepClone|cloneDeep|deepEqual|isEqual|merge|deepMerge|formatDate|parseDate|toISO|formatMoney|formatCurrency|formatPrice|toCents|fromCents|noop|identity|range|sum|sumBy|sortBy|keyBy|memoize|once|pipe|compose|tryCatch|safeJsonParse|parseJson|assertNever|isDefined|notNull|nonNull|cn|classNames|clsx)$'

  # One "path:line name" per exported declaration in the added lines.
  local exported
  exported=$(printf '%s\n' "$added" \
    | grep -oE "^[^:]+:[0-9]+:[[:space:]]*$export_keywords$identifier" \
    | sed -E "s/:[[:space:]]*export.*[[:space:]]($identifier)\$/ \\1/")

  local location name file elsewhere duplicates="" textbook_named=""
  while read -r location name; do
    [ -n "$name" ] || continue
    file=${location%%:*}

    # Same name exported from any other tracked file, case-insensitive.
    elsewhere=$(git grep -ilE "$export_keywords$name([^A-Za-z0-9_$]|$)" -- ':!*.spec.*' ':!*.test.*' ':!**/__tests__/**' 2>/dev/null \
      | grep -vx "$file" | head -3 | tr '\n' ' ')
    [ -n "$elsewhere" ] && duplicates+="$location $name — already exported from $elsewhere"$'\n'

    if grep -qE "$textbook" <<< "$name"; then
      textbook_named+="$location $name — a textbook helper; a library or the shared layer usually has it"$'\n'
    fi
  done <<< "$exported"

  section "New exports that already exist" "$duplicates"
  section "New exports named like a textbook helper" "$textbook_named"
}

# Dependency names present after the change and absent before. Parsed, so formatting never matters.
added_dependency_names() {
  BEFORE=$1 AFTER=$2 node -e '
    const names = text => {
      try {
        const pkg = JSON.parse(text || "{}");
        const groups = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];
        return new Set(groups.flatMap(group => Object.keys(pkg[group] || {})));
      } catch {
        return new Set();
      }
    };
    const before = names(process.env.BEFORE);
    const after = names(process.env.AFTER);
    console.log([...after].filter(name => !before.has(name)).sort().join("\n"));
  ' 2>/dev/null | grep -v '^$'
}

added_dependencies() {
  local manifest before after names found=""
  for manifest in ${manifests[@]+"${manifests[@]}"}; do
    if [ -n "$range" ]; then
      before=$(git show "$before_ref:$manifest" 2>/dev/null)
      after=$(git show "${range##*..}:$manifest" 2>/dev/null)
    else
      before=$(git show "$before_ref:$manifest" 2>/dev/null)
      after=$(cat "$manifest" 2>/dev/null)
    fi
    names=$(added_dependency_names "$before" "$after")
    [ -n "$names" ] || continue
    found+=$(printf '%s\n' "$names" \
      | sed "s|^|$manifest: |; s|$| — new dependency; the plan task that named it goes in the ## Reuse block|")$'\n'
  done
  section "Dependencies added" "$found"
}

# What the registry and the advisory database say about added or re-versioned dependencies.
dependency_vetting() {
  local vet="$pipeline/dep-vet.sh"
  [ ${#manifests[@]} -gt 0 ] && [ -f "$vet" ] || return 0
  section "Dependency vetting" "$(DEP_VET_RANGE="$range" bash "$vet" --diff "${manifests[@]}" 2>/dev/null)"
}

# Hand-roll patterns in added lines (not exports: the inline kind).
hand_roll_patterns() {
  local found=""

  # flag LABEL REGEX — the regex is matched against the added text only. ENVIRON, not -v: -v unescapes backslashes.
  flag() {
    local matched
    matched=$(printf '%s\n' "$added" | LABEL=$1 REGEX=$2 awk '
      {
        text = $0
        sub(/^[^:]*:[0-9]+:/, "", text)
        if (text ~ ENVIRON["REGEX"]) print $0 " — " ENVIRON["LABEL"]
      }' | cut -c1-200)
    [ -n "$matched" ] && found+="$matched"$'\n'
  }

  flag "sleep via setTimeout; a shared delay helper or the test clock usually exists" 'new Promise\([^)]*=>[[:space:]]*setTimeout'
  flag "deep clone via JSON; structuredClone or the shared helper"                    'JSON\.parse\(JSON\.stringify'
  flag "money formatted with toFixed(2); the money helper"                            '\.toFixed\(2\)'
  flag "date arithmetic on getTime(); the date helper"                                'getTime\(\)[[:space:]]*[-+]|[-+][[:space:]]*[A-Za-z_.]*getTime\(\)'
  flag "uniq via Set spread; the collections helper"                                  '\[\.\.\.new Set\('
  flag "isEmpty via Object.keys().length; the collections helper"                     'Object\.keys\([^)]*\)\.length[[:space:]]*===?[[:space:]]*0'
  flag "debounce by hand; the debounce hook or helper"                                'clearTimeout\([^)]*\);?[[:space:]]*[A-Za-z_.]*[[:space:]]*=[[:space:]]*setTimeout'
  flag "fetch called directly; the api client"                                        '(^|[^A-Za-z.])fetch\([`"'"'"']'

  section "Hand-roll patterns in added lines" "$found"
}

project_has_jscpd() {
  node -e '
    const pkg = require("./package.json");
    const deps = { ...pkg.dependencies, ...pkg.devDependencies };
    process.exit(deps.jscpd ? 0 : 1);
  ' 2>/dev/null
}

duplicate_blocks() {
  [ ${#sources[@]} -gt 0 ] && project_has_jscpd || return 0
  local clones
  clones=$(npx --no-install jscpd --silent --reporters console --format typescript,tsx,javascript,jsx "${sources[@]}" 2>/dev/null \
    | grep -E 'Clone found|^ *- ' | head -40)
  section "Duplicate blocks (jscpd)" "$clones"
}

new_shared_files
new_exports
added_dependencies
dependency_vetting
hand_roll_patterns
duplicate_blocks

echo "REUSE: $total flags"
if [ "$total" -gt 0 ] && [ "${REUSE_STRICT:-0}" = 1 ]; then
  exit 1
fi
exit 0
