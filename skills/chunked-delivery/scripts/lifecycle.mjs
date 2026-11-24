#!/usr/bin/env node
// The life of a chunk, in one place. mark.sh asks this file whether a mark is
// permitted; the floor page, the run log and the retro ask it what a run did.
// Nothing else works out where a build starts or how many fix rounds it had.
//
//   node lifecycle.mjs check <events-file> key=value...   the fields of a permitted mark, one per
//                                                         line for event.sh; exit 2 with the reason
//   node lifecycle.mjs parse key=value...                 only reads the mark: exit 2 when it is malformed
//   node lifecycle.mjs status <events-file>               one line per chunk: where it is, what may come next
//   node lifecycle.mjs builds <events-file>...            one JSON line per build
//
//   LIFECYCLE_MODE   gated (default) or long; run.sh keeps it in the run marker
//
// Words. A chunk is built one or more times: a build starts at a `test` or
// `implement` mark, and the next one starts when such a mark follows a
// `report`. A fix round is a `fix` mark; its stage says who asked for it:
//   static   the gate, before any reviewer saw the build
//   review   a reviewer, a verifier or the other model, before the report
//   human    the human, after the report
// After the `final` mark the same phases, with no chunk number, belong to the
// whole-tree pass: one more build, with the key "final".
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const RISKS = ['low', 'medium', 'high'];
export const MODES = ['gated', 'long'];
export const DECISIONS = ['accepted', 'edited', 'rejected', 'stopped'];

// phase: the station the floor page shows it under, and the phases that may follow it.
export const PHASES = {
  test: { station: 'tests', next: ['test', 'implement', 'report'] },
  implement: { station: 'implement', next: ['implement', 'gate', 'report'] },
  gate: { station: 'gate', next: ['gate', 'fix', 'review', 'verify', 'cross', 'report'] },
  review: { station: 'review', next: ['review', 'fix', 'verify', 'cross', 'report'] },
  fix: { station: 'fix', next: ['gate'] },
  verify: { station: 'verify', next: ['verify', 'review', 'fix', 'cross', 'report'] },
  cross: { station: 'cross', next: ['cross', 'fix', 'report'] },
  report: { station: 'you', next: ['report', 'fix'] },
  final: { station: 'final', next: ['verify', 'review', 'cross', 'gate'] },
};
export const STARTS = ['test', 'implement'];

// Fix rounds a build may have at each stage. `human` has no limit: the human asked.
export const FIX_LIMIT = {
  static: { low: 2, medium: 2, high: 2, final: 2 },
  review: { low: 0, medium: 3, high: 5, final: 5 },
};
const NEEDS_VERIFY = ['medium', 'high'];
// A report before these ran is only for a build that cannot go on: parked=<reason>.
const REPORT_NEEDS_PARKED_AFTER = ['test', 'implement'];

const FINAL = 'final';
const keyOf = mark => (mark.scope === FINAL || mark.phase === FINAL ? FINAL : mark.chunk);

function newBuild(mark, number, previous) {
  return {
    run: mark.run,
    chunk: keyOf(mark),
    build: number,
    of: mark.of ?? previous?.of ?? null,
    name: mark.name ?? previous?.name ?? null,
    plan: mark.plan ?? previous?.plan ?? null,
    risk: keyOf(mark) === FINAL ? FINAL : (mark.risk ?? previous?.risk ?? null),
    marks: [],
    phases: [],
    fix: { static: 0, review: 0, human: 0 },
    started: mark.ts,
    reportedAt: null,
    verified: false,
    parked: null,
    decision: null,
  };
}

function stageOfFix(build) {
  if (build.reportedAt !== null) return 'human';
  return build.phases.some(phase => ['review', 'verify', 'cross'].includes(phase)) ? 'review' : 'static';
}

function addMark(build, mark) {
  if (mark.phase === 'fix') build.fix[mark.stage ?? stageOfFix(build)]++;
  if (mark.phase === 'verify') build.verified = true;
  if (mark.phase === 'report') {
    build.reportedAt = mark.ts;
    build.parked = mark.parked ?? null;
  }
  build.risk ??= mark.risk ?? null;
  build.name ??= mark.name ?? null;
  build.marks.push(mark);
  build.phases.push(mark.phase);
}

// Every build of one run, in the order they started. `events` are the parsed lines of its event file.
export function builds(events) {
  const all = [];
  const latest = new Map();
  for (const event of events) {
    if (event.ev === 'mark') {
      const key = keyOf(event);
      let build = latest.get(key);
      const restarts = build && STARTS.includes(event.phase) && build.reportedAt !== null;
      if (!build || restarts) {
        build = newBuild(event, (build?.build ?? 0) + 1, build);
        latest.set(key, build);
        all.push(build);
      }
      addMark(build, event);
    } else if (event.ev === 'chunk_logged' && event.entry) {
      const build = latest.get(event.entry.chunk);
      if (build) build.decision = event.entry.decision ?? null;
    }
  }
  return all;
}

export const lastPhase = build => build.phases[build.phases.length - 1];

// The phases that may follow the last mark of a build. An empty build may start.
export function nextPhases(build) {
  if (!build || !build.phases.length) return STARTS;
  const next = [...PHASES[lastPhase(build)].next];
  if (build.reportedAt !== null && build.chunk !== FINAL && build.decision === 'rejected') next.push(...STARTS);
  return next;
}

const promptAfter = (events, ts) => events.some(event => event.ev === 'prompt' && !event.agent && event.ts > ts);

// Why a chunk cannot start while an earlier one waits for the human. Null when it can.
function waitsForTheHuman(all, events, chunk, mode) {
  if (mode !== 'gated') return null;
  const waiting = all.filter(build => build.chunk !== chunk && build.chunk !== FINAL && build === lastBuildOf(all, build.chunk));
  for (const build of waiting) {
    const label = `chunk ${build.chunk}`;
    if (build.reportedAt === null) return `${label} has no report yet: finish it, or report it with parked=<reason>`;
    if (!['accepted', 'edited'].includes(build.decision)) {
      return `${label} has a report and no accepted decision in the run log: wait for the human, then add the run-log line`;
    }
  }
  const latest = waiting.sort((a, b) => a.reportedAt - b.reportedAt).pop();
  if (latest && !promptAfter(events, latest.reportedAt)) {
    return `chunk ${latest.chunk} was reported and the human has not answered since: stop and wait`;
  }
  return null;
}

const lastBuildOf = (all, chunk) => all.filter(build => build.chunk === chunk).pop();

// The reason a mark is not permitted, or null. `mark` is the new mark, not yet in `events`.
export function refusal(events, mark, mode = 'gated') {
  const all = builds(events);
  const finalStarted = all.some(build => build.chunk === FINAL);
  const key = mark.phase === FINAL || mark.chunk === undefined ? FINAL : mark.chunk;
  const build = lastBuildOf(all, key);
  const label = key === FINAL ? 'the final pass' : `chunk ${key}`;

  if (mark.phase === FINAL) return finalStarted ? 'the final pass has started already' : null;
  if (key === FINAL && !finalStarted) return 'missing chunk (only the phases after phase=final take none)';

  const startsBuild = STARTS.includes(mark.phase) && (!build || build.reportedAt !== null);
  if (startsBuild) {
    if (build && build.decision !== 'rejected') {
      return `${label} has a report and no rejected decision in the run log: add the line (decision=rejected) before you build the chunk again`;
    }
    if (!build && !mark.risk) return `the first mark of ${label} needs risk=<${RISKS.join('|')}>`;
    return build ? null : waitsForTheHuman(all, events, key, mode);
  }
  if (!build) {
    return `${label} has no build: it starts with phase=${STARTS.join(' or phase=')}`;
  }

  const allowed = nextPhases(build);
  if (!allowed.includes(mark.phase)) {
    return `${label} is at ${lastPhase(build)}; next is one of: ${allowed.join(', ')}`;
  }

  const risk = build.risk ?? mark.risk;
  if (mark.phase === 'fix') {
    const stage = stageOfFix(build);
    const limit = FIX_LIMIT[stage]?.[risk];
    if (limit !== undefined && build.fix[stage] >= limit) {
      const what = stage === 'static' ? 'static rounds' : 'fix rounds';
      return `${label} is ${risk} risk and is at its limit of ${limit} ${what}: park the open findings and report`;
    }
  }
  if (mark.phase === 'report' && !mark.parked && build.reportedAt === null) {
    if (REPORT_NEEDS_PARKED_AFTER.includes(lastPhase(build))) {
      return `${label} did not pass the gate: run it, or report with parked=<reason>`;
    }
    if (NEEDS_VERIFY.includes(risk) && !build.phases.includes('review')) {
      return `${label} is ${risk} risk and has no review mark: dispatch the reviewer before the report, or report with parked=<reason>`;
    }
    if (NEEDS_VERIFY.includes(risk) && !build.verified) {
      return `${label} is ${risk} risk and has no verify mark: dispatch the verifier before the report, or report with parked=<reason>`;
    }
  }
  return null;
}

// The fields mark.sh adds to a permitted mark, so that no reader has to work them out.
export function stamp(events, mark) {
  const all = builds(events);
  const key = mark.phase === FINAL || mark.chunk === undefined ? FINAL : mark.chunk;
  const build = lastBuildOf(all, key);
  const startsBuild = !build || (STARTS.includes(mark.phase) && build.reportedAt !== null);
  const stamped = { build: startsBuild ? (build?.build ?? 0) + 1 : build.build };
  if (key === FINAL && mark.phase !== FINAL) stamped.scope = FINAL;
  if (mark.phase === 'fix') {
    stamped.stage = stageOfFix(build);
    stamped.round = mark.round ?? build.fix[stamped.stage] + 1;
  }
  return stamped;
}

export function readEvents(path) {
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch {
    return [];
  }
  const events = [];
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      events.push(JSON.parse(line));
    } catch {
      // A line cut off by a crash is not an event.
    }
  }
  return events;
}

// --------------------------------------------------------------------- CLI
const KEYS = ['phase', 'chunk', 'of', 'name', 'risk', 'plan', 'round', 'parked'];
const NUMBERS = ['chunk', 'of', 'round'];

class Refused extends Error {}
const refuse = message => {
  throw new Refused(message);
};

function parseMark(pairs) {
  if (!pairs.length) {
    refuse(
      `usage: mark.sh phase=<${Object.keys(PHASES).join('|')}> chunk=N of=M [name=<text>] [risk=<${RISKS.join('|')}>] [plan=<path>] [round=N] [parked=<reason>]\n` +
        '       the phases after phase=final take no chunk',
    );
  }
  const mark = {};
  for (const pair of pairs) {
    const at = pair.indexOf('=');
    if (at < 1) refuse(`expected key=value, got '${pair}'`);
    const key = pair.slice(0, at);
    const value = pair.slice(at + 1);
    if (!KEYS.includes(key)) refuse(`unknown key '${key}'`);
    if (key in mark) refuse(`repeated key '${key}'`);
    if (key === 'phase' && !PHASES[value]) refuse(`phase must be one of: ${Object.keys(PHASES).join(', ')} (got '${value}')`);
    if (key === 'risk' && !RISKS.includes(value)) refuse(`risk must be one of: ${RISKS.join(', ')} (got '${value}')`);
    if (NUMBERS.includes(key) && !/^[0-9]+$/.test(value)) refuse(`${key} must be a whole number (got '${value}')`);
    mark[key] = NUMBERS.includes(key) ? Number(value) : value;
  }
  if (!mark.phase) refuse('missing phase');
  return mark;
}

function check(file, pairs) {
  const mark = parseMark(pairs);
  const mode = process.env.LIFECYCLE_MODE || 'gated';
  const events = readEvents(file);
  const reason = refusal(events, mark, mode);
  if (reason) refuse(reason);

  for (const [key, value] of Object.entries({ ...mark, ...stamp(events, mark) })) {
    console.log(typeof value === 'number' ? `${key}:=${value}` : `${key}=${value}`);
  }
}

function status(file) {
  const all = builds(readEvents(file));
  if (!all.length) {
    console.log('no chunk has a mark yet');
    return;
  }
  const latest = new Map(all.map(build => [build.chunk, build]));
  for (const build of latest.values()) {
    const title = build.chunk === FINAL ? 'final pass' : `chunk ${build.chunk}${build.of ? `/${build.of}` : ''}`;
    const facts = [
      build.name,
      build.risk && build.chunk !== FINAL ? `${build.risk} risk` : null,
      build.build > 1 ? `build ${build.build}` : null,
      `at ${lastPhase(build)}`,
      build.fix.review ? `${build.fix.review} fix round(s)` : null,
      build.parked ? `parked: ${build.parked}` : null,
      build.decision ? `decision: ${build.decision}` : null,
    ].filter(Boolean);
    console.log(`${title} — ${facts.join(' · ')} — next: ${nextPhases(build).join(', ')}`);
  }
}

function printBuilds(files) {
  for (const file of files) {
    for (const build of builds(readEvents(file))) {
      const { marks, ...rest } = build;
      console.log(JSON.stringify({ ...rest, reported: build.reportedAt !== null, ended: marks[marks.length - 1].ts }));
    }
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command, ...args] = process.argv.slice(2);
  try {
    if (command === 'check') check(args[0], args.slice(1));
    else if (command === 'parse') parseMark(args);
    else if (command === 'status') status(args[0]);
    else if (command === 'builds') printBuilds(args);
    else refuse('usage: lifecycle.mjs check <events-file> key=value... | status <events-file> | builds <events-file>...');
  } catch (error) {
    if (!(error instanceof Refused)) throw error;
    console.error(error.message.startsWith('usage') ? error.message : `mark: ${error.message}`);
    process.exit(2);
  }
}
