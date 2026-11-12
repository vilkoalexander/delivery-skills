---
name: factory-floor
description: Use when asked to watch, monitor or show a delivery run live, open the factory floor, see what the agents are doing right now, or see token use and hook refusals of a chunked-delivery run.
---

# Factory Floor

A local page that shows delivery runs as they happen: the pipeline as
stations, gate steps, running agents, tokens and context fill, and every hook
refusal. It shows what was observed. No model reports its own progress.

```
node ${CLAUDE_PLUGIN_ROOT}/skills/factory-floor/scripts/serve.ts --open
```

Start it in the background and give the human the URL (default
`http://127.0.0.1:4777/`, `--port` changes it). It is its own process: it
keeps working when the session is busy or the human is away in long-run mode.
TypeScript run directly by Node 22.18 or newer: no install, no build step, no
dependencies. It binds to loopback and only reads files.

## Where the data comes from

| Shown | Source | Written by |
| --- | --- | --- |
| Tool calls, agent start and stop, turn end | `~/.claude/delivery-skills/events/<run>.jsonl` | `hooks/emit.sh`, async, on every hook event while a run is active |
| Refusals and their reasons | same file | `hooks/guard.sh`, as it refuses |
| Gate runs and steps | same file | `static-gate.sh check` |
| Run start and stop, chunk decisions | same file | `run.sh`, `run-log.sh add` |
| Chunk number, name, risk, declared step | same file | the controller, through `chunked-delivery/scripts/mark.sh` only |
| Model, tokens, context fill | session and subagent transcripts | Claude Code |

Stations light up from observed events: a gate from its own events, review and
verify from the agent type, cross-model from the codex command, waiting from
the controller's turn ending with no agent running. The declared step from
`mark.sh` only outlines a station and assigns a `general-purpose` agent to
implement or fix.

## Limits to say out loud when asked

- A run started before the event stream existed has no events and shows as
  stale with nothing in it.
- The context window size is recorded nowhere, so the share is against an
  assumed 200k, or 1M once a session passes 200k (`WINDOW_1M_MODELS` in
  `scripts/state.ts`).
- The transcript format is internal to Claude Code. A field that goes missing
  shows as "no data"; the page keeps working.
- Only this plugin's refusals are shown. A call denied by another plugin's
  hook leaves no event.
- `state: stale` is a marker with no event for 30 minutes. A crashed run stays
  stale until `run.sh stop`.

`node scripts/state.ts [run-id]` prints the same JSON the page reads, for a
question the page does not answer.
