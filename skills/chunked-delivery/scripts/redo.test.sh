#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/redo.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1" "got '$2', wanted '$3'"; fi; }
exists() { if [ -e "$2" ]; then ok "$1"; else nok "$1" "$2 missing"; fi; }
absent() { if [ -e "$2" ]; then nok "$1" "$2 still there"; else ok "$1"; fi; }

# Two chunks of uncommitted work, plus a fix round made after the after-snapshot.
setup() {
  repo="$tmp/$1"; ws="$tmp/$1-ws"
  mkdir -p "$repo" "$ws"; cd "$repo" || exit 1
  git init -q
  printf 'one\n' > a.txt; printf 'keep\n' > b.txt
  git add . && git -c user.name=t -c user.email=t@t commit -qm base

  git diff > "$ws/chunk-1-before.diff"
  printf 'one\nchunk1\n' > a.txt; printf 'new1\n' > c1.txt; git add -N c1.txt
  git diff > "$ws/chunk-1.diff"

  git diff > "$ws/chunk-2-before.diff"
  printf 'one\nchunk1\nchunk2\n' > a.txt; printf 'new2\n' > c2.txt; rm b.txt; git add -N c2.txt
  git diff > "$ws/chunk-2.diff"
  printf 'one\nchunk1\nchunk2\nfix\n' > a.txt
}

setup later
bash "$script" "$ws/chunk-2-before.diff" >/dev/null 2>&1; eq "later chunk exits 0" "$?" 0
eq "keeps the earlier chunk" "$(cat a.txt)" $'one\nchunk1'
exists "earlier chunk's new file stays" c1.txt
absent "this chunk's new file goes" c2.txt
exists "this chunk's delete is undone" b.txt
eq "tree equals the before snapshot" "$(git diff)" "$(cat "$ws/chunk-2-before.diff")"
if grep -q '^+fix$' "$ws/chunk-2-discarded.diff"; then ok "discarded work saved with the fix round"; else nok "discarded work saved" "no fix line"; fi

setup first
bash "$script" "$ws/chunk-1-before.diff" >/dev/null 2>&1; eq "first chunk exits 0" "$?" 0
eq "empty before snapshot gives a clean tree" "$(git diff)" ""
eq "base content back" "$(cat a.txt)" one
absent "first chunk's new file goes" c1.txt

setup corrupt
printf 'this is not a patch\n' > "$ws/chunk-2-before.diff"
want=$(git diff)
if bash "$script" "$ws/chunk-2-before.diff" >/dev/null 2>"$tmp/err"; then nok "bad snapshot" "exited 0"; else ok "bad snapshot refused"; fi
eq "bad snapshot leaves work in place" "$(git diff)" "$want"

setup missing
want=$(git diff)
if bash "$script" "$ws/nope-before.diff" >/dev/null 2>&1; then nok "missing snapshot" "exited 0"; else ok "missing snapshot refused"; fi
eq "missing snapshot leaves work in place" "$(git diff)" "$want"

setup misnamed
want=$(git diff)
cp "$ws/chunk-2.diff" "$ws/chunk-2-after.txt"
if bash "$script" "$ws/chunk-2-after.txt" >/dev/null 2>&1; then nok "wrong file" "exited 0"; else ok "only a -before.diff is accepted"; fi
eq "wrong file leaves work in place" "$(git diff)" "$want"

setup untracked
printf 'stray\n' > stray.txt
want=$(git diff)
if bash "$script" "$ws/chunk-2-before.diff" >/dev/null 2>"$tmp/err"; then ok "untracked file does not block"; else nok "untracked" "$(cat "$tmp/err")"; fi
eq "untracked file is left alone" "$(cat stray.txt)" stray
if grep -q 'stray.txt' "$tmp/err"; then ok "untracked file is named"; else nok "untracked named" "$(cat "$tmp/err")"; fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" = 0 ]
