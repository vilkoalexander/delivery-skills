#!/usr/bin/env bash
# Registered async: it observes, never decides. Every path out is exit 0.
set -uo pipefail
input=$(cat)

run_dir="${DELIVERY_RUN_DIR:-$HOME/.claude/delivery-skills/runs}"
[ -n "$(ls -A "$run_dir" 2>/dev/null)" ] || exit 0

project=""
if [[ $input =~ \"cwd\":\"([^\"]*)\" ]]; then
  project=${BASH_REMATCH[1]}
fi
[ -n "$project" ] || project="${CLAUDE_PROJECT_DIR:-}"
[ -n "$project" ] || exit 0

source "$(dirname "$0")/../skills/chunked-delivery/scripts/lib/run.sh" 2>/dev/null || exit 0
run_locate "$project"
run_active || exit 0
run=$(run_field run)
[ -n "$run" ] || exit 0

line=$(EV_RUN="$run" EV_REFUSAL="${EMIT_REFUSAL:-}" jq -c '
  def clip(n): tostring | .[0:n];
  def redact: tostring
    | gsub("(?<k>authorization[\"\u0027]?\\s*[:=]\\s*[\"\u0027]?((bearer|basic|token)\\s+)?)[^\\s\"\u0027]+"; "\(.k)[redacted]"; "i")
    | gsub("(?<k>bearer\\s+)[A-Za-z0-9._~+/=-]{8,}"; "\(.k)[redacted]"; "i")
    | gsub("(?<k>--?(password|passwd|token|secret|api-key|apikey|access-token|auth-token)[= ])\\S+"; "\(.k)[redacted]"; "i")
    | gsub("(?<k>[A-Za-z0-9_]*(secret|token|password|passwd|api_?key|private_?key|access_?key)[A-Za-z0-9_]*=)(\"[^\"]*\"|\u0027[^\u0027]*\u0027|\\S+)"; "\(.k)[redacted]"; "i")
    | gsub("(?<k>://[^/\\s:@]+:)[^@/\\s]+@"; "\(.k)[redacted]@")
    | gsub("gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|(AKIA|ASIA)[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|(sk|rk)_live_[A-Za-z0-9]{16,}|eyJ[A-Za-z0-9_-]{10,}\\.eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"; "[redacted]");
  def what: (.tool_input // {}) as $i
    | ($i.file_path // $i.path // $i.notebook_path // $i.command // $i.pattern
       // $i.url // $i.query // $i.description // $i.skill // "") | redact | clip(200);
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
       {ev: "tool_end", ok: false, ms: (.duration_ms // null), error: ((.error // "") | redact | clip(300))} + tool_fields
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
mkdir -p "$run_events_dir" 2>/dev/null || exit 0
printf '%s\n' "$line" >> "$(run_events_file)" 2>/dev/null
exit 0
