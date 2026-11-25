#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../../scripts/test-lib.sh"
source "$here/changes.sh"

listed() {
  changed_paths "${1:-}" | tr '\0' '\n' | sort | tr '\n' ' '
}

echo "# a repository with no commit"
new_repo fresh
printf 'one\n' > staged.ts && git add staged.ts
printf 'one\n' > loose.ts
eq "staged and untracked paths are listed" "$(listed)" "loose.ts staged.ts "
eq "a staged file is added whole" "$(added_lines "" staged.ts)" "staged.ts:1:one"

echo "# which paths changed"
new_repo project
mkdir -p src
printf 'a\n' > src/gone.ts
printf 'a\n' > src/old.test.ts
printf 'a\nb\n' > src/kept.ts
printf 'a\n' > "src/café.ts"
printf 'a\n' > "src/my file.ts"
commit_all

rm src/gone.ts
git mv src/old.test.ts src/renamed.ts
printf 'c\n' >> src/kept.ts && git add src/kept.ts
printf 'x\n' >> "src/café.ts"
printf 'y\n' >> "src/my file.ts"
printf 'n\n' > src/new.ts
out=$(listed)
sees   "a deleted file"                 "src/gone.ts "      "$out"
sees   "the old name of a renamed file" "src/old.test.ts "  "$out"
sees   "the new name of a renamed file" "src/renamed.ts "   "$out"
sees   "a change that is only staged"   "src/kept.ts "      "$out"
sees   "an untracked file"              "src/new.ts "       "$out"
sees   "a name that is not ASCII"       "src/café.ts "      "$out"
sees   "a name with a space"            "src/my file.ts "   "$out"
changed_paths nope..nowhere > /dev/null 2>&1
eq "a bad range is an error" "$?" 128

echo "# load_paths"
load_paths "" a.ts b.ts
eq "arguments win" "${paths[*]}" "a.ts b.ts"
load_paths "" < <(printf '%s\n' '"src/caf\303\251.ts"' 'src/kept.ts')
eq "stdin, with a path git quoted" "${paths[*]}" "src/café.ts src/kept.ts"
load_paths "" < /dev/null
sees "nothing given: the changed paths" "src/gone.ts" "${paths[*]}"
load_paths nope..nowhere < /dev/null 2> /dev/null
eq "a bad range returns 2" "$?" 2

echo "# added lines"
out=$(added_lines "" src/kept.ts "src/café.ts" "src/my file.ts" src/new.ts src/gone.ts)
sees   "a staged line, with its number"   "^src/kept.ts:3:c$"     "$out"
sees   "a name that is not ASCII"         "^src/café.ts:2:x$"     "$out"
sees   "a name with a space"              "^src/my file.ts:2:y$"  "$out"
sees   "an untracked file is added whole" "^src/new.ts:1:n$"      "$out"
misses "a deleted file adds nothing"      "gone"                  "$out"
printf 'p\n++ plus signs\nq\n' > src/plus.ts
eq "an added line that starts with ++" "$(added_lines "" src/plus.ts | sed -n 2p)" "src/plus.ts:2:++ plus signs"
printf '\000\001binary' > src/blob.bin
eq "an untracked binary adds nothing" "$(added_lines "" src/blob.bin)" ""
before=$(git ls-files -s | shasum)
worktree_tree > /dev/null
eq "the real index is not touched" "$(git ls-files -s | shasum)" "$before"
base=$(worktree_tree)
printf 'later\n' >> src/new.ts
eq "DELIVERY_BASE: only what came after it" "$(DELIVERY_BASE=$base added_lines "" src/new.ts src/kept.ts)" "src/new.ts:2:later"
eq "DELIVERY_BASE: the paths after it" "$(DELIVERY_BASE=$base changed_paths | tr '\0' ' ')" "src/new.ts "
added_lines nope..nowhere src/kept.ts > /dev/null 2>&1
eq "a bad range returns 2" "$?" 2
commit_all second
eq "a range" "$(added_lines HEAD~1..HEAD src/new.ts | sed -n 1p)" "src/new.ts:1:n"

echo "# is it a test"
for path in src/a.spec.ts src/a.test.tsx app.e2e-spec.ts src/__tests__/a.ts src/__snapshots__/a.snap \
  src/testFixtures/Fx.java src/test/java/A.java e2e/login.ts tests/a.py UserServiceTest.java UserIT.kt fixtures/a.json internal/cart/handler_test.go; do
  if is_test_path "$path"; then ok "test: $path"; else nok "test: $path" "read as source"; fi
done
for path in src/contest.ts src/latest/a.ts src/attest.service.ts src/a.ts Protest.java src/testing.ts internal/cart/handler.go internal/latest_test/go.go; do
  if is_test_path "$path"; then nok "source: $path" "read as a test"; else ok "source: $path"; fi
done

echo "# patterns"
has "a pattern that compiles"         0 ""                        valid_ere SECRET_ALLOW '^src/'
has "a pattern that does not compile" 2 "SECRET_ALLOW is not a valid pattern" valid_ere SECRET_ALLOW '('

echo "# an edit in the same second as the commit, with the same size"
new_repo racy
same=0
for round in 1 2 3 4 5 6 7 8; do
  echo one > r.txt && commit_all
  echo two > r.txt
  [ "$(worktree_tree)" = "$(git rev-parse HEAD^{tree})" ] && same=$((same + 1))
done
eq "is in the tree every time" "$same" 0

finish
