#!/usr/bin/env node
// The project's delivery config, docs/review/delivery.json: what the stack is,
// which command each static step runs per workspace, and the project's own
// patterns. The gate runs what this file names and guesses nothing.
//
//   node config.mjs check            validate; silent when fine, exit 2 with the reason
//   node config.mjs get <key>        a scalar as is; a pattern list as one ERE; nothing when unset
//                                    (`writing` is ste100 when unset)
//   node config.mjs plan <path>...   the steps the changed paths call for, tab-separated:
//                                    RUN|SKIP|OFF  workspace  step  command-or-reason
//   node config.mjs init             write a first draft from what the repo has; never overwrites
//
//   DELIVERY_CONFIG   path of the file (default: <git root>/docs/review/delivery.json)
//
// A step is a command string, `false` for "this workspace has none", or
// { "run": "...", "files": "<ERE>" } to run only when a changed path matches.
// Commands run in the workspace directory; {files} becomes the changed paths
// that still exist, relative to it. Patterns are POSIX ERE: bash reads them.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

export const STEPS = ['typecheck', 'lint', 'format', 'test'];
const KEYS = ['stack', 'workspaces', 'writing', 'risk', 'secrets', 'deps', 'shared'];
const WRITING = ['ste100', 'free'];
const DEFAULTS = { writing: 'ste100' };
const CODE = '\\.[cm]?[jt]sx?$';

const git = (...a) => { try { return execFileSync('git', a, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return ''; } };
export const root = () => git('rev-parse', '--show-toplevel') || process.cwd();
export const file = () => process.env.DELIVERY_CONFIG || join(root(), 'docs/review/delivery.json');
export const ere = list => (list || []).map(p => `(${p})`).join('|');

class Invalid extends Error {}
const bad = msg => { throw new Invalid(msg); };

export function load({ optional = false } = {}) {
  const path = file();
  if (!existsSync(path)) return optional ? {} : bad(`no ${relative(process.cwd(), path) || path} — write one with: bash static-gate.sh init`);
  let cfg;
  try { cfg = JSON.parse(readFileSync(path, 'utf8')); } catch (e) { bad(`${path}: ${e.message}`); }
  for (const k of Object.keys(cfg)) KEYS.includes(k) || bad(`${path}: unknown key "${k}" (known: ${KEYS.join(', ')})`);
  const patterns = (v, name) => v === undefined || (Array.isArray(v) && v.every(p => typeof p === 'string')) || bad(`${path}: ${name} must be a list of patterns`);
  patterns(cfg.stack, 'stack'); patterns(cfg.shared, 'shared');
  patterns(cfg.risk?.high, 'risk.high'); patterns(cfg.risk?.medium, 'risk.medium');
  patterns(cfg.secrets?.allow, 'secrets.allow'); patterns(cfg.deps?.allow, 'deps.allow');
  cfg.writing === undefined || WRITING.includes(cfg.writing) || bad(`${path}: writing must be one of: ${WRITING.join(', ')}`);
  if (optional && cfg.workspaces === undefined) return cfg;
  const ws = cfg.workspaces;
  ws && typeof ws === 'object' && Object.keys(ws).length || bad(`${path}: workspaces must name at least one directory ("." for the root)`);
  for (const [dir, steps] of Object.entries(ws)) {
    steps && typeof steps === 'object' || bad(`${path}: workspaces["${dir}"] must be an object of steps`);
    for (const [name, step] of Object.entries(steps)) {
      const run = step && typeof step === 'object' ? step.run : step;
      if (step === false || step === null) continue;
      typeof run === 'string' && run.trim() && !/[\t\n]/.test(run) || bad(`${path}: workspaces["${dir}"].${name} must be a one-line command, false, or { run, files }`);
      if (typeof step === 'object') typeof step.files === 'string' || bad(`${path}: workspaces["${dir}"].${name}.files must be a pattern`);
    }
  }
  return cfg;
}

const norm = dir => dir.replace(/^\.\//, '').replace(/\/+$/, '') || '.';
const quote = s => `'${s.replace(/'/g, `'\\''`)}'`;

export function plan(cfg, paths) {
  const base = root();
  const dirs = Object.keys(cfg.workspaces).map(d => [norm(d), cfg.workspaces[d]]).sort((a, b) => b[0].length - a[0].length);
  const touched = new Map(), orphans = [];
  for (const p of paths) {
    const hit = dirs.find(([d]) => d === '.' || p === d || p.startsWith(d + '/'));
    if (!hit) { orphans.push(p); continue; }
    touched.has(hit[0]) || touched.set(hit[0], { steps: hit[1], paths: [] });
    touched.get(hit[0]).paths.push(p);
  }
  const out = [];
  for (const [dir, { steps, paths: changed }] of touched) {
    for (const name of [...new Set([...Object.keys(steps), ...STEPS])]) {
      const step = steps[name];
      if (step === undefined) { out.push(['SKIP', dir, name, `no command for ${dir}; set one, or false`]); continue; }
      if (step === false || step === null) { out.push(['OFF', dir, name, '']); continue; }
      const run = typeof step === 'string' ? step : step.run;
      const mine = typeof step === 'string' ? changed : changed.filter(p => new RegExp(step.files).test(p));
      if (!mine.length) continue;
      if (!run.includes('{files}')) { out.push(['RUN', dir, name, run]); continue; }
      const live = mine.filter(p => existsSync(join(base, p)));
      if (!live.length) { out.push(['SKIP', dir, name, 'every matching path was deleted']); continue; }
      out.push(['RUN', dir, name, run.replaceAll('{files}', live.map(p => quote(dir === '.' ? p : p.slice(dir.length + 1))).join(' '))]);
    }
  }
  if (orphans.length) out.push(['SKIP', '-', 'workspace', `${orphans.length} path(s) under no workspace: ${orphans.slice(0, 3).join(', ')}${orphans.length > 3 ? ', …' : ''}`]);
  return out;
}

function draft() {
  const base = root();
  const json = p => { try { return JSON.parse(readFileSync(join(base, p), 'utf8')); } catch { return {}; } };
  const has = (dir, re) => { try { return readdirSync(join(base, dir)).some(f => re.test(f)); } catch { return false; } };
  const pm = has('.', /^pnpm-lock\.yaml$/) ? 'pnpm' : has('.', /^yarn\.lock$/) ? 'yarn' : has('.', /^bun\.lockb?$/) ? 'bun' : 'npm';
  const bin = { npm: 'npx --no-install', pnpm: 'pnpm exec', yarn: 'yarn run', bun: 'bun x' }[pm];
  const rootPkg = json('package.json');
  const all = pkg => ({ ...pkg.dependencies, ...pkg.devDependencies });
  const manifests = git('ls-files', '-co', '--exclude-standard', '--', 'package.json', '*/package.json').split('\n').filter(f => f && !f.includes('node_modules/'));
  const workspaces = {}, seen = {};
  for (const m of manifests.sort()) {
    const dir = norm(dirname(m)), pkg = json(m), deps = { ...all(rootPkg), ...all(pkg) }, scripts = pkg.scripts || {};
    Object.assign(seen, all(pkg));
    const here = re => has(dir, re) || has('.', re), steps = {};
    if (scripts.typecheck) steps.typecheck = { run: `${pm} run typecheck`, files: CODE };
    else if (has(dir, /^tsconfig\.json$/)) steps.typecheck = { run: `${bin} tsc --noEmit -p tsconfig.json`, files: '\\.[cm]?tsx?$' };
    if (here(/^(eslint\.config\.|\.eslintrc)/) || pkg.eslintConfig) steps.lint = { run: `${bin} eslint --max-warnings=0 --no-warn-ignored {files}`, files: '\\.([cm]?[jt]sx?|vue|svelte)$' };
    if (here(/^(\.prettierrc|prettier\.config\.)/) || pkg.prettier || rootPkg.prettier) steps.format = `${bin} prettier --check --ignore-unknown {files}`;
    if (deps.vitest) steps.test = { run: `${bin} vitest related --run {files}`, files: CODE };
    else if (deps.jest) steps.test = { run: `${bin} jest --findRelatedTests {files}`, files: CODE };
    else if (scripts.test) steps.test = { run: `${pm} test`, files: CODE };
    if ((deps.prisma || deps['@prisma/client']) && git('ls-files', '-co', '--exclude-standard', '--', dir === '.' ? '*.prisma' : `${dir}/*.prisma`)) steps.prisma = { run: `${bin} prisma validate`, files: '\\.prisma$' };
    if (dir === '.' || Object.keys(steps).length) workspaces[dir] = steps;
  }
  workspaces['.'] ||= {};
  const marks = { nestjs: '@nestjs/core', angular: '@angular/core', 'react-native': 'react-native', expo: 'expo', next: 'next', react: 'react', prisma: '@prisma/client' };
  return { stack: Object.keys(marks).filter(k => seen[marks[k]]), writing: DEFAULTS.writing, workspaces };
}

function main([cmd, ...args]) {
  if (cmd === 'check') return void load();
  if (cmd === 'get') {
    const value = (args[0] || '').split('.').reduce((o, k) => o?.[k], { ...DEFAULTS, ...load({ optional: true }) });
    if (value !== undefined && value !== null) console.log(Array.isArray(value) ? ere(value) : typeof value === 'object' ? JSON.stringify(value) : String(value));
    return;
  }
  if (cmd === 'plan') return void plan(load(), args).forEach(l => console.log(l.join('\t')));
  if (cmd === 'init') {
    const path = file();
    if (existsSync(path)) bad(`${path} exists; edit it`);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(draft(), null, 2) + '\n');
    console.log(`wrote ${relative(process.cwd(), path)} — every command in it is a guess from package.json. Read it, fix it, commit it.`);
    console.log('A step the gate should never run for a workspace is `false`; a missing step is reported as skipped on every run.');
    return;
  }
  console.error('usage: config.mjs check | get <key> | plan <path>... | init');
  process.exit(2);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); } catch (e) {
    if (!(e instanceof Invalid)) throw e;
    console.error(`delivery config: ${e.message}`);
    process.exit(2);
  }
}
