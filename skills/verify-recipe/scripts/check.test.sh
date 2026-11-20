#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
check="$here/check.sh"
templates="$here/../../../templates"

new_repo app
mkdir -p src docs/review/features
echo "export const Orders = 1" > src/Orders.tsx

echo "# no recipe"
has "says none"             1 '^VERIFY RECIPE: none — no docs/review/verify.md' bash "$check"
has "a root that is not there" 2 'check: no directory' bash "$check" "$tmp/nowhere"

write_recipe() {
  cat > docs/review/verify.md <<'MD'
# Verify recipe

## Launch

```bash
npm run dev
```

- Ready when: `GET /health` answers 200

## Doctor

Run `curl -fsS http://localhost:3000/health`.

## Drive

The browser tool. Handles are test ids.

## Evidence

Goes to the temp directory.

## Cleanup

```bash
kill "$(cat dev.pid)"
```
MD
}

write_feature() {
  cat > "docs/review/features/$1.md" <<'MD'
# Orders

The list of orders. Code: `src/Orders.tsx`

## Reach

`/orders`, or "Orders" in the side menu.

## Drive

Press `orders-new`, then `POST /orders` with `application/json`.

## Proves it

The row is first in the table, and `GET /orders/<id>` answers 200.

## Gotchas
MD
}

echo "# a whole recipe"
write_recipe
write_feature orders
echo "- [Orders](orders.md)" > docs/review/features/README.md
has "passes"                       0 '^VERIFY RECIPE: ok — 1 features$' bash "$check"
has "takes the root as an argument" 0 'ok — 1 features' bash -c "cd / && bash '$check' '$tmp/app'"
lacks "an id in a URL is not a placeholder" 'PLACEHOLDER' bash "$check"
lacks "a route and a media type are not paths" 'STALE' bash "$check"

echo "# the recipe"
sed -i.bak '/^## Doctor$/,/^## Drive$/{/^## Drive$/!d;}' docs/review/verify.md
has "a section that is gone"       1 'MISS +docs/review/verify.md — no "## Doctor" section' bash "$check"
write_recipe
sed -i.bak 's/^The browser tool.*$//' docs/review/verify.md
has "a section with no text"       1 'EMPTY +docs/review/verify.md — "## Drive" says nothing' bash "$check"
write_recipe
sed -i.bak 's/^kill .*$//' docs/review/verify.md
has "a cleanup with no command"    1 'NO COMMAND +docs/review/verify.md — "## Cleanup" names no command' bash "$check"
write_recipe
sed -i.bak 's/^npm run dev$/<npm run dev>/' docs/review/verify.md
has "a placeholder line"           1 'PLACEHOLDER +docs/review/verify.md:6 — <npm run dev>' bash "$check"
write_recipe
echo '- Sign in as: `<demo user>`' >> docs/review/verify.md
has "a placeholder span"           1 'PLACEHOLDER +docs/review/verify.md:[0-9]+ — - Sign in as' bash "$check"
has "counts the problems"          1 '^VERIFY RECIPE: 1 problems$' bash "$check"
write_recipe
rm -f docs/review/verify.md.bak

echo "# the feature map"
write_feature cart
has "a feature the index lacks"    1 'UNLISTED +docs/review/features/cart.md — not in docs/review/features/README.md' bash "$check"
rm docs/review/features/cart.md
echo "- [Refunds](refunds.md)" >> docs/review/features/README.md
has "an index line with no file"   1 'GONE +docs/review/features/README.md — names refunds.md' bash "$check"
echo "- [Orders](orders.md)" > docs/review/features/README.md
sed -i.bak '/^## Proves it$/,/^## Gotchas$/{/^## /!d;}' docs/review/features/orders.md
has "a feature that proves nothing" 1 'EMPTY +docs/review/features/orders.md — "## Proves it" says nothing' bash "$check"
write_feature orders
sed -i.bak '/^## Gotchas$/d' docs/review/features/orders.md
has "a feature with no Gotchas heading" 1 'MISS +docs/review/features/orders.md — no "## Gotchas" section' bash "$check"
write_feature orders
rm -f docs/review/features/orders.md.bak
mv src/Orders.tsx src/OrderList.tsx
has "a path that moved"            1 'STALE +docs/review/features/orders.md — src/Orders.tsx does not exist' bash "$check"
mv src/OrderList.tsx src/Orders.tsx
rm docs/review/features/README.md
has "no index"                     1 'MISS +docs/review/features/README.md — no index' bash "$check"
rm docs/review/features/orders.md
has "no feature file"              1 'MISS +docs/review/features — no feature file' bash "$check"

echo "# the templates"
cp "$templates/verify.md" docs/review/verify.md
cp "$templates/verify-feature.md" docs/review/features/orders.md
echo "- [Orders](orders.md)" > docs/review/features/README.md
out=$(bash "$check" 2>&1)
sees   "an unfilled template is all placeholders" 'PLACEHOLDER +docs/review/verify.md' "$out"
sees   "in the feature file too"   'PLACEHOLDER +docs/review/features/orders.md:1' "$out"
misses "and has every section"     'MISS|EMPTY|NO COMMAND' "$out"

echo "# VERIFY_DIR"
mkdir -p ops/features
write_recipe && mv docs/review/verify.md ops/verify.md
write_feature orders && mv docs/review/features/orders.md ops/features/orders.md
echo "orders.md" > ops/features/README.md
has "reads another directory"      0 'ok — 1 features' env VERIFY_DIR=ops bash "$check"

finish
