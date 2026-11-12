#!/usr/bin/env bash
# Registered async: it observes, never decides. Every path out is exit 0.
set -uo pipefail
input=$(cat)

run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
[ -n "$(ls -A "$run_dir" 2>/dev/null)" ] || exit 0

proj="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$proj" ] && [[ $input =~ \"cwd\":\"([^\"]*)\" ]]; then proj=${BASH_REMATCH[1]}; fi
[ -n "$proj" ] || exit 0
root=$(git -C "$proj" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$proj")
hash() { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum; fi | cut -c1-12; }
id=$(printf '%s' "$root" | hash)
marker="$run_dir/$id"
[ -f "$marker" ] || exit 0

if [[ $(<"$marker") =~ \"run\":\"([^\"]+)\" ]]; then run=${BASH_REMATCH[1]}; else run="$id-0"; fi
events_dir="${DELIVERY_EVENTS_DIR:-$(dirname "$run_dir")/events}"

line=$(EV_RUN="$run" EV_REFUSAL="${EMIT_REFUSAL:-}" jq -c '
  def clip(n): tostring | .[0:n];
  def what: (.tool_input // {}) as $i
    | ($i.file_path // $i.path // $i.notebook_path // $i.command // $i.pattern
       // $i.url // $i.query // $i.description // $i.skill // "") | clip(200);
  def tool_fields: {id: (.tool_use_id // null), tool: (.tool_name // null)};
  . as $in
  | {ts: (now * 1000 | floor / 1000), run: env.EV_RUN, src: "hook",
     sid: (.session_id // null), agent: (.agent_id // null), agent_type: (.agent_type // null)}
  + (if env.EV_REFUSAL != "" then
       {ev: "refusal", tool: (.tool_name // null), what: what, reason: (env.EV_REFUSAL | clip(400))}
     elif .hook_event_name == "PreToolUse" then
       {ev: "tool", what: what} + tool_fields
       + (if (.tool_name == "Agent" or .tool_name == "Task")
          then {sub: (.tool_input.subagent_type // null), model: (.tool_input.model // null)} else {} end)
     elif .hook_event_name == "PostToolUse" then
       {ev: "tool_end", ok: true, ms: (.duration_ms // null)} + tool_fields
     elif .hook_event_name == "PostToolUseFailure" then
       {ev: "tool_end", ok: false, ms: (.duration_ms // null), error: ((.error // "") | clip(300))} + tool_fields
     elif .hook_event_name == "SubagentStart" then {ev: "agent_start"}
     elif .hook_event_name == "SubagentStop" then {ev: "agent_stop", agent_transcript: (.agent_transcript_path // null)}
     elif .hook_event_name == "Stop" then {ev: "turn_end"}
     elif .hook_event_name == "UserPromptSubmit" then {ev: "prompt"}
     elif .hook_event_name == "Notification" then {ev: "notify", kind: (.notification_type // null), message: ((.message // "") | clip(200))}
     elif .hook_event_name == "PreCompact" then {ev: "compact", trigger: (.trigger // null)}
     else empty end)
  + {transcript: ($in.transcript_path // null)}
' <<<"$input" 2>/dev/null) || exit 0
[ -n "$line" ] || exit 0
mkdir -p "$events_dir" 2>/dev/null || exit 0
printf '%s\n' "$line" >> "$events_dir/$run.jsonl" 2>/dev/null
exit 0
