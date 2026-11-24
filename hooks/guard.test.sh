#!/usr/bin/env bash
# Tests for hooks/guard.sh and skills/chunked-delivery/scripts/run.sh.
#
#   bash hooks/guard.test.sh
#
# Runs against a throwaway git repo and a private marker dir; touches nothing
# under ~/.claude.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
guard="$root/hooks/guard.sh"
run="$root/skills/chunked-delivery/scripts/run.sh"
tmp=$(mktemp -d)
node "$root/skills/delivery-pipeline/scripts/dep-vet.fixture.mjs" > "$tmp/port" & server=$!
trap 'kill $server 2>/dev/null; wait $server 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
export DEP_REGISTRY="http://127.0.0.1:$(cat "$tmp/port")" DEP_OSV="http://127.0.0.1:$(cat "$tmp/port")"

export DELIVERY_RUN_DIR="$tmp/runs" DELIVERY_EVENTS_DIR="$tmp/events" DELIVERY_LOG="$tmp/log.jsonl"
unset DELIVERY_EVIDENCE_DIR
repo="$tmp/repo"
mkdir -p "$repo/src" && git -C "$repo" init -q
export CLAUDE_PROJECT_DIR="$repo"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1"; printf '%s\n' "$2" | sed 's/^/       /'; }

# hook NAME EXPECTED_EXIT JSON — runs guard.sh with JSON on stdin
hook() {
  local name=$1 want=$2 json=$3 out err code
  out=$(printf '%s' "$json" | bash "$guard" 2>"$tmp/err"); code=$?
  err=$(cat "$tmp/err")
  if [ "$code" = "$want" ]; then ok "$name"; else nok "$name" "exit $code, wanted $want"$'\n'"stdout: $out"$'\n'"stderr: $err"; fi
  last_err=$err
}
bash_json() { # command [agent_type]
  local cmd=$1 agent=${2:-}
  jq -cn --arg cwd "$repo" --arg cmd "$cmd" --arg agent "$agent" '
    {session_id:"s1", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"Bash",
     tool_input:{command:$cmd}}
    + (if $agent != "" then {agent_id:"a1", agent_type:$agent} else {} end)'
}
read_json() { # file_path [agent_type]
  local f=$1 agent=${2:-}
  jq -cn --arg cwd "$repo" --arg f "$f" --arg agent "$agent" '
    {session_id:"s1", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"Read",
     tool_input:{file_path:$f}}
    + (if $agent != "" then {agent_id:"a1", agent_type:$agent} else {} end)'
}
stop_json() { # transcript last_message [stop_hook_active]
  local t=$1 msg=$2 active=${3:-false}
  jq -cn --arg cwd "$repo" --arg t "$t" --arg msg "$msg" --argjson active "$active" '
    {session_id:"s1", cwd:$cwd, hook_event_name:"SubagentStop", agent_id:"a1",
     agent_type:"general-purpose", agent_transcript_path:$t,
     last_assistant_message:$msg, stop_hook_active:$active}'
}

# ---------------------------------------------------------------- run.sh
out=$(bash "$run" status 2>&1); code=$?
[ "$code" = 1 ] && ok "status: no run is exit 1" || nok "status: no run is exit 1" "$out"
out=$(cd "$repo/src" && bash "$run" start 2>&1); code=$?
[ "$code" = 0 ] && ok "start from a subdir" || nok "start from a subdir" "$out"
[ "$(ls "$DELIVERY_RUN_DIR" | wc -l | tr -d ' ')" = 1 ] && ok "one marker" || nok "one marker" "$(ls "$DELIVERY_RUN_DIR")"
out=$(cd "$repo" && bash "$run" start 2>&1); code=$?
[ "$code" = 2 ] && [ "$(ls "$DELIVERY_RUN_DIR" | wc -l | tr -d ' ')" = 1 ] && ok "a second start is refused" || nok "a second start is refused" "$out"
out=$(cd "$repo" && bash "$run" status 2>&1); code=$?
[ "$code" = 0 ] && grep -qF "$repo" <<< "$out" && ok "status names the repo" || nok "status names the repo" "$out"

# ---------------------------------------------------------------- git writes, run active
hook "commit blocked"            2 "$(bash_json 'git commit -m "x"')"
grep -qi "run.sh stop" <<< "$last_err" && ok "reason says how to end the run" || nok "reason says how to end the run" "$last_err"
hook "add blocked"               2 "$(bash_json 'git add .')"
grep -q "snapshot.sh" <<< "$last_err" && ok "add: the reason names snapshot.sh" || nok "add: the reason names snapshot.sh" "$last_err"
hook "add -N blocked"            2 "$(bash_json 'git add -N .')"
hook "push after tests blocked"  2 "$(bash_json 'npm test && git push origin HEAD')"
hook "push via ; blocked"        2 "$(bash_json 'echo done; git push')"
hook "stash blocked"             2 "$(bash_json 'git stash')"
hook "stash pop blocked"         2 "$(bash_json 'git stash pop')"
hook "stash list allowed"        0 "$(bash_json 'npm test; git stash list | head -1 >/dev/null')"
hook "stash show allowed"        0 "$(bash_json 'git stash show -p')"
hook "reset --hard blocked"      2 "$(bash_json 'git reset --hard HEAD')"
grep -q "redo.sh N" <<< "$last_err" && ok "reset: the reason names redo.sh" || nok "reset: the reason names redo.sh" "$last_err"
hook "reset blocked"             2 "$(bash_json 'git reset')"
hook "checkout -- blocked"       2 "$(bash_json 'git checkout -- src/a.ts')"
hook "checkout of a path blocked" 2 "$(bash_json 'git checkout HEAD src/a.ts')"
hook "checkout -b blocked"       2 "$(bash_json 'git checkout -b feature/x')"
hook "switch blocked"            2 "$(bash_json 'git switch main')"
hook "restore blocked"           2 "$(bash_json 'git restore src/a.ts')"
hook "clean blocked"             2 "$(bash_json 'git clean -fd')"
hook "merge blocked"             2 "$(bash_json 'git merge main')"
hook "rebase blocked"            2 "$(bash_json 'git rebase main')"
hook "apply blocked"             2 "$(bash_json 'git apply -R /tmp/w/chunk-2-discarded-1.diff')"
hook "update-ref blocked"        2 "$(bash_json 'git update-ref refs/heads/main HEAD~1')"
hook "commit-tree blocked"       2 "$(bash_json 'git commit-tree HEAD^{tree} -m x')"
hook "branch -D blocked"         2 "$(bash_json 'git branch -D feature/x')"
hook "branch create blocked"     2 "$(bash_json 'git branch feature/x')"
hook "tag create blocked"        2 "$(bash_json 'git tag v1')"
hook "remote add blocked"        2 "$(bash_json 'git remote add up https://example.test/x.git')"
hook "config set blocked"        2 "$(bash_json 'git config user.name x')"
hook "git -C commit blocked"     2 "$(bash_json "git -C $repo commit -am x")"
hook "env prefix commit blocked" 2 "$(bash_json 'GIT_AUTHOR_NAME=x git commit -m y')"
hook "subagent commit blocked"   2 "$(bash_json 'git commit -m x' general-purpose)"

hook "status allowed"            0 "$(bash_json 'git status --short')"
hook "log allowed"               0 "$(bash_json 'git log --oneline -5')"
hook "diff allowed"              0 "$(bash_json 'git diff --stat')"
hook "apply --numstat allowed"   0 "$(bash_json 'git apply --numstat /tmp/w/chunk-2.diff')"
hook "branch list allowed"       0 "$(bash_json 'git branch -a --contains HEAD')"
hook "branch --show-current allowed" 0 "$(bash_json 'git branch --show-current')"
hook "tag list allowed"          0 "$(bash_json 'git tag -l "v*"')"
hook "remote -v allowed"         0 "$(bash_json 'git remote -v')"
hook "config --get allowed"      0 "$(bash_json 'git config --get user.name')"
hook "--no-pager log allowed"    0 "$(bash_json 'git --no-pager log -1 --format=%H')"
hook "commit --dry-run allowed"  0 "$(bash_json 'git commit --dry-run')"
hook "git --version allowed"     0 "$(bash_json 'git --version')"
hook "the snapshot script runs"  0 "$(bash_json 'WORKSPACE=/tmp/w bash skills/chunked-delivery/scripts/snapshot.sh after 2')"

# Text that only looks like a git write.
hook "grep for commit allowed"   0 "$(bash_json 'grep -rn "git commit" docs/')"
hook "echo of a git write allowed" 0 "$(bash_json 'echo "then run: git push && git merge main"')"
hook "log --grep with an operator in quotes" 0 "$(bash_json "git log --grep='fix; git push' --oneline")"
hook "a comment is not a command" 0 "$(bash_json 'ls # git commit later')"
hook "a heredoc body is not a command" 0 "$(bash_json $'cat <<\'EOF\'\ngit commit -m x\nEOF')"
hook "a file named like a subcommand" 0 "$(bash_json 'git diff -- commit.ts push.ts')"

# Every way to wrap or group a command.
wrapped() { hook "wrapped: $1" 2 "$(bash_json "$1")"; }
wrapped 'command git commit -m x'
wrapped 'env GIT_DIR=.git git commit -m x'
wrapped 'env -i git push'
wrapped 'sudo -u dev git push'
wrapped 'exec git push'
wrapped 'nohup git push &'
wrapped 'time git commit -m x'
wrapped 'timeout 30 git push'
wrapped '/usr/bin/git commit -m x'
wrapped '\git commit -m x'
wrapped '"git" commit -m x'
wrapped "g'i't commit -m x"
wrapped 'git -c user.name=x commit -m y'
wrapped 'git --git-dir=.git --work-tree=. commit -m y'
wrapped "bash -c 'git commit -m x'"
wrapped "sh -ec 'cd src && git push'"
wrapped 'bash -lc "git add . && git commit -m x"'
wrapped 'eval "git commit -m x"'
wrapped '(git commit -m x)'
wrapped '{ git commit -m x; }'
wrapped 'echo $(git stash)'
wrapped 'echo "$(git stash)"'
wrapped 'echo `git stash`'
wrapped 'if true; then git commit -m x; fi'
wrapped 'for f in a b; do git add "$f"; done'
wrapped 'true || git push'
wrapped 'ls | xargs git add'
wrapped 'ls | xargs -n 1 git add'
wrapped 'find . -name "*.ts" -exec git add {} +'
wrapped $'ls\ngit commit -m x'
wrapped $'cat <<EOF\n$(git stash)\nEOF'
wrapped 'diff <(git stash show) a.txt && git stash drop'
hook "a command that does not parse and names git" 2 "$(bash_json 'git commit -m "unfinished')"
grep -q "plain command" <<< "$last_err" && ok "reason asks for a plain command" || nok "reason asks for a plain command" "$last_err"
hook "a command that does not parse, no git" 0 "$(bash_json 'echo "unfinished')"
hook "a name built at run time, with git in the text" 2 "$(bash_json 'g=git; $g commit -m x')"

# ---------------------------------------------------------------- PRs, run active
hook "gh pr create blocked"      2 "$(bash_json 'gh pr create --fill')"
hook "gh pr merge blocked"       2 "$(bash_json 'gh pr merge 12 --squash')"
hook "gh pr close blocked"       2 "$(bash_json 'gh pr close 12')"
hook "gh pr edit blocked"        2 "$(bash_json 'gh pr edit 12 --title x')"
hook "gh pr ready blocked"       2 "$(bash_json 'gh pr ready')"
hook "gh pr review blocked"      2 "$(bash_json 'gh pr review --approve')"
hook "gh -R pr create blocked"   2 "$(bash_json 'gh -R o/r pr create --fill')"
hook "gh release create blocked" 2 "$(bash_json 'gh release create v1')"
hook "gh api POST pulls blocked" 2 "$(bash_json 'gh api -X POST repos/o/r/pulls -f title=x')"
hook "gh api with a field is a POST" 2 "$(bash_json 'gh api repos/o/r/pulls -f title=x -f head=b')"
hook "gh api PUT merge blocked"  2 "$(bash_json 'gh api --method PUT repos/o/r/pulls/3/merge')"
hook "gh pr view allowed"        0 "$(bash_json 'gh pr view 12 --json title')"
hook "gh pr list allowed"        0 "$(bash_json 'gh pr list')"
hook "gh api GET pulls allowed"  0 "$(bash_json 'gh api repos/o/r/pulls')"
hook "echo of gh pr create allowed" 0 "$(bash_json 'echo "gh pr create"')"

# ---------------------------------------------------------------- package fetches, run active
hook "install of a known package"        0 "$(bash_json 'npm install lodash')"
hook "install of an unknown name blocked" 2 "$(bash_json 'npm install lodahs')"
grep -q "not in the registry" <<< "$last_err" && grep -q "DEP_VET_ALLOW" <<< "$last_err" && ok "reason names the package and the way out" || nok "reason names the package and the way out" "$last_err"
hook "npm i -D young package blocked"    2 "$(bash_json 'npm i -D young-pkg')"
hook "pnpm add fresh version blocked"    2 "$(bash_json 'pnpm add --filter web fresh-version')"
hook "pnpm add older pin allowed"        0 "$(bash_json 'pnpm add --filter web fresh-version@1.0.0')"
hook "yarn add malware blocked"          2 "$(bash_json 'yarn add evil-pkg')"
hook "bun add after cd blocked"          2 "$(bash_json 'cd apps/web && bun add lodahs')"
hook "subagent install blocked"          2 "$(bash_json 'npm install lodahs' general-purpose)"
hook "install script only flags"         0 "$(bash_json 'npm install has-script')"
hook "npm -w value is not a package"     0 "$(bash_json 'npm install lodash -w not-a-package')"
hook "npm ci allowed"                    0 "$(bash_json 'npm ci')"
hook "npm run allowed"                   0 "$(bash_json 'npm run lodahs')"
hook "npm uninstall allowed"             0 "$(bash_json 'npm uninstall lodahs')"
hook "npx unknown package blocked"       2 "$(bash_json 'npx lodahs --help')"
hook "npx -p unknown package blocked"    2 "$(bash_json 'npx -p lodahs some-bin')"
hook "pnpm dlx unknown blocked"          2 "$(bash_json 'pnpm dlx lodahs')"
hook "npx --no-install allowed"          0 "$(bash_json 'npx --no-install lodahs')"
mkdir -p "$repo/node_modules/.bin" && touch "$repo/node_modules/.bin/lodahs"
hook "npx of a local bin allowed"        0 "$(bash_json 'npx lodahs --help')"
rm -rf "$repo/node_modules"
hook "bare install, clean package.json"  0 "$(bash_json 'npm install')"
echo '{"dependencies":{"lodahs":"^1.0.0"}}' > "$repo/package.json"
hook "bare install, unknown dep blocked" 2 "$(bash_json 'pnpm install')"
hook "bare yarn, unknown dep blocked"    2 "$(bash_json 'yarn')"
rm -f "$repo/package.json"
DEP_VET_ALLOW='^lodahs$' hook "allowed name passes" 0 "$(bash_json 'npm install lodahs')"
DEP_VET=off hook "DEP_VET=off passes"    0 "$(bash_json 'npm install lodahs')"
DEP_REGISTRY="http://127.0.0.1:1" hook "a registry that does not answer blocks" 2 "$(bash_json 'npm install lodahs')"
grep -q "could not be checked" <<< "$last_err" && grep -q "DEP_VET=off" <<< "$last_err" && ok "reason says why and the way out" || nok "reason says why and the way out" "$last_err"
hook "npm in is install"                 2 "$(bash_json 'npm in lodahs')"
hook "npm exec unknown blocked"          2 "$(bash_json 'npm exec lodahs')"
hook "npm create fetches create-<name>"  2 "$(bash_json 'npm create lodahs')"
grep -q "create-lodahs" <<< "$last_err" && ok "reason names create-lodahs" || nok "reason names create-lodahs" "$last_err"
hook "npm update of an unknown name"     2 "$(bash_json 'npm update lodahs')"
hook "yarn workspace add blocked"        2 "$(bash_json 'yarn workspace web add lodahs')"
hook "install inside bash -c blocked"    2 "$(bash_json "bash -c 'npm install lodahs'")"
hook "env before the install blocked"    2 "$(bash_json 'CI=1 command npm install lodahs')"
hook "a git spec is not fetched"         2 "$(bash_json 'npm install git+https://example.test/x.git')"
grep -q "git or tarball spec" <<< "$last_err" && ok "reason says what the spec is" || nok "reason says what the spec is" "$last_err"
hook "a user/repo spec is not fetched"   2 "$(bash_json 'npm install someone/thing')"
hook "a tarball url is not fetched"      2 "$(bash_json 'pnpm add https://example.test/x.tgz')"
hook "a local path is not a fetch"       0 "$(bash_json 'npm install ./packages/ui')"
DEP_VET_ALLOW='^@types/' hook "a scoped name is a registry name" 0 "$(bash_json 'npm install @types/lodash')"
hook "echo of an install allowed"        0 "$(bash_json 'echo "npm install lodahs"')"

# ---------------------------------------------------------------- snapshot read, run active
hook "controller reading snapshot blocked" 2 "$(read_json /tmp/w/chunk-3.diff)"
hook "controller reading before-snapshot blocked" 2 "$(read_json /tmp/w/chunk-3-before.diff)"
hook "reviewer reading snapshot allowed"   0 "$(read_json /tmp/w/chunk-3.diff delivery-skills:reviewer)"
hook "controller reading source allowed"   0 "$(read_json "$repo/src/a.ts")"
hook "controller cat snapshot blocked"     2 "$(bash_json 'cat /tmp/w/chunk-3.diff')"
hook "controller sed -n snapshot blocked"  2 "$(bash_json "sed -n '1,80p' /tmp/w/chunk-3-before.diff")"
hook "controller wc snapshot allowed"      0 "$(bash_json 'wc -l /tmp/w/chunk-3.diff')"
hook "controller writing snapshot allowed" 0 "$(bash_json 'git diff > /tmp/w/chunk-3.diff')"
hook "controller grep of a snapshot blocked" 2 "$(bash_json 'grep -n TODO /tmp/w/chunk-3.diff')"
hook "controller snapshot on stdin blocked" 2 "$(bash_json 'python3 -c "import sys; print(sys.stdin.read())" < /tmp/w/chunk-3-web.diff')"
hook "controller cat in bash -c blocked"   2 "$(bash_json "bash -c 'cat /tmp/w/chunk-3.diff'")"
hook "a file that only starts like one"    0 "$(bash_json 'cat /tmp/w/chunk-3.diff.md')"
hook "controller snapshot stat allowed"    0 "$(bash_json 'ls -l /tmp/w/chunk-3.diff')"
hook "subagent cat snapshot allowed"       0 "$(bash_json 'cat /tmp/w/chunk-3.diff' general-purpose)"

# ---------------------------------------------------------------- reviewer is read-only (run or not)
for agent in delivery-skills:reviewer delivery-skills:verifier; do
  hook "$agent: sed -i blocked"        2 "$(bash_json "sed -i 's/a/b/' src/a.ts" $agent)"
  hook "$agent: perl -pi blocked"      2 "$(bash_json "perl -pi -e 's/a/b/' src/a.ts" $agent)"
  hook "$agent: redirect blocked"      2 "$(bash_json 'echo hi > notes.txt' $agent)"
  hook "$agent: redirect in bash -c blocked" 2 "$(bash_json "bash -c 'echo hi > notes.txt'" $agent)"
  hook "$agent: heredoc to a file blocked" 2 "$(bash_json "cat > probe.cjs <<'EOF'" $agent)"
  hook "$agent: arrow function is no redirect" 0 "$(bash_json 'node -e "const ids = rows.map((row) => row.id); console.log(ids.filter(id=>id))"' $agent)"
  hook "$agent: a quoted > is no redirect" 0 "$(bash_json "grep -n 'a > b' src/a.ts" $agent)"
  hook "$agent: stash list allowed"    0 "$(bash_json 'git stash list' $agent)"
  hook "$agent: stash drop blocked"    2 "$(bash_json 'git stash drop' $agent)"
  hook "$agent: append blocked"        2 "$(bash_json 'echo hi >> notes.txt' $agent)"
  hook "$agent: tee blocked"           2 "$(bash_json 'cat a | tee b' $agent)"
  hook "$agent: rm blocked"            2 "$(bash_json 'rm -rf dist' $agent)"
  hook "$agent: mv blocked"            2 "$(bash_json 'mv a b' $agent)"
  hook "$agent: install blocked"       2 "$(bash_json 'npm install left-pad' $agent)"
  hook "$agent: eslint --fix blocked"  2 "$(bash_json 'npx eslint --fix src' $agent)"
  hook "$agent: git apply blocked"     2 "$(bash_json 'git apply fix.diff' $agent)"
  hook "$agent: git add blocked"       2 "$(bash_json 'git add -N .' $agent)"
  hook "$agent: does not parse blocked" 2 "$(bash_json 'echo "unfinished' $agent)"
  hook "$agent: devnull allowed"       0 "$(bash_json 'npm test > /dev/null 2>&1' $agent)"
  hook "$agent: stderr merge allowed"  0 "$(bash_json 'tsc --noEmit 2>&1 | head' $agent)"
  hook "$agent: grep allowed"          0 "$(bash_json 'grep -rn "useEffect" src | sort' $agent)"
  hook "$agent: cat diff allowed"      0 "$(bash_json 'cat /tmp/w/chunk-3.diff' $agent)"
  hook "$agent: scan script allowed"   0 "$(bash_json 'bash scripts/scan.sh src/a.tsx' $agent)"
  hook "$agent: a log under /tmp allowed" 0 "$(bash_json 'npm run start:dev > /tmp/verify-app/dev.log 2>&1 &' $agent)"
  hook "$agent: a log under \$TMPDIR allowed" 0 "$(bash_json 'mkdir -p "$TMPDIR/verify-app" && npm run dev > "$TMPDIR/verify-app/dev.log"' $agent)"
  hook "$agent: cp into the temp directory allowed" 0 "$(bash_json 'cp shot.png /tmp/verify-app/shot.png' $agent)"
  hook "$agent: cp into the checkout blocked" 2 "$(bash_json 'cp /tmp/verify-app/shot.png docs/shot.png' $agent)"
  hook "$agent: .. out of the temp directory blocked" 2 "$(bash_json "echo x > /tmp/../$repo/a.txt" $agent)"
  DELIVERY_EVIDENCE_DIR="$tmp/evidence" hook "$agent: the evidence directory allowed" 0 "$(bash_json "curl -s localhost:3000 | tee $tmp/evidence/body.json" $agent)"
done
hook "verifier may run the app"   0 "$(bash_json 'npm run start:dev & sleep 3; curl -s localhost:3000/health' delivery-skills:verifier)"
hook "verifier may run tests"     0 "$(bash_json 'npx jest src/orders 2>&1 | tail -5' delivery-skills:verifier)"
hook "implementer sed -i allowed" 0 "$(bash_json "sed -i 's/a/b/' src/a.ts" general-purpose)"
hook "a reviewer of another plugin is not the seat" 0 "$(bash_json 'echo hi > notes.txt' other-plugin:reviewer)"
hook "nor is an agent only named reviewer" 0 "$(bash_json 'echo hi > notes.txt' reviewer)"

# ---------------------------------------------------------------- run off: git is free again
out=$(cd "$repo" && bash "$run" stop 2>&1); code=$?
[ "$code" = 0 ] && [ -z "$(ls -A "$DELIVERY_RUN_DIR")" ] && ok "stop removes the marker" || nok "stop removes the marker" "$out"
hook "commit allowed with no run"        0 "$(bash_json 'git commit -m x')"
hook "snapshot read allowed with no run" 0 "$(read_json /tmp/w/chunk-3.diff)"
hook "unknown install allowed with no run" 0 "$(bash_json 'npm install lodahs')"
hook "reviewer still read-only"          2 "$(bash_json 'rm -rf dist' delivery-skills:reviewer)"

# ---------------------------------------------------------------- SubagentStop: Proof block
impl_t="$tmp/impl.jsonl"
cat > "$impl_t" <<'EOF'
{"type":"user","message":{"role":"user","content":"Implement task 2. Your report ends with:\n## Proof\n- ran: ...\n## Reuse\n- reused: ..."}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}
EOF
arr_t="$tmp/arr.jsonl"
cat > "$arr_t" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Implement task 3. End with the ## Proof block."}]}}
EOF
explore_t="$tmp/explore.jsonl"
cat > "$explore_t" <<'EOF'
{"type":"user","message":{"role":"user","content":"Find where OrdersController is guarded."}}
EOF
full_report=$'Done.\n\n## Proof\n- ran: npm test — 12 passed\n- not verified: nothing\n\n## Reuse\n- reused: nothing'

hook "no run: a report without Proof passes" 0 "$(stop_json "$impl_t" 'Done, all tests pass.')"
(cd "$repo" && bash "$run" start > /dev/null && bash "$run" mode long > /dev/null)
hook "a reviewer is not asked for Proof" 0 "$(stop_json "$impl_t" 'Done.' | jq -c '.agent_type = "delivery-skills:reviewer"')"
hook "report without Proof held"       2 "$(stop_json "$impl_t" 'Done, all tests pass.')"
grep -q "## Proof" <<< "$last_err" && ok "reason names the block" || nok "reason names the block" "$last_err"
hook "report missing Reuse held"       2 "$(stop_json "$impl_t" $'Done.\n## Proof\n- ran: npm test — ok\n- not verified: nothing')"
hook "full report passes"              0 "$(stop_json "$impl_t" "$full_report")"
hook "array-content prompt enforced"   2 "$(stop_json "$arr_t" 'Done.')"
hook "explore agent not held"          0 "$(stop_json "$explore_t" 'It is guarded at class level.')"
handback_t="$tmp/handback.jsonl"
{
  cat "$impl_t"
  jq -cn --arg report "$full_report" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:"first try, no blocks"}}]}}'
  echo 'a line cut off in the mid'
  jq -cn --arg report "$full_report" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:$report}}]}}'
} > "$handback_t"
partial_t="$tmp/partial.jsonl"
{
  cat "$impl_t"
  jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:"Done.\n## Proof\n- ran: npm test"}}]}}'
} > "$partial_t"
hook "report in a hand-back call passes"  0 "$(stop_json "$handback_t" '' | jq -c 'del(.last_assistant_message)')"
hook "hand-back missing Reuse held"       2 "$(stop_json "$partial_t" '' | jq -c 'del(.last_assistant_message)')"
hook "second stop passes through"      0 "$(stop_json "$impl_t" 'Done.' true)"
hook "missing transcript passes"       0 "$(stop_json "$tmp/nope.jsonl" 'Done.')"

# ---------------------------------------------------------------- chunk tasks
task_json() { # subject
  jq -cn --arg cwd "$repo" --arg subject "$1" '
    {session_id:"s1", cwd:$cwd, hook_event_name:"TaskCompleted", task_id:"1", task_subject:$subject}'
}
scripts="$root/skills/chunked-delivery/scripts"
reported() { # chunk — the marks of a low-risk chunk up to its report
  (cd "$repo" && for phase in implement gate report; do bash "$scripts/mark.sh" phase=$phase chunk="$1" of=3 risk=low; done)
}
log_decision() { # chunk decision
  (cd "$repo" && bash "$scripts/run-log.sh" add plan=p.md chunk="$1" risk=low \
    mode=long implementer=haiku reviewer=none fix_rounds=0 findings=0 verify=none decision="$2")
}

hook "chunk with no report held"           2 "$(task_json 'Chunk 1/3 — schema [high]')"
grep -q "Chunk 1 has no accepted decision" <<< "$last_err" && ok "reason names the chunk" || nok "reason names the chunk" "$last_err"
hook "other task completes"                0 "$(task_json 'Update the README')"
reported 1; reported 2
hook "reported chunk with no line held"    2 "$(task_json 'Chunk 1/3 — schema [high]')"
log_decision 1 accepted
log_decision 2 rejected
hook "accepted chunk completes"            0 "$(task_json 'Chunk 1/3 — schema [high]')"
hook "rejected chunk held"                 2 "$(task_json 'Chunk 2/3 — add login [low]')"
reported 2
hook "a rebuilt chunk waits for its own decision" 2 "$(task_json 'Chunk 2/3 — add login [low]')"
log_decision 2 edited
hook "chunk edited after a redo completes" 0 "$(task_json 'Chunk 2/3 — add login [low]')"
(cd "$repo" && bash "$run" stop > /dev/null)
hook "no run: chunk task completes"        0 "$(task_json 'Chunk 3/3 — screens [medium]')"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
