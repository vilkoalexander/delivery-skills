#!/usr/bin/env node
// Runs as is on Node 22.18+ (type stripping): erasable syntax only, no enums, no parameter properties.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const STALE_AFTER_S = 30 * 60;
const FEED_LIMIT = 300;
// Models seen running past 200k on this machine; everything else is assumed 200k.
export const WINDOW_1M_MODELS = ["fable"];
const SIDE_AGENTS = ["Explore", "Plan", "web-fetch", "claude-code-guide", "statusline-setup"];
const STATIONS = ["implement", "gate", "review", "fix", "verify", "cross", "you"] as const;

export type Tokens = { in: number; out: number; cw: number; cr: number };
export const ZERO: Tokens = { in: 0, out: 0, cw: 0, cr: 0 };

export type RunEvent = { ev: string; ts?: number; src?: string; agent?: string | null; [key: string]: any };
export type UsageItem = Tokens & { id: string; ts: number | null; model: string };
export type Marker = { project?: string; started?: string; run?: string };
type OpenTool = { tool: string; what: string; since: number };
type StationName = (typeof STATIONS)[number];
export type Station = { name: StationName; status: string; detail: string; declared: boolean };
type Chunk = {
  n: number | null; of: number | null; name: string | null; risk: string | null; phase: string | null;
  round: number; final: boolean; start: number | null; end: number | null; fixMarks: number; decision: string | null;
};
type Agent = {
  id: string; type: string | null; seat: string; start: number; end: number | null; calls: number;
  open: Map<string, OpenTool>; chunk: number; station: string; transcript: string | null;
  agentTranscript: string | null; desc: string | null; alias: string | null;
};
type Gate = {
  start: number; end: number | null; ok: boolean | null; chunk: number;
  steps: { step: string; ok: boolean | null; s: number | null }[];
};
type Cross = { id: string | null; start: number; end: number | null; ok: boolean | null; chunk: number };
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
  return "implement";
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

function emptyChunk(start: number | null): Chunk {
  return { n: null, of: null, name: null, risk: null, phase: null, round: 0, final: false, start, end: null,
           fixMarks: 0, decision: null };
}

export function build(runId: string, input: RunEvent[], tail: Tail, now: number | null = null,
                      marker: Marker | null = null) {
  const at = now ?? Date.now() / 1000;
  const events = [...input].sort((a, b) => (a.ts || 0) - (b.ts || 0));
  const run = { project: marker?.project ?? null, branch: null as string | null, plan: null as string | null,
                started: null as number | null, ended: null as number | null };
  const chunks: Chunk[] = [emptyChunk(null)];
  const agents = new Map<string, Agent>();
  const controller = { calls: 0, open: new Map<string, OpenTool>(), sid: null as string | null,
                       transcripts: [] as string[], lastEv: null as string | null };
  const dispatches: { sub: string | null; model: string | null; desc: string; taken: boolean }[] = [];
  const gates: Gate[] = [];
  const crosses: Cross[] = [];
  const feed: { ts: number; kind: string; who: string; text: string }[] = [];
  let lastTs: number | null = null;

  const strip = (what: unknown): string => {
    const text = typeof what === "string" ? what : "";
    return run.project ? text.split(run.project + "/").join("") : text;
  };
  const say = (ts: number, kind: string, who: string, text: string) => feed.push({ ts, kind, who, text });

  const getAgent = (event: RunEvent, ts: number): Agent => {
    const id = event.agent as string;
    let agent = agents.get(id);
    if (!agent) {
      const type: string | null = event.agent_type ?? null;
      const match = dispatches.find((d) => !d.taken && (d.sub === type || d.sub === null));
      if (match) match.taken = true;
      agent = { id, type, seat: shortType(type), start: ts, end: null, calls: 0, open: new Map(),
                chunk: chunks.length - 1, station: stationFor(type, chunks.at(-1)!.phase),
                transcript: event.transcript ?? null, agentTranscript: null,
                desc: match?.desc || null, alias: match?.model ?? null };
      agents.set(id, agent);
      say(ts, "agent", agent.seat, "started" + (agent.desc ? ": " + agent.desc : ""));
    }
    return agent;
  };

  for (const event of events) {
    const ts = event.ts;
    const kind = event.ev;
    if (typeof ts !== "number") continue;
    lastTs = ts;
    if (run.started === null) {
      run.started = ts;
      chunks[0].start = ts;
    }
    let current = chunks.at(-1)!;
    const isHook = event.src === "hook";
    let actor: Agent | null = null;
    let who: string;
    if (isHook && event.agent) {
      actor = getAgent(event, ts);
      who = actor.seat;
    } else if (isHook) {
      who = "controller";
      controller.lastEv = kind;
      if (event.sid) controller.sid = event.sid;
      if (event.transcript && !controller.transcripts.includes(event.transcript)) {
        controller.transcripts.push(event.transcript);
      }
    } else {
      who = event.src || "script";
    }
    const holder = actor ?? controller;

    if (kind === "run_start") {
      run.project = event.project || run.project;
      run.branch = event.branch ?? null;
      say(ts, "run", "run", "run started on " + path.basename(run.project || "?"));
    } else if (kind === "run_stop") {
      run.ended = ts;
      say(ts, "run", "run", "run ended");
    } else if (kind === "mark") {
      const isFinal = event.phase === "final";
      const same = isFinal ? current.final : !current.final && current.n === (event.chunk ?? null);
      if (!same) {
        current.end = ts;
        current = { ...emptyChunk(ts), n: event.chunk ?? null, final: isFinal };
        chunks.push(current);
      }
      if (event.of != null) current.of = event.of;
      if (event.name != null) current.name = event.name;
      if (event.risk != null) current.risk = event.risk;
      if (event.plan) run.plan = event.plan;
      current.phase = event.phase ?? null;
      if (event.phase === "fix") {
        current.fixMarks += 1;
        current.round = Math.max(current.round, event.round || current.fixMarks);
      }
      const label = isFinal ? "final, whole tree" : `chunk ${event.chunk}`;
      say(ts, "mark", "controller", `${label}: ${event.phase}${event.round ? " round " + event.round : ""}`);
    } else if (kind === "agent_stop" && actor) {
      actor.end = ts;
      actor.open.clear();
      actor.agentTranscript = event.agent_transcript || actor.agentTranscript;
      say(ts, "agent", who, `stopped, ${actor.calls} calls, ${clock(ts - actor.start)}`);
    } else if (kind === "tool") {
      holder.calls += 1;
      const what = strip(event.what);
      holder.open.set(event.id || "t" + ts, { tool: event.tool, what, since: ts });
      if (actor) {
        actor.end = null;
      } else {
        if (event.tool === "Agent" || event.tool === "Task") {
          dispatches.push({ sub: event.sub ?? null, model: event.model ?? null, desc: what, taken: false });
        }
        if (what.includes("codex-companion")) {
          crosses.push({ id: event.id ?? null, start: ts, end: null, ok: null, chunk: chunks.length - 1 });
        }
      }
      say(ts, "tool", who, `${event.tool} ${what}`);
    } else if (kind === "tool_end") {
      holder.open.delete(event.id);
      for (const cross of crosses) {
        if (cross.id === event.id && cross.end === null) {
          cross.end = ts;
          cross.ok = Boolean(event.ok);
        }
      }
      if (event.ok === false) say(ts, "fail", who, `${event.tool} failed: ${event.error || ""}`);
    } else if (kind === "refusal") {
      for (const [key, tool] of holder.open) if (tool.tool === event.tool) holder.open.delete(key);
      say(ts, "refusal", who, `REFUSED ${event.tool || "stop"} ${strip(event.what)}: ${strip(event.reason)}`);
    } else if (kind === "turn_end") {
      controller.open.clear();
      say(ts, "turn", who, "turn ended");
    } else if (kind === "notify") {
      say(ts, "notify", who, "notification: " + (event.message || event.kind || ""));
    } else if (kind === "compact") {
      say(ts, "notify", who, `context compacted (${event.trigger || "?"})`);
    } else if (kind === "gate_start") {
      gates.push({ start: ts, end: null, ok: null, steps: [], chunk: chunks.length - 1 });
      say(ts, "gate", "gate", `static gate started on ${event.paths} paths`);
    } else if (kind === "gate_step_start" && gates.length) {
      gates.at(-1)!.steps.push({ step: event.step, ok: null, s: null });
    } else if (kind === "gate_step" && gates.length) {
      const steps = gates.at(-1)!.steps;
      let step = steps.findLast((s) => s.step === event.step && s.ok === null);
      if (!step) {
        step = { step: event.step, ok: null, s: null };
        steps.push(step);
      }
      step.ok = Boolean(event.ok);
      step.s = event.s ?? null;
      say(ts, step.ok ? "gate" : "fail", "gate", `${step.step} ${step.ok ? "ok" : "FAIL"}`);
    } else if (kind === "gate_end" && gates.length) {
      const gate = gates.at(-1)!;
      gate.end = ts;
      gate.ok = Boolean(event.ok);
      say(ts, gate.ok ? "gate" : "fail", "gate", "static gate " + (gate.ok ? "clean" : "FAILED"));
    } else if (kind === "chunk_logged") {
      const entry = event.entry || {};
      for (const chunk of chunks) if (chunk.n === entry.chunk && !chunk.final) chunk.decision = entry.decision ?? null;
      say(ts, "mark", "you", `chunk ${entry.chunk} ${entry.decision}`);
    }
  }

  const ended = run.ended !== null || marker === null;
  const edge = run.ended ?? (ended ? lastTs : at) ?? at;
  const anyRunning = !ended && [...agents.values()].some((a) => a.end === null);
  const waiting = !ended && controller.lastEv === "turn_end" && !anyRunning;
  const state = ended ? "ended" : waiting ? "waiting"
    : lastTs === null || at - lastTs > STALE_AFTER_S ? "stale" : "running";

  const currentOf = (open: Map<string, OpenTool>): OpenTool | null => {
    let latest: OpenTool | null = null;
    for (const tool of open.values()) if (!latest || tool.since > latest.since) latest = tool;
    return latest ? { tool: latest.tool, what: latest.what, since: latest.since } : null;
  };

  const agentRows: AgentRow[] = [...agents.values()].map((agent) => {
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
    fill: controllerUsage.fill, running: state === "running" && controller.lastEv !== "turn_end",
  };

  const chunkRows = chunks.map((chunk, index) => {
    const isLast = index === chunks.length - 1;
    const mine = agentRows.filter((a) => a.chunk === index);
    const myGates = gates.filter((g) => g.chunk === index);
    const controllerTokens = summarize(controllerItems, chunk.start, chunk.end ?? run.ended).tokens;
    return {
      index, n: chunk.n, of: chunk.of, name: chunk.name, risk: chunk.risk, final: chunk.final,
      phase: chunk.phase, start: chunk.start, end: chunk.end ?? (ended ? edge : null), decision: chunk.decision,
      tokens: mine.reduce((sum, a) => add(sum, a.tokens), controllerTokens), controller_tokens: controllerTokens,
      stations: stations(chunk, mine, myGates, crosses.filter((c) => c.chunk === index), isLast, waiting, ended,
                         chunk.end ?? edge),
      gate: lastGate(myGates),
      empty: chunks.length > 1 && index === 0 && !mine.length && !myGates.length
        && !crosses.some((c) => c.chunk === 0),
    };
  });

  return {
    run: runId, project: run.project, name: path.basename(run.project || "") || runId, branch: run.branch,
    plan: run.plan, state, started: run.started, ended: run.ended ?? (ended ? lastTs : null), last: lastTs,
    now: at, chunks: chunkRows, agents: agentRows, controller: controllerRow,
    tokens: agentRows.reduce((sum, a) => add(sum, a.tokens), controllerUsage.tokens),
    feed: feed.slice(-FEED_LIMIT),
  };
}

function lastGate(gates: Gate[]) {
  const gate = gates.at(-1);
  if (!gate) return null;
  return { runs: gates.length, failed_runs: gates.filter((g) => g.ok === false).length, ok: gate.ok,
           start: gate.start, end: gate.end, steps: gate.steps.map((s) => ({ step: s.step, ok: s.ok, s: s.s })) };
}

function stations(chunk: Chunk, agents: AgentRow[], gates: Gate[], crosses: Cross[], isLast: boolean,
                  waiting: boolean, ended: boolean, stop: number): Station[] {
  const out = {} as Record<StationName, { status: string; detail: string }>;
  const idle = { status: "idle", detail: "" };

  for (const name of ["implement", "review", "fix", "verify"] as const) {
    const mine = agents.filter((a) => a.station === name);
    if (!mine.length) {
      out[name] = idle;
      continue;
    }
    const live = mine.some((a) => a.running);
    const span = (live ? stop : Math.max(...mine.map((a) => a.end as number))) - Math.min(...mine.map((a) => a.start));
    out[name] = { status: live ? "running" : "done",
                  detail: `${mine.length} agent${mine.length === 1 ? "" : "s"} · ${clock(span)}` };
  }
  if (chunk.round && out.fix.status !== "idle") {
    out.fix = { status: out.fix.status, detail: `round ${chunk.round} · ${out.fix.detail}` };
  } else if (chunk.round) {
    out.fix = { status: chunk.phase === "fix" && isLast && !ended ? "running" : "done", detail: `round ${chunk.round}` };
  }

  const gate = gates.at(-1);
  if (!gate) {
    out.gate = idle;
  } else {
    const failed = gates.filter((g) => g.ok === false).length;
    const note = `run ${gates.length}` + (failed ? ` · ${failed} failed` : "");
    if (gate.end !== null) {
      out.gate = { status: gate.ok ? "done" : "failed", detail: `${clock(gate.end - gate.start)} · ${note}` };
    } else if (ended) {
      out.gate = { status: "failed", detail: "no result · " + note };
    } else {
      const step = gate.steps.findLast((s) => s.ok === null)?.step;
      out.gate = { status: "running", detail: `${step || "starting"} · ${note}` };
    }
  }

  const cross = crosses.at(-1);
  if (!cross) {
    out.cross = idle;
  } else if (cross.end === null) {
    out.cross = { status: ended ? "done" : "running", detail: clock(stop - cross.start) };
  } else {
    out.cross = { status: cross.ok ? "done" : "failed", detail: clock(cross.end - cross.start) };
  }

  if (chunk.decision) out.you = { status: "done", detail: chunk.decision };
  else if (isLast && waiting) out.you = { status: "waiting", detail: "your turn" };
  else if (!isLast) out.you = { status: "done", detail: "moved on" };
  else out.you = idle;

  const reached = STATIONS.findLastIndex((name) => out[name].status !== "idle");
  return STATIONS.map((name, i) => {
    const skipped = out[name].status === "idle" && (i < reached || !isLast || ended);
    const station = skipped ? { status: "skipped", detail: "" } : out[name];
    return { name, status: station.status, detail: station.detail,
             declared: chunk.phase === name || (name === "you" && chunk.phase === "report") };
  });
}

export function listRuns(tail: Tail, now: number | null = null) {
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
    const events = tail.read(path.join(eventsDir(), name), parseEvent);
    const full = build(runId, events, new Tail(), now, markers.get(runId) ?? null);
    const chunk = full.chunks.findLast((c) => !c.empty) ?? full.chunks.at(-1)!;
    rows.push({ run: runId, name: full.name, project: full.project, plan: full.plan, state: full.state,
                started: full.started, ended: full.ended, chunk: chunk.n, of: chunk.of, final: chunk.final,
                chunks: full.chunks.filter((c) => c.n !== null).length });
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
