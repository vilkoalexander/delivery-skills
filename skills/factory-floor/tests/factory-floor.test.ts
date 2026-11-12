import assert from "node:assert/strict";
import fs from "node:fs";
import type http from "node:http";
import os from "node:os";
import path from "node:path";
import { after, before, beforeEach, afterEach, describe, test } from "node:test";
import { makeServer } from "../scripts/serve.ts";
import * as state from "../scripts/state.ts";

const RUN = "abc123abc123-20261112T100000Z";
const T0 = 1_794_000_000;

let root: string, runs: string, events: string, projects: string, transcript: string, tail: state.Tail;
const saved = { run: process.env.DELIVERY_RUN_DIR, events: process.env.DELIVERY_EVENTS_DIR };

beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), "ff-"));
  runs = path.join(root, "state", "runs");
  events = path.join(root, "state", "events");
  projects = path.join(root, "projects", "slug");
  for (const dir of [runs, events, projects]) fs.mkdirSync(dir, { recursive: true });
  process.env.DELIVERY_RUN_DIR = runs;
  delete process.env.DELIVERY_EVENTS_DIR;
  transcript = path.join(projects, "s1.jsonl");
  tail = new state.Tail();
});

afterEach(() => {
  fs.rmSync(root, { recursive: true, force: true });
  for (const [key, value] of [["DELIVERY_RUN_DIR", saved.run], ["DELIVERY_EVENTS_DIR", saved.events]] as const) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

const iso = (ts: number) => new Date(ts * 1000).toISOString();

function assistant(id: string, ts: number, over: Record<string, any> = {}) {
  const u = { model: "claude-sonnet-5-5", inp: 10, out: 100, cw: 1000, cr: 5000, ...over };
  return { type: "assistant", timestamp: iso(ts), message: { id, model: u.model, usage: {
    input_tokens: u.inp, output_tokens: u.out, cache_creation_input_tokens: u.cw, cache_read_input_tokens: u.cr } } };
}

function writeLines(file: string, items: unknown[], append = false) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const text = items.map((item) => JSON.stringify(item) + "\n").join("");
  if (append) fs.appendFileSync(file, text);
  else fs.writeFileSync(file, text);
}

function marker(run: string | null = RUN, name = "abc123abc123", project = "/work/app") {
  fs.writeFileSync(path.join(runs, name),
    JSON.stringify({ project, started: "2026-11-12T10:00:00Z", ...(run ? { run } : {}) }));
}

const hook = (ev: string, t: number, agent: string | null = null, agentType: string | null = null, extra = {}) =>
  ({ ts: T0 + t, run: RUN, src: "hook", ev, sid: "s1", agent, agent_type: agentType, transcript, ...extra });
const script = (src: string, ev: string, t: number, extra = {}) => ({ ts: T0 + t, run: RUN, src, ev, ...extra });
const agentFile = (id: string) => path.join(projects, "s1", "subagents", `agent-${id}.jsonl`);
const build = (list: state.RunEvent[], now = T0 + 1000, withMarker = true) =>
  state.build(RUN, list, tail, now, withMarker ? { project: "/work/app" } : null);
const station = (chunk: { stations: state.Station[] }, name: string) => chunk.stations.find((s) => s.name === name)!;
const usage = (entry: unknown) => state.parseUsage(Buffer.from(JSON.stringify(entry)))!;

const GP = "general-purpose";
const REV = "delivery-skills:reviewer";
const VER = "delivery-skills:verifier";

function chunkEvents(): state.RunEvent[] {
  return [
    script("run", "run_start", 0, { project: "/work/app", branch: "feat" }),
    hook("tool_end", 1, null, null, { id: "t0", tool: "Bash", ok: true }),
    script("mark", "mark", 2, { phase: "implement", chunk: 1, of: 3, name: "totals", risk: "medium", plan: "plans/b.md" }),
    hook("tool", 3, null, null, { id: "d1", tool: "Agent", what: "Build totals", sub: null, model: "haiku" }),
    hook("agent_start", 4, "a1", GP),
    hook("tool", 5, "a1", GP, { id: "t1", tool: "Read", what: "/work/app/src/a.ts" }),
    hook("tool_end", 6, "a1", GP, { id: "t1", tool: "Read", ok: true }),
    hook("tool", 7, "a1", GP, { id: "t2", tool: "Edit", what: "/work/app/src/a.ts" }),
  ];
}

function fullChunk(): state.RunEvent[] {
  return [
    ...chunkEvents(),
    hook("agent_stop", 9, "a1", GP),
    script("mark", "mark", 10, { phase: "gate", chunk: 1, of: 3 }),
    script("gate", "gate_start", 11, { paths: 4 }),
    script("gate", "gate_step_start", 11, { step: "typecheck" }),
    script("gate", "gate_step", 13, { step: "typecheck", ok: true, s: 2 }),
    script("gate", "gate_step_start", 13, { step: "lint" }),
    script("gate", "gate_step", 14, { step: "lint", ok: false, s: 1 }),
    script("gate", "gate_end", 14, { ok: false }),
    script("gate", "gate_start", 20, { paths: 4 }),
    script("gate", "gate_step_start", 20, { step: "typecheck" }),
    script("gate", "gate_step", 22, { step: "typecheck", ok: true, s: 2 }),
    script("gate", "gate_step_start", 22, { step: "lint" }),
    script("gate", "gate_step", 23, { step: "lint", ok: true, s: 1 }),
    script("gate", "gate_end", 23, { ok: true }),
    script("mark", "mark", 24, { phase: "review", chunk: 1, of: 3 }),
    hook("tool", 25, null, null, { id: "d2", tool: "Agent", what: "Review chunk 1", sub: REV, model: "sonnet" }),
    hook("agent_start", 26, "r1", REV),
    hook("tool", 27, "r1", REV, { id: "t5", tool: "Bash", what: "git add ." }),
    hook("refusal", 27.1, "r1", REV, { tool: "Bash", what: "git add .", reason: "reviewer seat is read-only" }),
    hook("agent_stop", 30, "r1", REV),
    script("mark", "mark", 31, { phase: "fix", chunk: 1, of: 3, round: 1 }),
    hook("agent_start", 32, "a2", GP),
    hook("agent_stop", 35, "a2", GP),
    hook("agent_start", 36, "r2", REV),
    hook("agent_stop", 38, "r2", REV),
    script("mark", "mark", 39, { phase: "verify", chunk: 1, of: 3 }),
    hook("agent_start", 40, "v1", VER),
    hook("agent_stop", 45, "v1", VER),
    hook("tool", 46, null, null, { id: "x1", tool: "Bash", what: "node /p/scripts/codex-companion.mjs adversarial-review" }),
    hook("tool_end", 50, null, null, { id: "x1", tool: "Bash", ok: true }),
    script("mark", "mark", 51, { phase: "report", chunk: 1, of: 3 }),
    hook("turn_end", 52),
  ];
}

describe("Tail", () => {
  test("reads only complete new lines", () => {
    const file = path.join(root, "e.jsonl");
    fs.writeFileSync(file, '{"ev":"a"}\n{"ev":"b"');
    assert.deepEqual(tail.read(file, state.parseEvent).map((e) => e.ev), ["a"]);
    fs.appendFileSync(file, '}\n{"ev":"c"}\n');
    assert.deepEqual(tail.read(file, state.parseEvent).map((e) => e.ev), ["a", "b", "c"]);
  });

  test("skips broken lines and missing files", () => {
    const file = path.join(root, "e.jsonl");
    fs.writeFileSync(file, 'not json\n{"ev":"a"}\n[1]\n{"no":"ev"}\nnull\n');
    assert.equal(tail.read(file, state.parseEvent).length, 1);
    assert.deepEqual(tail.read(path.join(root, "nope"), state.parseEvent), []);
    assert.deepEqual(tail.read(null, state.parseEvent), []);
  });

  test("starts over when the file shrinks", () => {
    const file = path.join(root, "e.jsonl");
    writeLines(file, [{ ev: "a" }, { ev: "b" }]);
    tail.read(file, state.parseEvent);
    writeLines(file, [{ ev: "z" }]);
    assert.deepEqual(tail.read(file, state.parseEvent).map((e) => e.ev), ["z"]);
  });
});

describe("usage", () => {
  test("repeated entries of one message count once", () => {
    writeLines(transcript, [
      { type: "user", message: { content: "an assistant said hi" } },
      assistant("m1", T0 + 1), assistant("m1", T0 + 1), assistant("m1", T0 + 1),
      assistant("m2", T0 + 2, { inp: 4, out: 50, cw: 200, cr: 7000 }),
    ]);
    const got = state.summarize(tail.read(transcript, state.parseUsage));
    assert.deepEqual(got.tokens, { in: 14, out: 150, cw: 1200, cr: 12000 });
    assert.equal(got.messages, 2);
    assert.equal(got.ctx, 4 + 200 + 7000);
    assert.equal(got.model, "claude-sonnet-5-5");
  });

  test("window is 200k until a request passes it", () => {
    const small = state.summarize([usage(assistant("m1", T0, { cr: 50_000 }))]);
    assert.equal(small.window, 200_000);
    assert.equal(small.fill, 0.2551);
    assert.equal(state.summarize([usage(assistant("m1", T0, { cr: 250_000 }))]).window, 1_000_000);
    assert.equal(state.summarize([usage(assistant("m1", T0, { model: "claude-fable-5-2" }))]).window, 1_000_000);
  });

  test("interval and synthetic entries", () => {
    writeLines(transcript, [
      assistant("m1", T0 + 1), assistant("m2", T0 + 50), assistant("m3", T0 + 99),
      assistant("m4", T0 + 60, { model: "<synthetic>" }),
    ]);
    const items = tail.read(transcript, state.parseUsage);
    assert.equal(items.length, 3);
    assert.equal(state.summarize(items, T0 + 10, T0 + 99).tokens.out, 100);
  });

  test("empty transcript", () => {
    const got = state.summarize([]);
    assert.deepEqual(got.tokens, state.ZERO);
    assert.equal(got.model, null);
    assert.equal(got.ctx, 0);
  });
});

describe("build", () => {
  test("header and running agent", () => {
    const got = build(chunkEvents(), T0 + 20);
    assert.deepEqual([got.name, got.branch, got.plan, got.state], ["app", "feat", "plans/b.md", "running"]);
    const chunk = got.chunks.at(-1)!;
    assert.deepEqual([chunk.n, chunk.of, chunk.name, chunk.risk], [1, 3, "totals", "medium"]);
    assert.equal(got.chunks[0].empty, true);
    const agent = got.agents[0];
    assert.equal(agent.running, true);
    assert.deepEqual([agent.seat, agent.desc, agent.model, agent.calls], [GP, "Build totals", "haiku", 2]);
    assert.deepEqual(agent.current, { tool: "Edit", what: "src/a.ts", since: T0 + 7 });
    assert.equal(agent.station, "implement");
    assert.equal(station(chunk, "implement").status, "running");
    assert.equal(station(chunk, "implement").declared, true);
    assert.equal(station(chunk, "gate").status, "idle");
  });

  test("first tool call marks the start when there is no start event", () => {
    const got = build(chunkEvents().filter((e) => e.ev !== "agent_start"), T0 + 20);
    assert.equal(got.agents[0].start, T0 + 5);
    assert.equal(got.agents[0].running, true);
  });

  test("model and tokens come from the transcripts", () => {
    writeLines(agentFile("a1"), [assistant("x1", T0 + 5, { model: "claude-haiku-5-5" })]);
    writeLines(transcript, [
      assistant("c0", T0 - 500, { out: 999 }), assistant("c1", T0 + 1, { out: 7 }), assistant("c2", T0 + 3, { out: 11 }),
    ]);
    const got = build(chunkEvents(), T0 + 20);
    assert.equal(got.agents[0].model, "claude-haiku-5-5");
    assert.equal(got.agents[0].tokens.out, 100);
    assert.equal(got.controller.tokens.out, 18);
    assert.equal(got.controller.model, "claude-sonnet-5-5");
    assert.equal(got.chunks.at(-1)!.controller_tokens.out, 11);
    assert.equal(got.chunks.at(-1)!.tokens.out, 111);
    assert.equal(got.tokens.out, 118);
  });

  test("agent transcript path from the stop event wins", () => {
    const other = path.join(root, "elsewhere.jsonl");
    writeLines(other, [assistant("x1", T0 + 5, { model: "claude-opus-5-5" })]);
    const got = build([...chunkEvents(), hook("agent_stop", 9, "a1", GP, { agent_transcript: other })]);
    assert.equal(got.agents[0].model, "claude-opus-5-5");
  });

  test("every station of a finished chunk", () => {
    const got = build(fullChunk(), T0 + 60);
    assert.equal(got.state, "waiting");
    const chunk = got.chunks.at(-1)!;
    assert.deepEqual(Object.fromEntries(chunk.stations.map((s) => [s.name, s.status])), {
      implement: "done", gate: "done", review: "done", fix: "done", verify: "done", cross: "done", you: "waiting" });
    assert.match(station(chunk, "gate").detail, /1 failed/);
    assert.match(station(chunk, "fix").detail, /round 1/);
    assert.match(station(chunk, "fix").detail, /2 agents/);
    assert.equal(chunk.gate!.runs, 2);
    assert.deepEqual(chunk.gate!.steps.map((s) => [s.step, s.ok]), [["typecheck", true], ["lint", true]]);
    const seats = Object.fromEntries(got.agents.map((a) => [a.id, [a.seat, a.station]]));
    assert.deepEqual(seats.r1, ["reviewer", "review"]);
    assert.deepEqual(seats.r2, ["reviewer", "fix"]);
    assert.deepEqual(seats.v1, ["verifier", "verify"]);
    assert.equal(got.agents.find((a) => a.id === "r1")!.desc, "Review chunk 1");
    assert.equal(got.agents.some((a) => a.running), false);
  });

  test("refusal is in the feed with its reason and closes the call", () => {
    const all = fullChunk();
    const got = build(all.slice(0, all.findIndex((e) => e.ev === "refusal") + 1), T0 + 28);
    const refusals = got.feed.filter((f) => f.kind === "refusal");
    assert.equal(refusals.length, 1);
    assert.equal(refusals[0].who, "reviewer");
    assert.match(refusals[0].text, /reviewer seat is read-only/);
    const reviewer = got.agents.find((a) => a.id === "r1")!;
    assert.equal(reviewer.running, true);
    assert.equal(reviewer.current, null);
  });

  test("failed gate and running step", () => {
    const all = fullChunk();
    const cut = all.findIndex((e) => e.ev === "gate_end");
    const failed = build(all.slice(0, cut + 1), T0 + 15);
    assert.equal(station(failed.chunks.at(-1)!, "gate").status, "failed");
    assert.deepEqual(failed.chunks.at(-1)!.gate!.steps.at(-1), { step: "lint", ok: false, s: 1 });
    const gate = station(build(all.slice(0, cut - 1), T0 + 13.5).chunks.at(-1)!, "gate");
    assert.equal(gate.status, "running");
    assert.match(gate.detail, /lint/);
  });

  test("waiting only when no agent is running", () => {
    const list = [...chunkEvents(), hook("turn_end", 8)];
    assert.equal(build(list, T0 + 20).state, "running");
    list.push(hook("agent_stop", 9, "a1", GP));
    const got = build(list, T0 + 20);
    assert.equal(got.state, "waiting");
    assert.equal(station(got.chunks.at(-1)!, "you").status, "waiting");
    list.push(hook("prompt", 12));
    assert.equal(build(list, T0 + 20).state, "running");
  });

  test("agent held at stop runs again", () => {
    const got = build([...chunkEvents(), hook("agent_stop", 9, "a1", GP),
      hook("tool", 10, "a1", GP, { id: "t3", tool: "Bash", what: "npm test" })], T0 + 20);
    assert.equal(got.agents[0].running, true);
  });

  test("stale and ended", () => {
    assert.equal(build(chunkEvents(), T0 + 7 + state.STALE_AFTER_S + 1).state, "stale");
    const ended = build([...chunkEvents(), script("run", "run_stop", 100)]);
    assert.equal(ended.state, "ended");
    assert.equal(ended.ended, T0 + 100);
    assert.equal(ended.agents[0].running, false);
    const noMarker = build(chunkEvents(), T0 + 1000, false);
    assert.equal(noMarker.state, "ended");
    assert.equal(noMarker.ended, T0 + 7);
  });

  test("next chunk, final and decision", () => {
    const got = build([
      ...fullChunk(),
      hook("prompt", 60),
      script("log", "chunk_logged", 61, { entry: { chunk: 1, decision: "edited" } }),
      script("mark", "mark", 62, { phase: "implement", chunk: 2, of: 3, name: "screen", risk: "low" }),
      script("mark", "mark", 70, { phase: "final" }),
    ], T0 + 80);
    assert.deepEqual(got.chunks.map((c) => [c.n, c.final]), [[null, false], [1, false], [2, false], [null, true]]);
    const first = got.chunks[1];
    assert.equal(first.decision, "edited");
    assert.deepEqual(station(first, "you"), { name: "you", status: "done", detail: "edited", declared: true });
    assert.equal(first.end, T0 + 62);
    const second = got.chunks[2];
    assert.deepEqual([second.name, second.risk], ["screen", "low"]);
    assert.equal(station(second, "implement").status, "skipped");
    assert.equal(station(second, "you").detail, "moved on");
  });

  test("run without marks still shows observed work", () => {
    const got = build(chunkEvents().filter((e) => e.ev !== "mark"), T0 + 20);
    assert.equal(got.chunks.length, 1);
    assert.equal(got.chunks[0].n, null);
    assert.equal(got.chunks[0].empty, false);
    assert.equal(station(got.chunks[0], "implement").status, "running");
  });

  test("events out of order and without ts", () => {
    const got = build([...chunkEvents().reverse(), { ev: "tool", src: "hook" }], T0 + 20);
    assert.equal(got.agents[0].current!.tool, "Edit");
  });

  test("side agents stay out of the stations", () => {
    const got = build([...chunkEvents().slice(0, 3), hook("agent_start", 4, "e1", "Explore")], T0 + 20);
    assert.equal(got.agents[0].station, "other");
    assert.equal(station(got.chunks.at(-1)!, "implement").status, "idle");
  });
});

describe("list", () => {
  test("active first, and a marker without events", () => {
    marker();
    marker(null, "feedfeedfeed", "/work/old");
    writeLines(path.join(events, RUN + ".jsonl"), [
      script("run", "run_start", 0, { project: "/work/app", branch: "feat" }),
      script("mark", "mark", 2, { phase: "implement", chunk: 2, of: 5, plan: "plans/b.md" }),
      hook("tool", 3, null, null, { id: "t1", tool: "Read", what: "x" }),
    ]);
    const done = "0000aaaa0000-20261101T100000Z";
    writeLines(path.join(events, done + ".jsonl"), [
      { ts: T0 + 500, run: done, src: "run", ev: "run_start", project: "/work/done" },
      { ts: T0 + 600, run: done, src: "run", ev: "run_stop" },
    ]);
    const rows = state.listRuns(tail, T0 + 10);
    assert.deepEqual(rows.map((r) => [r.name, r.state]), [["app", "running"], ["old", "stale"], ["done", "ended"]]);
    assert.deepEqual([rows[0].plan, rows[0].chunk, rows[0].of], ["plans/b.md", 2, 5]);
    assert.equal(rows[1].no_events, true);
    assert.equal(rows[1].run, "feedfeedfeed-0");
  });

  test("nothing on disk", () => {
    process.env.DELIVERY_RUN_DIR = path.join(root, "missing", "runs");
    assert.deepEqual(state.listRuns(tail), []);
    assert.equal(state.runState("nope", tail), null);
  });
});

describe("serve", () => {
  let server: http.Server, port: number;

  before(async () => {
    server = makeServer();
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    port = (server.address() as { port: number }).port;
  });
  after(() => new Promise((resolve) => server.close(resolve)));
  beforeEach(() => {
    marker();
    writeLines(path.join(events, RUN + ".jsonl"), [script("run", "run_start", 0, { project: "/work/app", branch: "feat" })]);
  });

  const get = async (url: string) => {
    const res = await fetch(`http://127.0.0.1:${port}${url}`);
    return { code: res.status, body: await res.text() };
  };

  test("page and api", async () => {
    const page = await get("/");
    assert.equal(page.code, 200);
    assert.match(page.body, /Factory floor/);
    const list = await get("/api/runs");
    assert.deepEqual([list.code, JSON.parse(list.body)[0].run], [200, RUN]);
    const one = await get("/api/run?id=" + RUN);
    assert.deepEqual([one.code, JSON.parse(one.body).name], [200, "app"]);
  });

  test("new events show on the next request", async () => {
    await get("/api/run?id=" + RUN);
    writeLines(path.join(events, RUN + ".jsonl"), [script("mark", "mark", 2, { phase: "review", chunk: 4, of: 9 })], true);
    assert.equal(JSON.parse((await get("/api/run?id=" + RUN)).body).chunks.at(-1).n, 4);
  });

  test("refuses bad ids, unknown paths, foreign hosts and writes", async () => {
    assert.equal((await get("/api/run?id=../../etc/passwd")).code, 400);
    assert.equal((await get("/api/run?id=nope")).code, 404);
    assert.equal((await get("/etc/passwd")).code, 404);
    assert.equal((await fetch(`http://127.0.0.1:${port}/api/runs`, { method: "POST" })).status, 405);
    const foreign = await new Promise<number>((resolve, reject) => {
      import("node:http").then(({ request }) => request({ host: "127.0.0.1", port, path: "/api/runs",
        headers: { Host: "evil.example" } }, (res) => { res.resume(); resolve(res.statusCode!); }).on("error", reject).end());
    });
    assert.equal(foreign, 403);
  });
});
