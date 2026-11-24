#!/usr/bin/env bash
# Flags the functions a change made more complex when they were complex
# already, or took past the limit: the slow way a codebase goes bad, one
# branch per chunk, each diff fine on its own.
# Flags, not a verdict: a reviewer or the human judges each one.
#
#   bash erosion-scan.sh [path...]              default: every changed path
#   git diff --name-only | bash erosion-scan.sh
#
# Prints `path:line — complex function grew — name: before → after` per flag.
# Compares each function with the one of the same name before the change, in
# source files that are not tests. A new function is not a flag, whatever its
# size: the linter owns that. complexity.mjs says how the count is made.
#
#   EROSION_DIFF_RANGE  base..head to scan instead of the working tree vs HEAD
#   EROSION_THRESHOLD   complexity a function must reach to be a flag
#                       (default: erosion.threshold in docs/review/delivery.json, else 10)
#   EROSION_ALLOW       ERE over `path:function`; matching functions are not flags
#                       (default: erosion.allow in docs/review/delivery.json)
#   EROSION_STRICT=1    exit 1 when anything was flagged
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
range="${EROSION_DIFF_RANGE:-}"
threshold="${EROSION_THRESHOLD:-$(node "$here/config.mjs" get erosion.threshold 2>/dev/null)}"
threshold="${threshold:-10}"
allow="${EROSION_ALLOW:-$(node "$here/config.mjs" get erosion.allow 2>/dev/null)}"
if ! [[ $threshold =~ ^[0-9]+$ ]]; then
  echo "erosion-scan: threshold must be a number, got '$threshold'" >&2
  exit 2
fi
if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "erosion-scan: not a git repository" >&2
  exit 2
fi
cd "$root"

base=HEAD
head=
case "$range" in
  '') ;;
  *...*) head=${range##*...}; base=$(git merge-base "${range%%...*}" "${head:-HEAD}" 2>/dev/null) ;;
  *)     head=${range##*..}; base=${range%%..*} ;;
esac
[ -n "$range" ] && head=${head:-HEAD}

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
    git diff --name-only HEAD
  fi
}

[ ${#paths[@]} -gt 0 ] || read_paths_from_stdin
if [ ${#paths[@]} -eq 0 ]; then
  while IFS= read -r path; do
    paths+=("$path")
  done < <(changed_paths)
fi

is_test='\.(spec|test)\.|(^|/)(__tests__|__mocks__|__fixtures__|fixtures|tests?|e2e|cypress|playwright)/|(Tests?|IT)\.(java|kt)$'

language_of() {
  [[ $1 =~ $is_test ]] && return 1
  case "$1" in
    *.d.ts|*.min.js) return 1 ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) echo js ;;
    *.java) echo java ;;
    *.kt) echo kt ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------ before and after
before_of() {
  git show "$base:$1" 2>/dev/null
}

after_of() {
  if [ -n "$range" ]; then git show "$head:$1" 2>/dev/null; else cat "$1" 2>/dev/null; fi
}

flags=""
unread=()
for path in ${paths[@]+"${paths[@]}"}; do
  language=$(language_of "$path") || continue
  before_of "$path" > /dev/null || continue
  after_of "$path" > /dev/null || continue

  if ! before=$(before_of "$path" | node "$here/complexity.mjs" "$language" 2>/dev/null) \
    || ! after=$(after_of "$path" | node "$here/complexity.mjs" "$language" 2>/dev/null); then
    unread+=("$path")
    continue
  fi
  [ -n "$before" ] && [ -n "$after" ] || continue

  # "path:function<TAB>the flag", so the allow list reads the first field only.
  found=$(FILE=$path LIMIT=$threshold awk -F'\t' '
    NR == FNR { was[$1] = $3; next }
    ($1 in was) && $3 > was[$1] && $3 >= ENVIRON["LIMIT"] + 0 {
      file = ENVIRON["FILE"]
      print file ":" $1 "\t" file ":" $2 " — complex function grew — " $1 ": " was[$1] " → " $3
    }
  ' <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
  [ -n "$found" ] && flags="$flags$found"$'\n'
done

if [ -n "$allow" ] && [ -n "$flags" ]; then
  flags=$(printf '%s' "$flags" | ALLOW=$allow awk -F'\t' '$1 !~ ENVIRON["ALLOW"]')
fi
flags=$(printf '%s' "$flags" | cut -f2- | LC_ALL=C grep -a . || true)

# ------------------------------------------------------------------ report
count=0
if [ -n "$flags" ]; then
  count=$(printf '%s\n' "$flags" | wc -l | tr -d ' ')
  printf '%s\n' "$flags"
fi
if [ ${#unread[@]} -gt 0 ]; then
  echo "not read, the brackets do not balance for the scan: ${unread[*]}"
fi
echo "EROSION: $count flags (limit $threshold)"
if [ "$count" -gt 0 ]; then
  echo "give the new branch a function of its own, or split the function. A function the project accepts as it is goes in erosion.allow"
  [ "${EROSION_STRICT:-}" = 1 ] && exit 1
fi
exit 0
