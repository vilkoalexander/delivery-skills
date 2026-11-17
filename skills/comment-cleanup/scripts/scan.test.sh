#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

new_repo project
mkdir -p src node_modules/dep
cat > src/a.ts <<'TS'
// added retry for the flaky call
// see https://example.com/x
// ---------------
// 1. load the user
// const old = 1;
// eslint-disable-next-line
// eslint-disable-next-line no-console -- cli output
// TODO tidy
/** @param {string} name */
const a = 1; // trailing why
const url = "http://x//y";
TS
echo '// one comment' > src/b.ts
echo '// vendored'    > node_modules/dep/index.js
echo '// generated'   > src/types.d.ts
echo '// not code'    > notes.md
git add -A


out=$(bash "$scan")
eq   "exits 0"                               "$?" 0
sees "counts human and tool comments apart"  '^9 to judge in 2 files; 2 lines a tool reads, left alone$' "$out"
sees "densest file first"                    '^ *8 src/a.ts$' "$(under 'Per file' | head -1)"
misses "skips node_modules, .d.ts, non-code" 'node_modules|types\.d\.ts|notes\.md' "$out"
eq   "change description"                    "$(under 'Describes the change' | cut -d: -f1,2)" "src/a.ts:1"
eq   "link"                                  "$(under 'Names the outside world' | cut -d: -f1,2)" "src/a.ts:2"
eq   "banner"                                "$(under 'Banner' | cut -d: -f1,2)" "src/a.ts:3"
eq   "step number"                           "$(under 'Step number' | cut -d: -f1,2)" "src/a.ts:4"
eq   "commented-out code"                    "$(under 'Looks like commented-out code' | cut -d: -f1,2)" "src/a.ts:5"
eq   "suppression without a reason only"     "$(under 'Suppression with no reason' | cut -d: -f1,2)" "src/a.ts:6"
eq   "todo"                                  "$(under 'TODO' | cut -d: -f1,2)" "src/a.ts:8"
eq   "jsdoc types in typescript"             "$(under 'JSDoc repeating' | cut -d: -f1,2)" "src/a.ts:9"
misses "a URL is not a trailing comment"     'src/a.ts:11' "$out"

echo "# scope"
has   "a path limits the scan"        0 '^1 to judge in 1 files' bash "$scan" src/b.ts
has   "COMMENT_TOP limits the table"  0 '\(top 1\)'              env COMMENT_TOP=1 bash "$scan"
has   "COMMENT_EXT picks extensions"  0 'no source files in scope' env COMMENT_EXT=py bash "$scan"
lacks "an untracked file is not scanned" 'c\.ts' bash -c "echo '// new' > src/c.ts; bash '$scan'"

echo "# outside git"
mkdir -p "$tmp/plain/src" && cd "$tmp/plain"
echo '// TODO later' > src/x.js
has "falls back to find" 0 'src/x.js:1:// TODO later' env GIT_CEILING_DIRECTORIES="$tmp" bash "$scan"

finish
