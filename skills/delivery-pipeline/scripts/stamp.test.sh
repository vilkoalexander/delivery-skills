#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
stamp="$here/stamp.sh"

new_repo app
mkdir -p src docs/review/features
echo "export const Orders = 1" > src/Orders.tsx
echo "export const Cart = 1" > src/Cart.tsx
echo "export const Row = 1" > src/Row.tsx

write_docs() {
  printf '# Verify recipe\n\n## Launch\n\nRun `npm run dev`.\n' > docs/review/verify.md
  printf '# Orders\n\nThe list. Code: `src/Orders.tsx`, `src/Row.tsx`\n\n## Reach\n\n`/orders`\n' > docs/review/features/orders.md
  printf '# Cart\n\nThe cart. Code: `src/Cart.tsx`\n' > docs/review/features/cart.md
  printf -- '- [Orders](orders.md)\n- [Cart](cart.md)\n' > docs/review/features/README.md
  printf '# React review — project layer\n\nA row: `src/Row.tsx`, a screen: `src/features/<x>/Screen.tsx`\n' > docs/review/react-review.md
}

echo "# usage"
has "no mode"                 2 'usage: stamp.sh' bash "$stamp"
has "set with no file"        2 'usage: stamp.sh' bash "$stamp" set
has "outside a repository"    2 'not a git repository' bash -c "cd '$tmp' && bash '$stamp' check"
has "no documents"            0 '^STAMPS: none' bash "$stamp" check

echo "# before a commit"
write_docs
has "set has no commit to write" 2 'no commit yet' bash "$stamp" set docs/review/verify.md

echo "# unstamped"
commit_all
out=$(bash "$stamp" check 2>&1)
sees   "the recipe"            'UNSTAMPED +docs/review/verify.md' "$out"
sees   "a feature"             'UNSTAMPED +docs/review/features/orders.md' "$out"
sees   "a rubric layer"        'UNSTAMPED +docs/review/react-review.md' "$out"
misses "not the index"         'features/README.md' "$out"
sees   "counts them"           '^STAMPS: 4 of 4 files flagged$' "$out"

echo "# set"
has "writes the commit"        0 '^STAMPED +docs/review/features/orders.md — [0-9a-f]{7,}$' bash "$stamp" set docs/review/features/orders.md
eq  "below the title"          "$(sed -n 3p docs/review/features/orders.md)" "As of: \`$(git rev-parse --short HEAD)\`"
eq  "the title stays first"    "$(sed -n 1p docs/review/features/orders.md)" "# Orders"
bash "$stamp" set docs/review/features/orders.md > /dev/null
eq  "one line, not two"        "$(grep -c '^As of:' docs/review/features/orders.md)" 1
printf '# Cart\n\nAs of: `<commit>`\n\nThe cart. Code: `src/Cart.tsx`\n' > docs/review/features/cart.md
has "a template placeholder is no commit" 0 'UNSTAMPED +docs/review/features/cart.md' bash "$stamp" check docs/review/features/cart.md
bash "$stamp" set docs/review/features/cart.md docs/review/verify.md docs/review/react-review.md > /dev/null
eq  "fills the placeholder of a template" "$(sed -n 3p docs/review/features/cart.md)" "As of: \`$(git rev-parse --short HEAD)\`"
has "a file that is not there" 2 'stamp: no file docs/review/none.md' bash "$stamp" set docs/review/none.md
has "from a subdirectory"      0 'STAMPED +docs/review/verify.md' bash -c "cd docs/review && bash '$stamp' set verify.md"
has "from an absolute path"    0 '^STAMPED +docs/review/verify.md' bash "$stamp" set "$PWD/docs/review/verify.md"
commit_all stamped
has "all fresh"                0 '^STAMPS: ok — 4 files$' bash "$stamp" check

echo "# drift"
echo "export const Orders = 2" > src/Orders.tsx
out=$(bash "$stamp" check 2>&1)
sees   "an uncommitted change" 'DRIFT +docs/review/features/orders.md — 1 path changed since [0-9a-f]+: src/Orders.tsx$' "$out"
misses "only the document that names the path" 'cart.md|react-review.md|verify.md' "$out"
commit_all orders
echo "export const Row = 2" > src/Row.tsx
commit_all row
out=$(bash "$stamp" check 2>&1)
sees   "committed changes"     'DRIFT +docs/review/features/orders.md — 2 paths changed since [0-9a-f]+: src/Orders.tsx, src/Row.tsx' "$out"
sees   "each document that names the path" 'DRIFT +docs/review/react-review.md — 1 path changed' "$out"
sees   "counts them"           '^STAMPS: 2 of 4 files flagged$' "$out"
has "flags, never fails"       0 'DRIFT' bash "$stamp" check
has "takes the files to read"  0 '^STAMPS: ok — 1 files$' bash "$stamp" check docs/review/features/cart.md
has "a named file that is not there" 2 'stamp: no file docs/review/none.md' bash "$stamp" check docs/review/none.md
git rm -q src/Cart.tsx && commit_all gone
has "a path that is gone"      0 'DRIFT +docs/review/features/cart.md — 1 path changed' bash "$stamp" check
bash "$stamp" set docs/review/features/orders.md docs/review/react-review.md > /dev/null
lacks "a new stamp ends the drift" 'orders.md|react-review.md' bash "$stamp" check

echo "# set on a dirty path"
echo "export const Row = 3" > src/Row.tsx
before=$(cat docs/review/features/orders.md)
has "refuses"                  1 'DIRTY +docs/review/features/orders.md — src/Row.tsx has uncommitted changes' bash "$stamp" set docs/review/features/orders.md
has "stamps the rest, still exits 1" 1 'STAMPED +docs/review/verify.md' bash "$stamp" set docs/review/features/orders.md docs/review/verify.md
eq  "and leaves the file"      "$(cat docs/review/features/orders.md)" "$before"
eq  "the rest is written"      "$(sed -n 3p docs/review/verify.md)" "As of: \`$(git rev-parse --short HEAD)\`"
git checkout -q src/Row.tsx

echo "# more than three paths"
for name in a b c d e; do echo 1 > "src/$name.ts"; done
printf '# Wide\n\nCode: `src/a.ts`, `src/b.ts`, `src/c.ts`, `src/d.ts`, `src/e.ts`\n' > docs/review/features/wide.md
commit_all wide
bash "$stamp" set docs/review/features/wide.md > /dev/null
for name in a b c d e; do echo 2 > "src/$name.ts"; done
has "names three and counts the rest" 0 'DRIFT +docs/review/features/wide.md — 5 paths changed since [0-9a-f]+: src/a.ts, src/b.ts, src/c.ts \+2 more$' bash "$stamp" check docs/review/features/wide.md
git checkout -q src

echo "# what counts as a named path"
mkdir -p 'app/[id]' .github
echo 1 > 'app/[id]/page.tsx'; echo 1 > .github/ci.yml; echo 1 > package.json
printf '# Routes\n\nCode: `app/[id]/page.tsx`, `.github/ci.yml:12`, `package.json`, `src/../../out/x.ts`, `application/json`\n' > docs/review/features/routes.md
printf '# Folder\n\nCode: `app/`\n' > docs/review/features/folder.md
commit_all routes
bash "$stamp" set docs/review/features/routes.md docs/review/features/folder.md > /dev/null
echo 2 > 'app/[id]/page.tsx'; echo 2 > .github/ci.yml; echo 2 > package.json
out=$(bash "$stamp" check docs/review/features/routes.md docs/review/features/folder.md 2>&1)
sees   "brackets, a leading dot, a line number, a root file" 'DRIFT +docs/review/features/routes.md — 3 paths changed since [0-9a-f]+: .github/ci.yml, app/\[id\]/page.tsx, package.json$' "$out"
sees   "a directory"           'DRIFT +docs/review/features/folder.md — 1 path changed since [0-9a-f]+: app/\[id\]/page.tsx$' "$out"
git checkout -q .

echo "# a document that names a document"
printf '# Verify recipe\n\nRead `docs/review/features/orders.md` and `src/Row.tsx`.\n' > docs/review/verify.md
commit_all names-a-document
has "is not dirty by the other stamp" 0 'STAMPED +docs/review/verify.md' bash "$stamp" set docs/review/features/orders.md docs/review/verify.md
commit_all stamped-again
has "and does not drift by it"  0 '^STAMPS: ok — 1 files$' bash "$stamp" check docs/review/verify.md

echo "# a file that cannot take the stamp"
: > docs/review/features/blank.md
has "no title"                 1 'NO TITLE +docs/review/features/blank.md' bash "$stamp" set docs/review/features/blank.md
eq  "and stays empty"          "$(wc -c < docs/review/features/blank.md | tr -d ' ')" 0
printf -- '---\nname: x\n---\n# Layer\n\nText.\n' > docs/review/features/front.md
bash "$stamp" set docs/review/features/front.md > /dev/null
eq  "front matter stays whole" "$(sed -n 1,4p docs/review/features/front.md | tr '\n' '|')" "---|name: x|---|# Layer|"
eq  "the stamp goes below the title" "$(sed -n 6p docs/review/features/front.md)" "As of: \`$(git rev-parse --short HEAD)\`"
printf '# Locked\n' > docs/review/features/locked.md && chmod 444 docs/review/features/locked.md
has "a file that cannot be written" 1 'FAILED +docs/review/features/locked.md — the stamp was not written' bash "$stamp" set docs/review/features/locked.md
rm -f docs/review/features/blank.md docs/review/features/front.md docs/review/features/locked.md
echo 1 > src/New.tsx
printf '# New\n\nCode: `src/New.tsx`\n' > docs/review/features/new.md
has "an untracked path is dirty" 1 'DIRTY +docs/review/features/new.md — src/New.tsx has uncommitted changes' bash "$stamp" set docs/review/features/new.md
rm -f src/New.tsx

echo "# a commit that is gone"
printf '# New\n\nAs of: `0123456789abcdef`\n\nCode: `src/Row.tsx`\n' > docs/review/features/new.md
has "says lost for a document that was never committed" 0 'LOST +docs/review/features/new.md — commit 0123456789abcdef is not in this repository' bash "$stamp" check docs/review/features/new.md
commit_all squashed
has "uses the commit of the document" 0 '^STAMPS: ok — 1 files$' bash "$stamp" check docs/review/features/new.md
echo "export const Row = 4" > src/Row.tsx
has "and says the stamp is gone" 0 'DRIFT +docs/review/features/new.md — 1 path changed since [0-9a-f]+ \(stamp 0123456789abcdef is gone\): src/Row.tsx$' bash "$stamp" check docs/review/features/new.md
git checkout -q src/Row.tsx

echo "# VERIFY_DIR"
mkdir -p ops/features
printf '# Recipe\n' > ops/verify.md
has "reads another directory"  0 'UNSTAMPED +ops/verify.md' env VERIFY_DIR=ops bash "$stamp" check

finish
