#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
verify="$here/verify.sh"

new_repo project
mkdir src
cat > src/a.ts <<'TS'
// loads the user
const a = 1; // the first
/* block */ const b = 2;
/**
 * Doc.
 */
export const c = a + b;
TS
cat > src/b.ts <<'TS'
// other file
export const d = 4;
TS
commit_all
reset() { git checkout -q -- . && git clean -qfd; }

has "clean tree" 0 '^ok: 0 file\(s\) changed, comment lines only$' bash "$verify"

echo "# comment-only changes pass"
cat > src/a.ts <<'TS'
const a = 1;
const b = 2;
/** Why: sums the pair. */
export const c = a + b;
TS
has "removed, trimmed and rewritten comments" 0 '^ok: 1 file\(s\) changed, comment lines only$' bash "$verify"
reset

echo "# code changes fail"
sed -i.bak 's/const a = 1;/const a = 2;/' src/a.ts && rm src/a.ts.bak
out=$(bash "$verify" 2>&1); code=$?
eq   "exits 1"                 "$code" 1
sees "names the file"          '^CODE CHANGED — src/a.ts$' "$out"
sees "shows the removed code"  '^< consta=1;$' "$out"
sees "shows the added code"    '^> consta=2;$' "$out"
sees "summary"                 '^FAILED: 1 file\(s\) changed, see above$' "$out"
has  "a path limits the check" 0 '^ok: 0 file' bash "$verify" src/b.ts
reset

echo "# code that looks like a comment change fails"
cat > src/c.ts <<'TS'
let count = 0;
++count;
const cdn = '//cdn.example.com/a.js';
const total = price /* net */ * quantity /* units */;
const area = width
  * height;
// @ts-expect-error legacy shape
const legacy: number = 'x';
const label = 'a  b';
export { count, cdn, total, area, legacy, label };
TS
commit_all c
change() { sed -i.bak "$1" src/c.ts && rm src/c.ts.bak; }
change 's/^++count;$/--count;/'
has "a line that starts with ++ or --"      1 '^CODE CHANGED — src/c.ts$' bash "$verify"
reset
change 's#//cdn.example.com#//evil.example.com#'
has "a // inside a string"                  1 '^CODE CHANGED — src/c.ts$' bash "$verify"
reset
change 's#\* quantity /\* units#* 2 /* units#'
has "code between two inline comments"      1 '^CODE CHANGED — src/c.ts$' bash "$verify"
reset
change 's/^  \* height;$/  * 2;/'
has "a line that starts with *"             1 '^CODE CHANGED — src/c.ts$' bash "$verify"
reset
change '/@ts-expect-error/d'
has "a removed tool directive"              1 '^CODE CHANGED — src/c.ts$' bash "$verify"
reset
change "s/'a  b'/'a b'/"
has "whitespace inside a string"            1 '^CODE CHANGED — src/c.ts$' bash "$verify"
reset
change 's/^let count = 0;$/let count = 1;/'
git add src/c.ts
has "a staged code change"                  1 '^CODE CHANGED — src/c.ts$' bash "$verify"
git reset -q
reset

echo "# comment changes that looked like code pass"
cat > src/view.tsx <<'TSX'
export const View = () => (
  <div>
    {/*
      explains the layout
      at length
    */}
    <span>text</span>
  </div>
);
TSX
commit_all view
sed -i.bak '3,6d' src/view.tsx && rm src/view.tsx.bak
has "a deleted multi-line JSX comment"      0 '^ok: 1 file' bash "$verify"
reset
change 's#^++count;$#++count; // bump#'
git add src/c.ts
has "a staged comment change"               0 '^ok: 1 file' bash "$verify"
git reset -q
reset

echo "# file names git would quote"
printf '// note\nexport const k = 1;\n' > 'src/café one.ts'
commit_all odd
printf '// note\nexport const k = 2;\n' > 'src/café one.ts'
has "code change in a non-ASCII, spaced name" 1 '^CODE CHANGED — src/café one.ts$' bash "$verify"
printf 'export const k = 1;\n' > 'src/café one.ts'
has "comment change in that name"           0 '^ok: 1 file' bash "$verify"
reset

echo "# files that come or go fail"
echo 'export const e = 5;' > src/new.ts
has "untracked file" 1 'NOT A COMMENT CHANGE — files added, deleted or renamed' bash "$verify"
reset
git rm -q src/b.ts
has "deleted file"   1 'NOT A COMMENT CHANGE' bash "$verify"

finish
