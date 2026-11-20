#!/usr/bin/env bash
# Flags the lines a change adds to get past a check instead of fixing its
# cause: a silenced checker, a cast that turns the type system off, a comment
# that defers the fix, a comment that keeps two copies in sync by hand.
# Flags, not a verdict: a reviewer or the human judges each one.
#
#   bash escape-scan.sh [path...]              default: every changed path
#   git diff --name-only | bash escape-scan.sh
#
# Prints `path:line — rule — the line` per flag. Reads added lines only, in
# source files that are not tests.
#
#   ESCAPE_DIFF_RANGE  base..head to scan instead of the working tree vs HEAD
#   ESCAPE_ALLOW       ERE over `path:line:text`; matching lines are not flags
#                      (default: escapes.allow in docs/review/delivery.json)
#   ESCAPE_STRICT=1    exit 1 when anything was flagged
set -uo pipefail

range="${ESCAPE_DIFF_RANGE:-}"
allow="${ESCAPE_ALLOW:-$(node "$(dirname "$0")/config.mjs" get escapes.allow 2>/dev/null)}"
if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "escape-scan: not a git repository" >&2
  exit 2
fi
cd "$root"

# ------------------------------------------------------------- which paths
paths=("$@")

# A harness can hand a pipe that never closes; wait one second for each line.
read_paths_from_stdin() {
  local line
  [ -t 0 ] && return 0
  while IFS= read -r -t 1 line; do
    [ -n "$line" ] && paths+=("$line")
  done
}

changed_paths() {
  if [ -n "$range" ]; then
    git diff --name-only "$range"
  else
    { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
  fi
}

[ ${#paths[@]} -gt 0 ] || read_paths_from_stdin
if [ ${#paths[@]} -eq 0 ]; then
  while IFS= read -r path; do
    paths+=("$path")
  done < <(changed_paths)
fi

is_test='\.(spec|test)\.|(^|/)(__tests__|__mocks__|__fixtures__|fixtures|tests?|e2e|cypress|playwright)/|(Tests?|IT)\.(java|kt)$'
sources=()
for path in ${paths[@]+"${paths[@]}"}; do
  [[ $path =~ $is_test ]] && continue
  case "$path" in
    *.d.ts|*.min.js) ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.java|*.kt) sources+=("$path") ;;
  esac
done
if [ ${#sources[@]} -eq 0 ]; then
  echo "ESCAPES: 0 flags"
  exit 0
fi

# ------------------------------------------------------------- added lines
is_tracked() {
  git ls-files --error-unmatch "$1" > /dev/null 2>&1
}

# A diff of the paths; an untracked file counts as added whole.
diff_of() {
  local file
  if [ -n "$range" ]; then
    git diff -U0 "$range" -- "$@"
    return
  fi
  git diff -U0 HEAD -- "$@"
  for file in "$@"; do
    [ -f "$file" ] || continue
    is_tracked "$file" && continue
    printf '+++ b/%s\n' "$file"
    sed 's/^/+/' "$file"
  done
}

# Turns a -U0 diff into "path:line:text", one line per added line.
number_added_lines() {
  awk '
    /^\+\+\+ b\// { file = substr($0, 7); line = 0; next }
    /^@@/         { split($3, hunk, /[,+]/); line = hunk[2] - 1; next }
    /^\+/         { line++; print file ":" line ":" substr($0, 2); next }
    /^-/          { next }
                  { line++ }
  '
}

added=$(diff_of "${sources[@]}" 2>/dev/null | number_added_lines | LC_ALL=C grep -a . || true)
if [ -n "$allow" ]; then
  added=$(printf '%s\n' "$added" | grep -vE -- "$allow" || true)
fi

# ------------------------------------------------------------------- rules
flags=""

# rule NAME LINES REGEX [i] — records "path:line — NAME — the line" for each matching line
rule() {
  local name=$1 lines=$2 regex=$3 ignore_case=${4:-} found
  found=$(printf '%s\n' "$lines" \
    | LC_ALL=C grep -a"$ignore_case"E -- "$regex" \
    | NAME=$name awk '
        match($0, /^[^:]*:[0-9]+:/) {
          where = substr($0, 1, RLENGTH - 1)
          text = substr($0, RLENGTH + 1)
          gsub(/^[ \t]+|[ \t]+$/, "", text)
          if (length(text) > 100) text = substr(text, 1, 100) "…"
          print where " — " ENVIRON["NAME"] " — " text
        }')
  [ -n "$found" ] && flags="$flags$found"$'\n'
}

rule "checker silenced" "$added" \
  'eslint-disable|@ts-(ignore|expect-error|nocheck)|biome-ignore|@SuppressWarnings|@Suppress\(|NOSONAR|CHECKSTYLE:OFF|noinspection|(istanbul|c8|v8) ignore'

typescript=$(printf '%s\n' "$added" | grep -E '^[^:]*\.[cm]?tsx?:' || true)
rule "type escape" "$typescript" \
  '(^|[^A-Za-z0-9_$])as[[:space:]]+any([^A-Za-z0-9_$]|$)|(^|[^A-Za-z0-9_$])as[[:space:]]+unknown[[:space:]]+as[[:space:]]'

# A full-line comment, a block-comment body line, or a trailing `//` that is not the tail of a URL scheme.
comments=$(printf '%s\n' "$added" | grep -E '^[^:]*:[0-9]+:[[:space:]]*(//|/\*|\*)|[^:"'"'"'`/]//[[:space:]]' || true)
rule "comment defers the fix" "$comments" \
  '(^|[^a-z])(for now|temporar(y|ily)|workaround|work around|hack|hacky|quick fix|band-?aid|good enough|should be (fine|ok|okay|safe)|too risky|todo|fixme)([^a-z]|$)' i
rule "copies kept in sync by a comment" "$comments" \
  '(keep|kept|stay|stays)[a-z ]* in sync|in sync with|must match[[:space:]]' i

# ------------------------------------------------------------------ report
flags=$(printf '%s' "$flags" | sort -u)
count=0
if [ -n "$flags" ]; then
  count=$(printf '%s\n' "$flags" | wc -l | tr -d ' ')
  printf '%s\n' "$flags"
fi
echo "ESCAPES: $count flags"
if [ "$count" -gt 0 ]; then
  echo "fix the cause of each one. A rule that is wrong for the line stays silenced with the reason on the line; two copies go in docs/review/drift.checks; a flag the project accepts goes in escapes.allow"
  [ "${ESCAPE_STRICT:-}" = 1 ] && exit 1
fi
exit 0
