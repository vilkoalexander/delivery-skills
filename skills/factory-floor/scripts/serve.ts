#!/usr/bin/env node
import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { eventsDir, listRuns, runState, Tail } from "./state.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATE = path.join(here, "..", "template.html");
const RUN_ID = /^[A-Za-z0-9_-]{1,80}$/;

export function makeServer(): http.Server {
  const tail = new Tail();
  const send = (res: http.ServerResponse, code: number, body: string | Buffer, kind: string) => {
    res.writeHead(code, { "Content-Type": kind, "Cache-Control": "no-store" });
    res.end(body);
  };
  const json = (res: http.ServerResponse, value: unknown, code = 200) =>
    send(res, code, JSON.stringify(value), "application/json");

  return http.createServer((req, res) => {
    // A page on another origin could otherwise reach this server through a DNS name pointed at loopback.
    const host = (req.headers.host || "").split(":")[0];
    if (host !== "127.0.0.1" && host !== "localhost") return send(res, 403, "forbidden", "text/plain");
    if (req.method !== "GET") return send(res, 405, "method not allowed", "text/plain");
    try {
      const url = new URL(req.url || "/", "http://127.0.0.1");
      if (url.pathname === "/") return send(res, 200, fs.readFileSync(TEMPLATE), "text/html; charset=utf-8");
      if (url.pathname === "/api/runs") return json(res, listRuns(tail));
      if (url.pathname === "/api/run") {
        const runId = url.searchParams.get("id") || "";
        if (!RUN_ID.test(runId)) return json(res, { error: "bad run id" }, 400);
        const found = runState(runId, tail);
        return found === null ? json(res, { error: "no such run" }, 404) : json(res, found);
      }
      return send(res, 404, "not found", "text/plain");
    } catch (error) {
      // One unreadable file must not take the page down.
      return json(res, { error: String(error) }, 500);
    }
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.includes("--help") || args.includes("-h")) {
    console.log("usage: node serve.ts [--port 4777] [--open]");
    process.exit(0);
  }
  const at = args.indexOf("--port");
  const port = at >= 0 ? Number(args[at + 1]) : 4777;
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    console.error("serve: --port needs a number");
    process.exit(2);
  }
  const server = makeServer();
  server.on("error", (error: NodeJS.ErrnoException) => {
    console.error(error.code === "EADDRINUSE" ? `serve: port ${port} is taken; pass --port <n>` : `serve: ${error.message}`);
    process.exit(1);
  });
  server.listen(port, "127.0.0.1", () => {
    const url = `http://127.0.0.1:${(server.address() as { port: number }).port}/`;
    console.log(`factory floor on ${url}  (events: ${eventsDir()})`);
    if (args.includes("--open")) {
      const opener = process.platform === "darwin" ? "open" : process.platform === "win32" ? "explorer" : "xdg-open";
      spawn(opener, [url], { stdio: "ignore", detached: true }).on("error", () => {}).unref();
    }
  });
}
