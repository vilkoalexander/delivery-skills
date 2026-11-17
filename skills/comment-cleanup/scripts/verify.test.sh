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

echo "# files that come or go fail"
echo 'export const e = 5;' > src/new.ts
has "untracked file" 1 'NOT A COMMENT CHANGE — files added, deleted or renamed' bash "$verify"
reset
git rm -q src/b.ts
has "deleted file"   1 'NOT A COMMENT CHANGE' bash "$verify"

finish
