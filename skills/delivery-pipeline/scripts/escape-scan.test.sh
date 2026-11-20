#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/escape-scan.sh"

new_repo project
echo base > README.md && commit_all

# added NAME PATTERN FILE CONTENT — scans a new file holding one line; the scan never fails
added() {
  local name=$1 pattern=$2 file=$3 content=$4 out code
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" > "$file"
  out=$(bash "$scan" "$file" 2>&1)
  code=$?
  rm -f "$file"
  if [ "$code" != 0 ]; then nok "$name" "exit $code, wanted 0"$'\n'"$out"
  elif ! grep -qE -- "$pattern" <<< "$out"; then nok "$name" "no match for $pattern"$'\n'"$out"
  else ok "$name"; fi
}
clean='^ESCAPES: 0 flags$'

echo "# a silenced checker"
added "eslint-disable"          "src/a.ts:1 — checker silenced — // eslint-disable-next-line no-console" src/a.ts "// eslint-disable-next-line no-console"
added "ts-ignore"               "checker silenced"  src/a.ts "  // @ts-ignore"
added "ts-expect-error"         "checker silenced"  src/a.tsx "{/* @ts-expect-error wrong props */}"
added "SuppressWarnings"        "checker silenced"  src/main/java/A.java '@SuppressWarnings("unchecked")'
added "Kotlin Suppress"         "checker silenced"  src/main/kotlin/A.kt '@Suppress("UNCHECKED_CAST")'
added "coverage ignore"         "checker silenced"  src/a.ts "/* istanbul ignore next */"

echo "# a type escape"
added "as any"                  "src/a.ts:1 — type escape" src/a.ts "const user = payload as any;"
added "double cast"             "type escape"       src/a.ts "return row as unknown as Order;"
added "a word that ends in as"  "$clean"            src/a.ts "const alias = canvas; const many = 1;"
added "as any in plain js"      "$clean"            src/a.js "// treat it as any other row"

echo "# a comment that defers the fix"
added "for now"                 "src/a.ts:1 — comment defers the fix" src/a.ts "// fine for now"
added "workaround"              "comment defers the fix" src/a.ts "  // workaround: the list renders twice"
added "todo"                    "comment defers the fix" src/a.ts "const x = 1; // TODO handle the empty case"
added "block comment body"      "comment defers the fix" src/A.java " * Temporary until the client sends the id."
added "the word in code"        "$clean"            src/a.ts "const workaround = hack(todo);"
added "a longer word"           "$clean"            src/a.ts "// the hackathon list"

echo "# copies kept in sync by hand"
added "keep in sync"            "src/a.ts:1 — copies kept in sync by a comment" src/a.ts "// keep in sync with apps/web/src/roles.ts"
added "must match"              "copies kept in sync" src/a.ts "// must match the enum in the schema"

echo "# what is not scanned"
added "a test file"             "$clean"            src/a.spec.ts "const x = y as any; // @ts-ignore"
added "a tests directory"       "$clean"            src/__tests__/a.ts "// @ts-ignore"
added "a Java test"             "$clean"            src/test/java/ATest.java '@SuppressWarnings("unchecked")'
added "a declaration file"      "$clean"            src/a.d.ts "declare const x: any; // @ts-ignore"
added "a doc"                   "$clean"            docs/a.md "// @ts-ignore"
ESCAPE_ALLOW='src/legacy/' added "ESCAPE_ALLOW path" "$clean" src/legacy/a.ts "// @ts-ignore"

echo "# only what the change adds"
mkdir -p src
echo "// @ts-ignore" > src/old.ts && commit_all old
echo "export const x = 1" >> src/old.ts
has "an escape already committed is not this change's" 0 "$clean" bash "$scan" src/old.ts
git checkout -q src/old.ts

echo "# which paths, and the exit code"
printf 'export const a = 1\nconst b = a as any\n' > src/new.ts
has "no arguments: every changed path" 0 "src/new.ts:2 — type escape — const b = a as any" bash "$scan"
has "paths on stdin"                   0 "src/new.ts:2"            bash -c "echo src/new.ts | bash '$scan'"
has "a flag says what to do"           0 "fix the cause of each one" bash "$scan" src/new.ts
has "counts the flags"                 0 "^ESCAPES: 1 flags$"      bash "$scan" src/new.ts
has "ESCAPE_STRICT fails on a flag"    1 "^ESCAPES: 1 flags$"      env ESCAPE_STRICT=1 bash "$scan" src/new.ts
git add -N . 2>/dev/null
has "a file added with -N"             0 "src/new.ts:2"            bash "$scan" src/new.ts
commit_all new
has "committed, so the tree is clean"  0 "$clean"                  bash "$scan"
has "ESCAPE_STRICT passes a clean tree" 0 "$clean"                 env ESCAPE_STRICT=1 bash "$scan"
has "ESCAPE_DIFF_RANGE scans a range"  0 "src/new.ts:2"            env ESCAPE_DIFF_RANGE=HEAD~1..HEAD bash "$scan"
printf 'const long = %s as any\n' "$(printf 'x%.0s' $(seq 1 150))" > src/long.ts
has "a long line is cut"               0 "x{60}…$"                 bash "$scan" src/long.ts
rm src/long.ts

mkdir -p "$tmp/plain" && cd "$tmp/plain"
has "outside git" 2 "escape-scan: not a git repository" env GIT_CEILING_DIRECTORIES="$tmp" bash "$scan"

finish
