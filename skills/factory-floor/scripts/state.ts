#!/usr/bin/env node
// Runs as is on Node 22.18+ (type stripping): erasable syntax only, no enums, no parameter properties.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { builds as buildsOf, PHASES } from "../../chunked-delivery/scripts/lifecycle.mjs";

export const STALE_AFTER_S = 30 * 60;
const FEED_LIMIT = 300;
// Models seen running past 200k on this machine; everything else is assumed 200k.
export const WINDOW_1M_MODELS = ["fable"];
const SIDE_AGENTS = ["Explore", "Plan", "web-fetch", "claude-code-guide", "statusline-setup"];
const FINAL = "final";
export const STATIONS: string[] = [...new Set(Object.values(PHASES as Record<string, { station: string }>)
  .map((phase) => phase.station))].filter((name) => name !== FINAL);
const STATION_OF_PHASE = (phase: string | null): string | null =>
  phase ? (PHASES as Record<string, { station: string }>)[phase]?.station ?? null : null;
const AGENT_STATIONS = ["tests", "implement", "review", "fix", "verify"];

export type Tokens = { in: number; out: number; cw: number; cr: number };
export const ZERO: Tokens = { in: 0, out: 0, cw: 0, cr: 0 };

export type RunEvent = { ev: string; ts?: number; src?: string; agent?: string | null; [key: string]: any };
export type UsageItem = Tokens & { id: string; ts: number | null; model: string };
export type Marker = { project?: string; started?: string; run?: string; mode?: string; head?: string };
type OpenTool = { tool: string; what: string; since: number };
export type Station = { name: string; status: string; detail: string; declared: boolean };
type Build = {
  chunk: number | string | undefined; build: number; of: number | null; name: string | null; plan: string | null;
  risk: string | null; marks: RunEvent[]; phases: string[]; fix: { static: number; review: number; human: number };
  started: number; reportedAt: number | null; parked: string | null; decision: string | null;
};
type Row = { build: Build | null; phase: string | null; start: number | null; end: number | null };
type Agent = {
  id: string; type: string | null; seat: string; start: number; end: number | null; calls: number;
  open: Map<string, OpenTool>; chunk: number; station: string; transcript: string | null;
  agentTranscript: string | null; desc: string | null; alias: string | null;
};
type Gate = {
  start: number; end: number | null; ok: boolean | null; chunk: number;
  steps: { step: string; ok: boolean | null; s: number | null }[];
};
type AgentRow = {
  id: string; seat: string; type: string | null; desc: string | null; station: string; chunk: number;
  start: number; end: number | null; running: boolean; calls: number; current: OpenTool | null;
  model: string | null; tokens: Tokens; ctx: number; window: number; fill: number;
};

export function runsDir(): string {
  return process.env.DELIVERY_RUN_DIR || path.join(os.homedir(), ".claude/delivery-skills/runs");
}

export function eventsDir(): string {
  return process.env.DELIVERY_EVENTS_DIR || path.join(path.dirname(runsDir()), "events");
}

function isoToEpoch(value: unknown): number | null {
  const ms = typeof value === "string" ? Date.parse(value) : NaN;
  return Number.isNaN(ms) ? null : ms / 1000;
}

export function parseEvent(line: Buffer): RunEvent | null {
  const item = JSON.parse(line.toString());
  return item && typeof item === "object" && !Array.isArray(item) && "ev" in item ? item : null;
}

export function parseUsage(line: Buffer): UsageItem | null {
  if (!line.includes('"assistant"')) return null;
  const entry = JSON.parse(line.toString());
  if (entry?.type !== "assistant") return null;
  const message = entry.message ?? {};
  const usage = message.usage ?? {};
  const model: string = message.model ?? "";
  if (model.startsWith("<")) return null;
  return {
    id: message.id ?? entry.uuid,
    ts: isoToEpoch(entry.timestamp),
    model,
    in: usage.input_tokens ?? 0,
    out: usage.output_tokens ?? 0,
    cw: usage.cache_creation_input_tokens ?? 0,
    cr: usage.cache_read_input_tokens ?? 0,
  };
}

type TailEntry = { offset: number; items: any[]; inode: number };

/** Reads only the bytes appended since the last call and keeps the reduced items. */
export class Tail {
  files = new Map<string, TailEntry>();

  read<T>(file: string | null | undefined, reduce: (line: Buffer) => T | null): T[] {
    if (!file) return [];
    let stat: fs.Stats;
    try {
      stat = fs.statSync(file);
    } catch {
      return [];
    }
    const key = file + "\0" + reduce.name;
    let entry = this.files.get(key);
    if (!entry || stat.size < entry.offset || stat.ino !== entry.inode) {
      entry = { offset: 0, items: [], inode: stat.ino };
      this.files.set(key, entry);
    }
    if (stat.size > entry.offset) {
      let data: Buffer;
      try {
        const fd = fs.openSync(file, "r");
        try {
          data = Buffer.alloc(stat.size - entry.offset);
          const got = fs.readSync(fd, data, 0, data.length, entry.offset);
          data = data.subarray(0, got);
        } finally {
          fs.closeSync(fd);
        }
      } catch {
        return entry.items;
      }
      const end = data.lastIndexOf(10);
      if (end >= 0) {
        let from = 0;
        while (from <= end) {
          const to = data.indexOf(10, from);
          let item: T | null = null;
          try {
            item = reduce(data.subarray(from, to));
          } catch {
            item = null;
          }
          if (item !== null && item !== undefined) entry.items.push(item);
          from = to + 1;
        }
        entry.offset += end + 1;
      }
    }
    return entry.items;
  }
}

function add(total: Tokens, part: Tokens): Tokens {
  return { in: total.in + part.in, out: total.out + part.out, cw: total.cw + part.cw, cr: total.cr + part.cr };
}

function windowFor(model: string | null, peak: number): number {
  return peak > 200_000 || WINDOW_1M_MODELS.some((name) => (model ?? "").includes(name)) ? 1_000_000 : 200_000;
}

/** A message is written as several entries repeating one usage block, so each id counts once. */
export function summarize(items: UsageItem[], since: number | null = null, until: number | null = null) {
  const byId = new Map<string, UsageItem>();
  for (const item of items) byId.set(item.id, item);
  const messages = [...byId.values()];
  let tokens = { ...ZERO };
  let peak = 0;
  for (const item of messages) {
    peak = Math.max(peak, item.in + item.cw + item.cr);
    if (since !== null && item.ts !== null && item.ts < since) continue;
    if (until !== null && item.ts !== null && item.ts >= until) continue;
    tokens = add(tokens, item);
  }
  const last = messages.at(-1);
  const ctx = last ? last.in + last.cw + last.cr : 0;
  const model = last ? last.model : null;
  const window = windowFor(model, peak);
  return { tokens, model, ctx, window, fill: Math.round((ctx / window) * 10000) / 10000, messages: messages.length };
}

function shortType(agentType: string | null | undefined): string {
  return (agentType || "agent").split(":").at(-1) as string;
}

function stationFor(agentType: string | null, phase: string | null): string {
  const kind = shortType(agentType);
  if (SIDE_AGENTS.includes(kind)) return "other";
  if (kind === "verifier") return "verify";
  if (phase === "fix") return "fix";
  if (kind === "reviewer") return "review";
  return phase === "test" ? "tests" : "implement";
}

function expandHome(file: string): string {
  return file.startsWith("~") ? path.join(os.homedir(), file.slice(1)) : file;
}

function agentTranscriptPath(agent: Agent): string | null {
  if (agent.agentTranscript) return expandHome(agent.agentTranscript);
  if (agent.transcript && agent.id) {
    return path.join(agent.transcript.replace(/\.[^./]+$/, ""), "subagents", `agent-${agent.id}.jsonl`);
  }
  return null;
}

export function readMarkers(): Map<string, Marker> {
  const found = new Map<string, Marker>();
  let names: string[];
  try {
    names = fs.readdirSync(runsDir());
  } catch {
    return found;
  }
  for (const name of names) {
    try {
      const marker = JSON.parse(fs.readFileSync(path.join(runsDir(), name), "utf8"));
      if (marker && typeof marker === "object") found.set(marker.run || name + "-0", marker);
    } catch {
      continue;
    }
  }
  return found;
}

export function clock(seconds: number | null | undefined): string {
  const total = Math.max(0, Math.floor(seconds || 0));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = String(total % 60).padStart(2, "0");
  return hours ? `${hours}:${String(minutes).padStart(2, "0")}:${secs}` : `${minutes}:${secs}`;
}

type Feed = { ts: number; kind: string; who: string; text: string };
type Controller = { calls: number; open: Map<string, OpenTool>; sid: string | null; transcripts: string[];
                    lastEv: string | null };
type Dispatch = { sub: string | null; model: string | null; desc: string; taken: boolean };
type Reduced = {
  run: { project: string | null; branch: string | null; plan: string | null; started: number | null;
         ended: number | null };
  rows: Row[]; current: number; agents: Map<string, Agent>; controller: Controller; dispatches: Dispatch[];
  gates: Gate[]; feed: Feed[]; lastTs: number | null; buildOfMark: Map<RunEvent, Build>;
};
type Turn = { ts: number; who: string; actor: Agent | null; holder: Agent | Controller };

const isFinal = (build: Build | null): boolean => build?.chunk === FINAL;

function stripProject(state: Reduced, what: unknown): string {
  const text = typeof what === "string" ? what : "";
  return state.run.project ? text.split(state.run.project + "/").join("") : text;
}

function say(state: Reduced, ts: number, kind: string, who: string, text: string) {
  state.feed.push({ ts, kind, who, text });
}

function enterRow(state: Reduced, build: Build | null, ts: number): Row {
  let index = state.rows.findIndex((row) => row.build === build);
  if (index < 0) index = state.rows.push({ build, phase: null, start: ts, end: null }) - 1;
  if (index !== state.current) {
    if (state.current >= 0) state.rows[state.current].end = ts;
    state.rows[index].end = null;
    state.current = index;
  }
  return state.rows[index];
}

// Work seen before the first mark still needs a row to show under.
function rowForWork(state: Reduced, ts: number): number {
  if (state.current < 0) enterRow(state, null, ts);
  return state.current;
}

function agentOf(state: Reduced, event: RunEvent, ts: number): Agent {
  const id = event.agent as string;
  let agent = state.agents.get(id);
  if (!agent) {
    const type: string | null = event.agent_type ?? null;
    const match = state.dispatches.find((d) => !d.taken && (d.sub === type || d.sub === null));
    if (match) match.taken = true;
    const chunk = rowForWork(state, ts);
    agent = { id, type, seat: shortType(type), start: ts, end: null, calls: 0, open: new Map(), chunk,
              station: stationFor(type, state.rows[chunk].phase), transcript: event.transcript ?? null,
              agentTranscript: null, desc: match?.desc || null, alias: match?.model ?? null };
    state.agents.set(id, agent);
    say(state, ts, "agent", agent.seat, "started" + (agent.desc ? ": " + agent.desc : ""));
  }
  return agent;
}

const HANDLERS: Record<string, (state: Reduced, event: RunEvent, turn: Turn) => void> = {
  run_start(state, event, { ts }) {
    state.run.project = event.project || state.run.project;
    state.run.branch = event.branch ?? null;
    say(state, ts, "run", "run", "run started on " + path.basename(state.run.project || "?"));
  },
  run_stop(state, _event, { ts }) {
    state.run.ended = ts;
    say(state, ts, "run", "run", "run ended");
  },
  mark(state, event, { ts }) {
    const build = state.buildOfMark.get(event) ?? null;
    if (!build) return;
    enterRow(state, build, ts).phase = event.phase ?? null;
    if (event.plan) state.run.plan = event.plan;
    const label = isFinal(build) ? "final, whole tree" : `chunk ${event.chunk}`;
    const again = build.build > 1 && event === build.marks[0] ? `, build ${build.build}` : "";
    const round = event.phase === "fix" && event.round ? ` round ${event.round}` : "";
    const parked = event.parked ? ` (parked: ${event.parked})` : "";
    say(state, ts, "mark", "controller", `${label}${again}: ${event.phase}${round}${parked}`);
  },
  agent_stop(state, event, { ts, who, actor }) {
    if (!actor) return;
    actor.end = ts;
    actor.open.clear();
    actor.agentTranscript = event.agent_transcript || actor.agentTranscript;
    say(state, ts, "agent", who, `stopped, ${actor.calls} calls, ${clock(ts - actor.start)}`);
  },
  tool(state, event, { ts, who, actor, holder }) {
    holder.calls += 1;
    const what = stripProject(state, event.what);
    holder.open.set(event.id || "t" + ts, { tool: event.tool, what, since: ts });
    if (actor) actor.end = null;
    else if (event.tool === "Agent" || event.tool === "Task") {
      state.dispatches.push({ sub: event.sub ?? null, model: event.model ?? null, desc: what, taken: false });
    }
    say(state, ts, "tool", who, `${event.tool} ${what}`);
  },
  tool_end(state, event, { ts, who, holder }) {
    holder.open.delete(event.id);
    if (event.ok === false) say(state, ts, "fail", who, `${event.tool} failed: ${event.error || ""}`);
  },
  refusal(state, event, { ts, who, holder }) {
    for (const [key, tool] of holder.open) if (tool.tool === event.tool) holder.open.delete(key);
    say(state, ts, "refusal", who,
        `REFUSED ${event.tool || "stop"} ${stripProject(state, event.what)}: ${stripProject(state, event.reason)}`);
  },
  turn_end(state, _event, { ts, who }) {
    state.controller.open.clear();
    say(state, ts, "turn", who, "turn ended");
  },
  notify(state, event, { ts, who }) {
    say(state, ts, "notify", who, "notification: " + (event.message || event.kind || ""));
  },
  compact(state, event, { ts, who }) {
    say(state, ts, "notify", who, `context compacted (${event.trigger || "?"})`);
  },
  gate_start(state, event, { ts }) {
    state.gates.push({ start: ts, end: null, ok: null, steps: [], chunk: rowForWork(state, ts) });
    say(state, ts, "gate", "gate", `static gate started on ${event.paths} paths`);
  },
  gate_step_start(state, event) {
    state.gates.at(-1)?.steps.push({ step: event.step, ok: null, s: null });
  },
  gate_step(state, event, { ts }) {
    const gate = state.gates.at(-1);
    if (!gate) return;
    let step = gate.steps.findLast((s) => s.step === event.step && s.ok === null);
    if (!step) {
      step = { step: event.step, ok: null, s: null };
      gate.steps.push(step);
    }
    step.ok = Boolean(event.ok);
    step.s = event.s ?? null;
    say(state, ts, step.ok ? "gate" : "fail", "gate", `${step.step} ${step.ok ? "ok" : "FAIL"}`);
  },
  gate_end(state, event, { ts }) {
    const gate = state.gates.at(-1);
    if (!gate) return;
    gate.end = ts;
    gate.ok = Boolean(event.ok);
    say(state, ts, gate.ok ? "gate" : "fail", "gate", "static gate " + (gate.ok ? "clean" : "FAILED"));
  },
  chunk_logged(state, event, { ts }) {
    const entry = event.entry || {};
    say(state, ts, "mark", "you", `chunk ${entry.chunk} ${entry.decision}`);
  },
};

function turnOf(state: Reduced, event: RunEvent, ts: number): Turn {
  if (event.src !== "hook") return { ts, who: event.src || "script", actor: null, holder: state.controller };
  if (event.agent) {
    const actor = agentOf(state, event, ts);
    return { ts, who: actor.seat, actor, holder: actor };
  }
  const controller = state.controller;
  controller.lastEv = event.ev;
  if (event.sid) controller.sid = event.sid;
  if (event.transcript && !controller.transcripts.includes(event.transcript)) {
    controller.transcripts.push(event.transcript);
  }
  return { ts, who: "controller", actor: null, holder: controller };
}

/** Everything the event file alone says about a run. No transcript is read here. */
export function reduce(input: RunEvent[], marker: Marker | null = null): Reduced {
  const events = input.filter((event) => typeof event.ts === "number").sort((a, b) => a.ts! - b.ts!);
  const state: Reduced = {
    run: { project: marker?.project ?? null, branch: null, plan: null, started: null, ended: null },
    rows: [], current: -1, agents: new Map(), dispatches: [], gates: [], feed: [], lastTs: null,
    controller: { calls: 0, open: new Map(), sid: null, transcripts: [], lastEv: null },
    buildOfMark: new Map(),
  };
  for (const build of buildsOf(events) as Build[]) {
    for (const mark of build.marks) state.buildOfMark.set(mark, build);
  }
  for (const event of events) {
    const ts = event.ts!;
    state.lastTs = ts;
    state.run.started ??= ts;
    const turn = turnOf(state, event, ts);
    HANDLERS[event.ev]?.(state, event, turn);
  }
  if (!state.rows.length) enterRow(state, null, state.run.started ?? 0);
  return state;
}

function progress(state: Reduced, marker: Marker | null, at: number) {
  const { run, lastTs, controller } = state;
  const ended = run.ended !== null || marker === null;
  const anyRunning = !ended && [...state.agents.values()].some((a) => a.end === null);
  const current = state.rows[state.current];
  const reported = current.build !== null && current.phase === "report" && !current.build.decision;
  const waiting = !ended && !anyRunning && (controller.lastEv === "turn_end" || reported);
  const status = ended ? "ended" : waiting ? "waiting"
    : lastTs === null || at - lastTs > STALE_AFTER_S ? "stale" : "running";
  return { ended, waiting, status, edge: run.ended ?? (ended ? lastTs : at) ?? at };
}

export function build(runId: string, input: RunEvent[], tail: Tail, now: number | null = null,
                      marker: Marker | null = null) {
  const at = now ?? Date.now() / 1000;
  const state = reduce(input, marker);
  const { run, controller, gates, lastTs } = state;
  const { ended, waiting, status, edge } = progress(state, marker, at);

  const currentOf = (open: Map<string, OpenTool>): OpenTool | null => {
    let latest: OpenTool | null = null;
    for (const tool of open.values()) if (!latest || tool.since > latest.since) latest = tool;
    return latest ? { tool: latest.tool, what: latest.what, since: latest.since } : null;
  };

  const agentRows: AgentRow[] = [...state.agents.values()].map((agent) => {
    const usage = summarize(tail.read(agentTranscriptPath(agent), parseUsage));
    const running = agent.end === null && !ended;
    return {
      id: agent.id, seat: agent.seat, type: agent.type, desc: agent.desc, station: agent.station,
      chunk: agent.chunk, start: agent.start, end: running ? null : agent.end ?? edge, running,
      calls: agent.calls, current: running ? currentOf(agent.open) : null, model: usage.model || agent.alias,
      tokens: usage.tokens, ctx: usage.ctx, window: usage.window, fill: usage.fill,
    };
  });

  const controllerItems = controller.transcripts.flatMap((file) => tail.read(expandHome(file), parseUsage));
  const controllerUsage = summarize(controllerItems, run.started, run.ended);
  const controllerRow = {
    seat: "controller", sid: controller.sid, calls: controller.calls,
    current: ended ? null : currentOf(controller.open), model: controllerUsage.model,
    tokens: controllerUsage.tokens, ctx: controllerUsage.ctx, window: controllerUsage.window,
    fill: controllerUsage.fill, running: status === "running" && controller.lastEv !== "turn_end",
  };

  const chunkRows = state.rows.map((row, index) => {
    const isCurrent = index === state.current;
    const mine = agentRows.filter((a) => a.chunk === index);
    const myGates = gates.filter((g) => g.chunk === index);
    const controllerTokens = summarize(controllerItems, row.start, row.end ?? run.ended).tokens;
    const made = row.build;
    return {
      index, n: typeof made?.chunk === "number" ? made.chunk : null, of: made?.of ?? null,
      name: made?.name ?? null, risk: isFinal(made) ? null : made?.risk ?? null, final: isFinal(made),
      build: made?.build ?? 1, phase: row.phase, start: row.start,
      end: row.end ?? (ended ? edge : null), decision: made?.decision ?? null, parked: made?.parked ?? null,
      fix: made?.fix ?? { static: 0, review: 0, human: 0 },
      tokens: mine.reduce((sum, a) => add(sum, a.tokens), controllerTokens), controller_tokens: controllerTokens,
      stations: stations(row, mine, myGates, isCurrent, waiting, ended, row.end ?? edge),
      gate: lastGate(myGates),
    };
  });

  return {
    run: runId, project: run.project, name: path.basename(run.project || "") || runId, branch: run.branch,
    plan: run.plan, mode: marker?.mode ?? null, state: status, started: run.started,
    ended: run.ended ?? (ended ? lastTs : null), last: lastTs, now: at, chunks: chunkRows, agents: agentRows,
    controller: controllerRow, tokens: agentRows.reduce((sum, a) => add(sum, a.tokens), controllerUsage.tokens),
    feed: state.feed.slice(-FEED_LIMIT),
  };
}

function lastGate(gates: Gate[]) {
  const gate = gates.at(-1);
  if (!gate) return null;
  return { runs: gates.length, failed_runs: gates.filter((g) => g.ok === false).length, ok: gate.ok,
           start: gate.start, end: gate.end, steps: gate.steps.map((s) => ({ step: s.step, ok: s.ok, s: s.s })) };
}

function fixDetail(fix: { static: number; review: number; human: number }): string {
  return [fix.review ? `round ${fix.review}` : "", fix.static ? `${fix.static} static` : "",
          fix.human ? `${fix.human} after the report` : ""].filter(Boolean).join(" · ");
}

function gateStation(gates: Gate[], ended: boolean) {
  const gate = gates.at(-1);
  if (!gate) return null;
  const failed = gates.filter((g) => g.ok === false).length;
  const note = `run ${gates.length}` + (failed ? ` · ${failed} failed` : "");
  if (gate.end !== null) {
    return { status: gate.ok ? "done" : "failed", detail: `${clock(gate.end - gate.start)} · ${note}` };
  }
  if (ended) return { status: "failed", detail: "no result · " + note };
  const step = gate.steps.findLast((s) => s.ok === null)?.step;
  return { status: "running", detail: `${step || "starting"} · ${note}` };
}

function crossStation(marks: RunEvent[], live: boolean, stop: number) {
  const at = marks.findLastIndex((mark) => mark.phase === "cross");
  if (at < 0) return null;
  const next = marks[at + 1];
  if (next) return { status: "done", detail: clock(next.ts! - marks[at].ts!) };
  return { status: live ? "running" : "done", detail: clock(stop - marks[at].ts!) };
}

function youStation(row: Row, isCurrent: boolean, waiting: boolean) {
  const made = row.build;
  if (made?.decision) return { status: "done", detail: made.decision };
  if (made && row.phase === "report") {
    return { status: "waiting", detail: made.parked ? "parked: " + made.parked : "your turn" };
  }
  if (isCurrent && waiting) return { status: "waiting", detail: "your turn" };
  if (!isCurrent) return { status: "done", detail: "moved on" };
  return null;
}

function stations(row: Row, agents: AgentRow[], gates: Gate[], isCurrent: boolean, waiting: boolean,
                  ended: boolean, stop: number): Station[] {
  const out: Record<string, { status: string; detail: string }> = {};
  const idle = { status: "idle", detail: "" };
  const phase = row.phase;
  const live = isCurrent && !ended;

  for (const name of AGENT_STATIONS) {
    const mine = agents.filter((a) => a.station === name);
    if (!mine.length) continue;
    const running = mine.some((a) => a.running);
    const span = (running ? stop : Math.max(...mine.map((a) => a.end as number))) - Math.min(...mine.map((a) => a.start));
    out[name] = { status: running ? "running" : "done",
                  detail: `${mine.length} agent${mine.length === 1 ? "" : "s"} · ${clock(span)}` };
  }
  const rounds = row.build ? fixDetail(row.build.fix) : "";
  if (rounds && out.fix) out.fix = { status: out.fix.status, detail: `${rounds} · ${out.fix.detail}` };
  else if (rounds) out.fix = { status: phase === "fix" && live ? "running" : "done", detail: rounds };

  const gate = gateStation(gates, ended);
  if (gate) out.gate = gate;
  const cross = crossStation(row.build?.marks ?? [], live, stop);
  if (cross) out.cross = cross;
  const you = youStation(row, isCurrent, waiting);
  if (you) out.you = you;

  const reached = STATIONS.findLastIndex((name) => out[name]);
  const declared = STATION_OF_PHASE(phase);
  return STATIONS.map((name, i) => {
    const skipped = !out[name] && (i < reached || !isCurrent || ended);
    const station = skipped ? { status: "skipped", detail: "" } : out[name] ?? idle;
    return { name, status: station.status, detail: station.detail, declared: declared === name };
  });
}

export function listRuns(tail: Tail, now: number | null = null) {
  const at = now ?? Date.now() / 1000;
  const markers = readMarkers();
  const rows: any[] = [];
  const seen = new Set<string>();
  let names: string[] = [];
  try {
    names = fs.readdirSync(eventsDir()).sort();
  } catch {
    names = [];
  }
  for (const name of names) {
    if (!name.endsWith(".jsonl")) continue;
    const runId = name.slice(0, -6);
    seen.add(runId);
    const marker = markers.get(runId) ?? null;
    const state = reduce(tail.read(path.join(eventsDir(), name), parseEvent), marker);
    const { ended, status } = progress(state, marker, at);
    const made = state.rows[state.current].build;
    rows.push({ run: runId, name: path.basename(state.run.project || "") || runId, project: state.run.project,
                plan: state.run.plan, state: status, started: state.run.started,
                ended: state.run.ended ?? (ended ? state.lastTs : null),
                chunk: typeof made?.chunk === "number" ? made.chunk : null, of: made?.of ?? null,
                final: isFinal(made),
                chunks: new Set(state.rows.map((row) => row.build?.chunk).filter((n) => typeof n === "number")).size });
  }
  for (const [runId, marker] of markers) {
    if (seen.has(runId)) continue;
    rows.push({ run: runId, name: path.basename(marker.project || runId), project: marker.project ?? null,
                plan: null, state: "stale", started: isoToEpoch(marker.started), ended: null, chunk: null,
                of: null, final: false, chunks: 0, no_events: true });
  }
  const order: Record<string, number> = { running: 0, waiting: 0, stale: 1, ended: 2 };
  return rows.sort((a, b) => order[a.state] - order[b.state] || (b.started || 0) - (a.started || 0));
}

export function runState(runId: string, tail: Tail, now: number | null = null) {
  const file = path.join(eventsDir(), runId + ".jsonl");
  const marker = readMarkers().get(runId) ?? null;
  if (!fs.existsSync(file) && marker === null) return null;
  return build(runId, tail.read(file, parseEvent), tail, now, marker);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const tail = new Tail();
  const runId = process.argv[2];
  const found = runId ? runState(runId, tail) : listRuns(tail);
  if (found === null) {
    console.error("no such run: " + runId);
    process.exit(1);
  }
  console.log(JSON.stringify(found, null, 1));
}
