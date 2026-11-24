#!/usr/bin/env bash
# Says which project-layer documents were last confirmed against code that has
# changed since. A document carries one line, "As of: `<commit>`". The paths it
# names in backticks are compared with that commit, the working tree included.
#
#   bash stamp.sh check [file...]   default: the verify recipe, the feature map and the rubric layers
#   bash stamp.sh set file...       write the current commit into each file, below its title
#
# `check` prints one line per document and ends with a `STAMPS:` line. It flags, never fails:
#   DRIFT       a path the document names changed since its commit
#   UNSTAMPED   the document has no commit
#   LOST        the commit is not in this repository, and the document was never committed
#   ERROR       git could not compare the paths
# A commit that a squash or a rebase removed is replaced by the last commit of the document.
#
# `set` says the document is true for the code of HEAD. It refuses a document
# that names a path with uncommitted changes, and one with no "# " title (exit 1).
#
# A named path is a span in backticks with a "/" or a "." in it that is a file or
# a directory now, or was one at the commit. Paths in the documents' own directory do not count.
#
#   VERIFY_DIR   where the documents live, relative to the root (default docs/review)
set -uo pipefail

usage() {
  echo "usage: stamp.sh check [file...] | stamp.sh set file..." >&2
  exit 2
}

mode="${1:-}"
[ $# -gt 0 ] && shift
case "$mode" in check | set) ;; *) usage ;; esac
[ "$mode" = set ] && [ $# -eq 0 ] && usage

if ! root=$(git rev-parse --show-toplevel 2> /dev/null); then
  echo "stamp: not a git repository" >&2
  exit 2
fi
prefix=$(git rev-parse --show-prefix)
dir="${VERIFY_DIR:-docs/review}"
dir="${dir%/}"

files=()
for file in "$@"; do
  case "$file" in
    "$root"/*) file="${file#"$root"/}" ;;
    /*) ;;
    *) file="$prefix$file" ;;
  esac
  case "$file" in -*) file="./$file" ;; esac
  files+=("$file")
done
cd "$root" || exit 2

for file in ${files[@]+"${files[@]}"}; do
  if [ ! -f "$file" ]; then
    echo "stamp: no file $file" >&2
    exit 2
  fi
done

if [ "$mode" = check ] && [ ${#files[@]} -eq 0 ]; then
  for file in "$dir"/*.md "$dir"/features/*.md; do
    [ -f "$file" ] && [ "$file" != "$dir/features/README.md" ] && files+=("$file")
  done
fi

stamp_of() {
  sed -nE 's/^As of: `([0-9a-f]{7,64})`.*/\1/p' "$1" | head -1
}

# names_code SPAN COMMIT
names_code() {
  case "$1" in
    -* | /* | '~'* | *://* | "$dir" | "$dir"/* | *'<'* | *'>'* | *'*'* | *'?'*) return 1 ;;
  esac
  case "$1" in */* | *.*) ;; *) return 1 ;; esac
  case "/$1/" in */../* | */./*) return 1 ;; esac
  [ -e "$1" ] || git cat-file -e "$2:${1%/}" 2> /dev/null
}

# read_specs FILE COMMIT — fills specs with one literal pathspec per named path
specs=()
read_specs() {
  local span
  specs=()
  while IFS= read -r span; do
    [ -n "$span" ] && names_code "$span" "$2" && specs+=(":(literal)${span%/}")
  done < <(grep -oE '`[^` ]+`' "$1" | tr -d '`' | sed -E 's/:[0-9]+(:[0-9]+)?$//' | sort -u)
  [ ${#specs[@]} -gt 0 ] && specs+=(":(exclude,literal)$dir")
}

# first_three LINES — "a, b, c +N more"
first_three() {
  awk '
    NF { n++; if (n <= 3) list = list (n > 1 ? ", " : "") $0 }
    END { print list (n > 3 ? " +" n - 3 " more" : "") }
  ' <<< "$1"
}

line() {
  printf '%-11s %s — %s\n' "$1" "$2" "$3"
}

check() {
  local file hash base gone changed count total=0 flagged=0
  for file in ${files[@]+"${files[@]}"}; do
    total=$((total + 1))
    hash=$(stamp_of "$file")
    if [ -z "$hash" ]; then
      flagged=$((flagged + 1))
      line UNSTAMPED "$file" 'no "As of:" commit; stamp.sh set writes one'
      continue
    fi
    base=$hash
    gone=""
    if ! git cat-file -e "$hash^{commit}" 2> /dev/null; then
      base=$(git log -1 --format=%h -- "$file" 2> /dev/null)
      gone=" (stamp $hash is gone)"
      if [ -z "$base" ]; then
        flagged=$((flagged + 1))
        line LOST "$file" "commit $hash is not in this repository"
        continue
      fi
    fi
    read_specs "$file" "$base"
    [ ${#specs[@]} -gt 0 ] || continue
    if ! changed=$(git diff --name-only "$base" -- "${specs[@]}" 2>&1); then
      flagged=$((flagged + 1))
      line ERROR "$file" "git diff failed: $(head -1 <<< "$changed")"
      continue
    fi
    untracked=$(git ls-files --others --exclude-standard -- "${specs[@]}" 2> /dev/null)
    [ -z "$untracked" ] || changed="${changed:+$changed$'\n'}$untracked"
    [ -n "$changed" ] || continue
    flagged=$((flagged + 1))
    count=$(grep -c . <<< "$changed")
    line DRIFT "$file" "$count $([ "$count" = 1 ] && echo path || echo paths) changed since $base$gone: $(first_three "$changed")"
  done
  if [ "$total" = 0 ]; then
    echo "STAMPS: none — no document in $dir"
  elif [ "$flagged" = 0 ]; then
    echo "STAMPS: ok — $total files"
  else
    echo "STAMPS: $flagged of $total files flagged"
  fi
}

# write_stamp FILE COMMIT — 3 when the file has no title to put the line under
write_stamp() {
  local file=$1 hash=$2 copy
  grep -qE '^(As of: `[^`]*`|# )' "$file" || return 3
  copy=$(mktemp "$file.XXXXXX") || return 1
  cp -p "$file" "$copy" 2> /dev/null
  if grep -qE '^As of: `[^`]*`' "$file"; then
    HASH=$hash awk '
      !done && /^As of: `[^`]*`/ { print "As of: `" ENVIRON["HASH"] "`"; done = 1; next }
      { print }
    ' "$file"
  else
    HASH=$hash awk '
      { print }
      !done && /^# / { print ""; print "As of: `" ENVIRON["HASH"] "`"; done = 1 }
    ' "$file"
  fi 2> /dev/null > "$copy" && [ "$(stamp_of "$copy")" = "$hash" ] && mv -f "$copy" "$file" && return 0
  rm -f "$copy"
  return 1
}

set_stamps() {
  local file head dirty code=0
  if ! head=$(git rev-parse --short HEAD 2> /dev/null); then
    echo "stamp: no commit yet" >&2
    exit 2
  fi
  for file in "${files[@]}"; do
    read_specs "$file" "$head"
    dirty=""
    if [ ${#specs[@]} -gt 0 ] && ! dirty=$(git status --porcelain -- "${specs[@]}" 2>&1); then
      code=1
      line ERROR "$file" "git status failed: $(head -1 <<< "$dirty")"
      continue
    fi
    if [ -n "$dirty" ]; then
      code=1
      line DIRTY "$file" "$(first_three "$(cut -c4- <<< "$dirty")") has uncommitted changes; commit, then stamp"
      continue
    fi
    write_stamp "$file" "$head"
    case $? in
      0) line STAMPED "$file" "$head" ;;
      3) code=1 && line "NO TITLE" "$file" 'no "# " heading to put the stamp under' ;;
      *) code=1 && line FAILED "$file" "the stamp was not written" ;;
    esac
  done
  exit "$code"
}

if [ "$mode" = check ]; then check; else set_stamps; fi
