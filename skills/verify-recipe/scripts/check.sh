#!/usr/bin/env bash
# Says whether a project's verify recipe and feature map are whole: every
# section there and filled, every feature in the index, no placeholder left,
# no path named that is gone. It reads files; it starts nothing.
#
#   bash check.sh [root]        default: the git root of the cwd
#
# Prints one line per problem and ends with `VERIFY RECIPE: ok — N features`
# (exit 0), `VERIFY RECIPE: N problems` (exit 1) or `VERIFY RECIPE: none`
# (exit 1) when the project has no recipe.
#
#   VERIFY_DIR   where the recipe lives, relative to the root (default docs/review)
set -uo pipefail

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
if ! cd "$root" 2>/dev/null; then
  echo "check: no directory $root" >&2
  exit 2
fi
dir="${VERIFY_DIR:-docs/review}"
recipe="$dir/verify.md"
features="$dir/features"
index="$features/README.md"

if [ ! -f "$recipe" ]; then
  echo "VERIFY RECIPE: none — no $recipe; the verify-recipe skill writes one"
  exit 1
fi

problems=0
problem() {
  problems=$((problems + 1))
  printf '%-11s %s — %s\n' "$1" "$2" "$3"
}

# body FILE TITLE — the lines below "## TITLE", up to the next "## "
body() {
  TITLE="## $2" awk '
    /^## / { on = ($0 == ENVIRON["TITLE"]); next }
    on
  ' "$1"
}

has_section() {
  grep -qxF -- "## $2" "$1"
}

has_text() {
  grep -q '[^[:space:]]' <<< "$1"
}

# A fenced block with a line in it, or a span in backticks.
names_a_command() {
  awk '
    /^[[:space:]]*```/ { fenced = !fenced; next }
    fenced && NF       { found = 1 }
    /`[^`]+`/          { found = 1 }
    END                { exit found ? 0 : 1 }
  ' <<< "$1"
}

# sections FILE "must have text" "may be empty" "must name a command"
sections() {
  local file=$1 filled=$2 optional=$3 commands=$4 title text
  for title in $filled $optional; do
    title=${title//_/ }
    if ! has_section "$file" "$title"; then
      problem MISS "$file" "no \"## $title\" section"
      continue
    fi
    text=$(body "$file" "$title")
    case " ${optional//_/ } " in *" $title "*) continue ;; esac
    if ! has_text "$text"; then
      problem EMPTY "$file" "\"## $title\" says nothing"
      continue
    fi
    case " $commands " in
      *" $title "*) names_a_command "$text" || problem "NO COMMAND" "$file" "\"## $title\" names no command" ;;
    esac
  done
}

# The templates mark what to replace with <angle brackets>: a whole backtick span, a whole line, or a title.
placeholders() {
  local file=$1 hit
  while IFS= read -r hit; do
    [ -n "$hit" ] && problem PLACEHOLDER "$file:${hit%%:*}" "$(sed -E 's/^[0-9]+:[[:space:]]*//' <<< "$hit" | cut -c1-80)"
  done < <(grep -nE '`<[^`]*>`|^[-[:space:]]*<[^>]+>[[:space:]]*$|^# <' "$file")
}

# A span in backticks that reads as a file of this repository and is not there.
stale_paths() {
  local file=$1 path
  while IFS= read -r path; do
    [ -n "$path" ] && [ ! -e "$path" ] && problem STALE "$file" "$path does not exist"
  done < <(grep -oE '`[^` ]+`' "$file" | tr -d '`' \
    | grep -E '^[A-Za-z0-9_@][A-Za-z0-9_@./-]*/[A-Za-z0-9_@./-]*\.[A-Za-z0-9]+$' \
    | grep -vE '^(https?|localhost)|^[0-9.]+/' | sort -u)
}

sections "$recipe" "Launch Doctor Drive Evidence Cleanup" "" "Launch Doctor Cleanup"
placeholders "$recipe"
stale_paths "$recipe"

count=0
if [ ! -f "$index" ]; then
  problem MISS "$index" "no index of the feature map"
fi
for feature in "$features"/*.md; do
  [ -f "$feature" ] || continue
  [ "$feature" = "$index" ] && continue
  count=$((count + 1))
  sections "$feature" "Reach Drive Proves_it" "Gotchas" ""
  placeholders "$feature"
  stale_paths "$feature"
  if [ -f "$index" ] && ! grep -qF -- "$(basename "$feature")" "$index"; then
    problem UNLISTED "$feature" "not in $index"
  fi
done
[ "$count" -gt 0 ] || problem MISS "$features" "no feature file"

if [ -f "$index" ]; then
  while IFS= read -r name; do
    [ "$name" = README.md ] && continue
    [ -f "$features/$name" ] || problem GONE "$index" "names $name, which does not exist"
  done < <(grep -oE '[A-Za-z0-9._-]+\.md' "$index" | sort -u)
fi

if [ "$problems" -gt 0 ]; then
  echo "VERIFY RECIPE: $problems problems"
  exit 1
fi
echo "VERIFY RECIPE: ok — $count features"
