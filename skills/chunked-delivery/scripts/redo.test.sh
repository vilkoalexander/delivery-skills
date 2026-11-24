#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
script="$here/redo.sh"
snapshot="$here/snapshot.sh"

exists() { if [ -e "$2" ]; then eq "$1" yes yes; else eq "$1" "missing: $2" yes; fi; }
absent() { if [ -e "$2" ]; then eq "$1" "still there: $2" gone; else eq "$1" gone gone; fi; }

# Two chunks of work nobody committed, with a file git does not track, and a fix round after the snapshot.
setup() {
  new_repo "$1"
  export WORKSPACE="$tmp/$1-ws"
  printf 'one\n' > a.txt; printf 'keep\n' > b.txt; printf '\0\1\2' > logo.bin
  commit_all
  bash "$snapshot" before 1 > /dev/null
  printf 'one\nchunk1\n' > a.txt; printf 'new1\n' > c1.txt
  bash "$snapshot" after 1 > /dev/null
  bash "$snapshot" before 2 > /dev/null
  before2=$(bash "$snapshot" base 2)
  printf 'one\nchunk1\nchunk2\n' > a.txt; printf 'new2\n' > "c 2.txt"; rm b.txt; printf '\3\4' > logo.bin
  bash "$snapshot" after 2 > /dev/null
  printf 'one\nchunk1\nchunk2\nfix\n' > a.txt
}
tree_now() { GIT_INDEX_FILE="$tmp/index.$RANDOM" bash -c 'git add -A . && git write-tree'; }

echo "# snapshots"
setup snap
sees  "the chunk diff has the new file"     '^\+new2$' "$(cat "$WORKSPACE/chunk-2.diff")"
misses "and nothing of the chunk before it" 'chunk1$'  "$(grep '^+' "$WORKSPACE/chunk-2.diff")"
eq    "nothing is staged"                   "$(git diff --cached --name-only)" ""
has   "a part holds only its paths"         0 "chunk-2-web.diff: 1 file changed" bash "$snapshot" part 2 web a.txt
has   "the final diff covers the run"       0 "final.diff: 5 files changed"      bash "$snapshot" final
sees  "from the first chunk on"             '^\+chunk1$' "$(cat "$WORKSPACE/final.diff")"
has   "stat counts the chunk alone"         0 "^2	0	a.txt$"                     bash "$snapshot" stat 2
has   "a rebuild keeps the first record"    0 "already has a before record"      bash "$snapshot" before 2
eq    "the record is unchanged"             "$(bash "$snapshot" base 2)" "$before2"
has   "no record"                           2 "no record of chunk-9-before"      bash "$snapshot" after 9
has   "no workspace"                        2 "WORKSPACE is not set"             env -u WORKSPACE bash "$snapshot" before 1
has   "bad input prints usage"              2 "snapshot.sh before N"             bash "$snapshot" before x

echo "# a later chunk"
setup later
has "exits 0 and says where the work went"  0 "discarded work saved in $WORKSPACE/chunk-2-discarded-1.diff" bash "$script" 2
eq  "keeps the earlier chunk"               "$(cat a.txt)" $'one\nchunk1'
exists "the new file of the earlier chunk stays" c1.txt
absent "the new file of this chunk goes"    "c 2.txt"
exists "the delete of this chunk is undone" b.txt
eq  "a binary file is back, byte for byte"  "$(git hash-object logo.bin)" "$(git rev-parse HEAD:logo.bin)"
eq  "the tree is the before tree"           "$(tree_now)" "$before2"
sees "the discarded patch has the fix round" '^\+fix$' "$(cat "$WORKSPACE/chunk-2-discarded-1.diff")"
eq  "nothing is staged"                     "$(git diff --cached --name-only)" ""
has "the discarded patch brings the work back" 0 "" git apply --binary "$WORKSPACE/chunk-2-discarded-1.diff"
eq  "all of it"                             "$(tail -1 a.txt) $(cat "c 2.txt")" "fix new2"
has "a second redo keeps the first patch"   0 "chunk-2-discarded-2.diff" bash "$script" 2

echo "# the first chunk"
setup first
has "exits 0"                               0 "back to the tree before chunk 1" bash "$script" 1
eq  "the tree is clean"                     "$(git status --porcelain)" ""

echo "# refusals leave the work in place"
setup refuse
want=$(tree_now)
has "no record of the chunk"                1 "no record of the tree before chunk 7" bash "$script" 7
echo 0000000000000000000000000000000000000000 > "$WORKSPACE/chunk-2-before.tree"
has "a tree that is gone"                   1 "is gone from the repository" bash "$script" 2
has "not a number"                          2 "usage: redo.sh N" bash "$script" chunk-2-before.diff
eq  "the work is as it was"                 "$(tree_now)" "$want"

echo "# a file git ignores"
setup ignored
echo "*.log" > .gitignore && commit_all
bash "$snapshot" before 3 > /dev/null
echo noise > build.log; echo more > d.txt
bash "$script" 3 > /dev/null
eq  "is left alone"                         "$(cat build.log)" noise
absent "and the new file goes"              d.txt

finish
