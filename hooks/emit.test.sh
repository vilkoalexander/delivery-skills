#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
emit="$root/hooks/emit.sh"
guard="$root/hooks/guard.sh"
run="$root/skills/chunked-delivery/scripts/run.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export DELIVERY_RUN_DIR="$tmp/state/runs"
events="$tmp/state/events"
repo="$tmp/repo"
mkdir -p "$repo" && git -C "$repo" init -q
export CLAUDE_PROJECT_DIR="$repo"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
nok() { fail=$((fail+1)); echo "FAIL - $1: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1" "got '$2', wanted '$3'"; fi; }
file() { ls "$events"/*.jsonl 2>/dev/null | head -1; }
last() { tail -n 1 "$(file)" | jq -r "$1"; }
lines() { local f; f=$(file); if [ -n "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi; }
send() { printf '%s' "$1" | bash "$emit"; }
ev() { # hook_event_name extra-json
  local extra=${2:-}
  [ -n "$extra" ] || extra='{}'
  jq -cn --arg cwd "$repo" --arg e "$1" --argjson x "$extra" \
    '{session_id:"s1", transcript_path:"/t/s1.jsonl", cwd:$cwd, hook_event_name:$e} + $x'
}

send "$(ev PreToolUse '{"tool_name":"Read","tool_use_id":"t1","tool_input":{"file_path":"/a/b.ts"}}')"; eq "no run: exit 0" "$?" 0
eq "no run: nothing written" "$(lines)" 0

(cd "$repo" && bash "$run" start >/dev/null)
eq "run_start written" "$(last .ev)" run_start
run_id=$(last .run)
eq "event file is named by the run" "$(basename "$(file)")" "$run_id.jsonl"
eq "marker carries the run id" "$(jq -r .run "$DELIVERY_RUN_DIR"/*)" "$run_id"

send "$(ev PreToolUse '{"tool_name":"Read","tool_use_id":"t1","tool_input":{"file_path":"/a/b.ts"},"agent_id":"a1","agent_type":"delivery-skills:reviewer"}')"
eq "tool: ev" "$(last .ev)" tool
eq "tool: name" "$(last .tool)" Read
eq "tool: what is the path" "$(last .what)" /a/b.ts
eq "tool: id" "$(last .id)" t1
eq "tool: agent" "$(last .agent)" a1
eq "tool: agent_type" "$(last .agent_type)" delivery-skills:reviewer
eq "tool: session" "$(last .sid)" s1
eq "tool: transcript" "$(last .transcript)" /t/s1.jsonl
eq "tool: run" "$(last .run)" "$run_id"
eq "tool: ts is a number" "$(last '.ts | type')" number

long=$(printf 'x%.0s' $(seq 1 500))
send "$(ev PreToolUse "$(jq -cn --arg c "$long" '{tool_name:"Bash",tool_use_id:"t2",tool_input:{command:$c}}')")"
eq "command clipped to 200" "$(last '.what | length')" 200
eq "controller agent is null" "$(last .agent)" null

send "$(ev PreToolUse '{"tool_name":"Write","tool_use_id":"t3","tool_input":{"file_path":"/a/c.ts","content":"SECRET"}}')"
if tail -n 1 "$(file)" | grep -q SECRET; then nok "file content kept out" "content in event"; else ok "file content kept out"; fi

send "$(ev PreToolUse '{"tool_name":"Agent","tool_use_id":"t4","tool_input":{"description":"Review chunk 2","subagent_type":"delivery-skills:reviewer","model":"sonnet","prompt":"long"}}')"
eq "agent dispatch: what is the description" "$(last .what)" "Review chunk 2"
eq "agent dispatch: sub" "$(last .sub)" delivery-skills:reviewer
eq "agent dispatch: model" "$(last .model)" sonnet

send "$(ev PostToolUse '{"tool_name":"Read","tool_use_id":"t1","duration_ms":12,"tool_response":"big"}')"
eq "tool_end: ev" "$(last .ev)" tool_end
eq "tool_end: ok" "$(last .ok)" true
eq "tool_end: ms" "$(last .ms)" 12
send "$(ev PostToolUseFailure '{"tool_name":"Bash","tool_use_id":"t2","error":"boom","duration_ms":3}')"
eq "failure: ok false" "$(last .ok)" false
eq "failure: error" "$(last .error)" boom

send "$(ev SubagentStart '{"agent_id":"a2","agent_type":"Explore"}')"
eq "agent_start" "$(last '.ev + " " + .agent + " " + .agent_type')" "agent_start a2 Explore"
send "$(ev SubagentStop '{"agent_id":"a2","agent_type":"Explore","agent_transcript_path":"/t/s1/subagents/agent-a2.jsonl"}')"
eq "agent_stop" "$(last .ev)" agent_stop
eq "agent_stop: transcript" "$(last .agent_transcript)" /t/s1/subagents/agent-a2.jsonl
send "$(ev Stop)"; eq "turn_end" "$(last .ev)" turn_end
send "$(ev UserPromptSubmit '{"prompt":"private text"}')"; eq "prompt" "$(last .ev)" prompt
if tail -n 1 "$(file)" | grep -q "private text"; then nok "prompt text kept out" "text in event"; else ok "prompt text kept out"; fi
send "$(ev Notification '{"message":"needs permission","notification_type":"permission_prompt"}')"
eq "notify" "$(last '.ev + " " + .kind')" "notify permission_prompt"
send "$(ev PreCompact '{"trigger":"auto"}')"; eq "compact" "$(last '.ev + " " + .trigger')" "compact auto"

before=$(lines)
send "$(ev SessionStart)"; eq "unknown event: exit 0" "$?" 0
eq "unknown event: nothing written" "$(lines)" "$before"
printf 'not json' | bash "$emit"; eq "bad input: exit 0" "$?" 0
eq "bad input: nothing written" "$(lines)" "$before"

chmod 500 "$events"
send "$(ev Stop)"; eq "unwritable event dir: exit 0" "$?" 0
chmod 700 "$events"

printf '%s' "$(ev PreToolUse '{"tool_name":"Bash","tool_use_id":"t9","tool_input:":{},"tool_input":{"command":"git commit -m x"}}')" | bash "$guard" 2>/dev/null
eq "guard still refuses" "$?" 2
eq "refusal logged" "$(last .ev)" refusal
eq "refusal: tool" "$(last .tool)" Bash
eq "refusal: what" "$(last .what)" "git commit -m x"
case "$(last .reason)" in *"git commit is not run during a run"*) ok "refusal: reason" ;; *) nok "refusal: reason" "$(last .reason)" ;; esac

chmod 500 "$events"
printf '%s' "$(ev PreToolUse '{"tool_name":"Bash","tool_input":{"command":"git push"}}')" | bash "$guard" 2>/dev/null
eq "guard refuses when logging fails" "$?" 2
printf '%s' "$(ev PreToolUse '{"tool_name":"Bash","tool_input":{"command":"ls"}}')" | bash "$guard" 2>/dev/null
eq "guard allows when logging fails" "$?" 0
chmod 700 "$events"

(cd "$repo" && bash "$run" stop >/dev/null)
eq "run_stop written" "$(last .ev)" run_stop
before=$(lines)
send "$(ev Stop)"
eq "after stop: nothing written" "$(lines)" "$before"

printf '{"project":"%s","started":"2026-01-01T00:00:00Z"}\n' "$repo" > "$DELIVERY_RUN_DIR/$(printf '%s' "$(git -C "$repo" rev-parse --show-toplevel)" | { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum; fi; } | cut -c1-12)"
send "$(ev Stop)"
legacy=$(ls "$events" | grep -- '-0.jsonl$' | head -1)
[ -n "$legacy" ] && ok "marker without a run id still logs" || nok "marker without a run id still logs" "$(ls "$events")"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" = 0 ]
