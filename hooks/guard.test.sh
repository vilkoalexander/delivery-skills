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
trap 'rm -rf "$tmp"' EXIT

export DELIVERY_RUN_DIR="$tmp/runs"
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
[ "$code" = 0 ] && [ "$(ls "$DELIVERY_RUN_DIR" | wc -l | tr -d ' ')" = 1 ] && ok "start twice is idempotent" || nok "start twice is idempotent" "$out"
out=$(cd "$repo" && bash "$run" status 2>&1); code=$?
[ "$code" = 0 ] && printf '%s' "$out" | grep -qF "$repo" && ok "status names the repo" || nok "status names the repo" "$out"

# ---------------------------------------------------------------- git writes, run active
hook "commit blocked"            2 "$(bash_json 'git commit -m "x"')"
printf '%s' "$last_err" | grep -qi "run.sh stop" && ok "reason says how to end the run" || nok "reason says how to end the run" "$last_err"
hook "add blocked"               2 "$(bash_json 'git add .')"
hook "add -N allowed"            0 "$(bash_json 'git add -N . && git diff > /tmp/w/chunk-1.diff')"
hook "add --intent-to-add ok"    0 "$(bash_json 'git add --intent-to-add src/new.ts')"
hook "push after tests blocked"  2 "$(bash_json 'npm test && git push origin HEAD')"
hook "push via ; blocked"        2 "$(bash_json 'echo done; git push')"
hook "stash blocked"             2 "$(bash_json 'git stash')"
hook "reset --hard blocked"      2 "$(bash_json 'git reset --hard HEAD')"
hook "reset (soft) allowed"      0 "$(bash_json 'git reset')"
hook "checkout -- blocked"       2 "$(bash_json 'git checkout -- src/a.ts')"
hook "checkout -b allowed"       0 "$(bash_json 'git checkout -b feature/x')"
hook "restore blocked"           2 "$(bash_json 'git restore src/a.ts')"
hook "clean blocked"             2 "$(bash_json 'git clean -fd')"
hook "merge blocked"             2 "$(bash_json 'git merge main')"
hook "rebase blocked"            2 "$(bash_json 'git rebase main')"
hook "gh pr create blocked"      2 "$(bash_json 'gh pr create --fill')"
hook "git -C commit blocked"     2 "$(bash_json "git -C $repo commit -am x")"
hook "env prefix commit blocked" 2 "$(bash_json 'GIT_AUTHOR_NAME=x git commit -m y')"
hook "status allowed"            0 "$(bash_json 'git status --short')"
hook "log allowed"               0 "$(bash_json 'git log --oneline -5')"
hook "diff allowed"              0 "$(bash_json 'git diff --stat')"
hook "apply -R allowed"          0 "$(bash_json 'git apply -R /tmp/w/chunk-2.diff')"
hook "grep for commit allowed"   0 "$(bash_json 'grep -rn "git commit" docs/')"
hook "subagent commit blocked"   2 "$(bash_json 'git commit -m x' general-purpose)"

# ---------------------------------------------------------------- snapshot read, run active
hook "controller reading snapshot blocked" 2 "$(read_json /tmp/w/chunk-3.diff)"
hook "controller reading before-snapshot blocked" 2 "$(read_json /tmp/w/chunk-3-before.diff)"
hook "reviewer reading snapshot allowed"   0 "$(read_json /tmp/w/chunk-3.diff delivery-skills:reviewer)"
hook "controller reading source allowed"   0 "$(read_json "$repo/src/a.ts")"
hook "controller cat snapshot blocked"     2 "$(bash_json 'cat /tmp/w/chunk-3.diff')"
hook "controller sed -n snapshot blocked"  2 "$(bash_json "sed -n '1,80p' /tmp/w/chunk-3-before.diff")"
hook "controller wc snapshot allowed"      0 "$(bash_json 'wc -l /tmp/w/chunk-3.diff')"
hook "controller writing snapshot allowed" 0 "$(bash_json 'git diff > /tmp/w/chunk-3.diff')"
hook "subagent cat snapshot allowed"       0 "$(bash_json 'cat /tmp/w/chunk-3.diff' general-purpose)"

# ---------------------------------------------------------------- reviewer is read-only (run or not)
for agent in delivery-skills:reviewer reviewer delivery-skills:verifier verifier; do
  hook "$agent: sed -i blocked"        2 "$(bash_json "sed -i 's/a/b/' src/a.ts" $agent)"
  hook "$agent: redirect blocked"      2 "$(bash_json 'echo hi > notes.txt' $agent)"
  hook "$agent: append blocked"        2 "$(bash_json 'echo hi >> notes.txt' $agent)"
  hook "$agent: tee blocked"           2 "$(bash_json 'cat a | tee b' $agent)"
  hook "$agent: rm blocked"            2 "$(bash_json 'rm -rf dist' $agent)"
  hook "$agent: mv blocked"            2 "$(bash_json 'mv a b' $agent)"
  hook "$agent: install blocked"       2 "$(bash_json 'npm install left-pad' $agent)"
  hook "$agent: git apply blocked"     2 "$(bash_json 'git apply fix.diff' $agent)"
  hook "$agent: devnull allowed"       0 "$(bash_json 'npm test > /dev/null 2>&1' $agent)"
  hook "$agent: stderr merge allowed"  0 "$(bash_json 'tsc --noEmit 2>&1 | head' $agent)"
  hook "$agent: grep allowed"          0 "$(bash_json 'grep -rn "useEffect" src | sort' $agent)"
  hook "$agent: cat diff allowed"      0 "$(bash_json 'cat /tmp/w/chunk-3.diff' $agent)"
  hook "$agent: scan script allowed"   0 "$(bash_json 'bash scripts/scan.sh src/a.tsx' $agent)"
done
hook "verifier may run the app"   0 "$(bash_json 'npm run start:dev & sleep 3; curl -s localhost:3000/health' delivery-skills:verifier)"
hook "verifier may run tests"     0 "$(bash_json 'npx jest src/orders 2>&1 | tail -5' delivery-skills:verifier)"
hook "implementer sed -i allowed" 0 "$(bash_json "sed -i 's/a/b/' src/a.ts" general-purpose)"

# ---------------------------------------------------------------- run off: git is free again
out=$(cd "$repo" && bash "$run" stop 2>&1); code=$?
[ "$code" = 0 ] && [ -z "$(ls -A "$DELIVERY_RUN_DIR")" ] && ok "stop removes the marker" || nok "stop removes the marker" "$out"
hook "commit allowed with no run"        0 "$(bash_json 'git commit -m x')"
hook "snapshot read allowed with no run" 0 "$(read_json /tmp/w/chunk-3.diff)"
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

hook "report without Proof held"       2 "$(stop_json "$impl_t" 'Done, all tests pass.')"
printf '%s' "$last_err" | grep -q "## Proof" && ok "reason names the block" || nok "reason names the block" "$last_err"
hook "report missing Reuse held"       2 "$(stop_json "$impl_t" $'Done.\n## Proof\n- ran: npm test — ok\n- not verified: nothing')"
hook "full report passes"              0 "$(stop_json "$impl_t" "$full_report")"
hook "array-content prompt enforced"   2 "$(stop_json "$arr_t" 'Done.')"
hook "explore agent not held"          0 "$(stop_json "$explore_t" 'It is guarded at class level.')"
hook "second stop passes through"      0 "$(stop_json "$impl_t" 'Done.' true)"
hook "missing transcript passes"       0 "$(stop_json "$tmp/nope.jsonl" 'Done.')"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
