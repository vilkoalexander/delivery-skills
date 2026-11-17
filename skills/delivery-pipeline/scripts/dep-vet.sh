#!/usr/bin/env bash
# Asks the npm registry and OSV about packages before they are trusted.
#
#   bash dep-vet.sh <name[@version]>...        the specs of an install command
#   bash dep-vet.sh --diff [package.json...]   deps added or re-versioned in the
#                                              working tree (default: every
#                                              changed package.json)
#
# One line per finding, nothing when clean:
#   BLOCK  not in the registry; first published under DEP_MIN_AGE_DAYS ago;
#          this version published under DEP_MIN_VERSION_DAYS ago; a malware
#          advisory (MAL-*)
#   FLAG   runs an install script; has known advisories; not a registry spec
#   SKIP   the registry did not answer in time, so nothing was vetted
# Exit 1 when any line is BLOCK, else 0. A range is vetted at its base version
# (^1.2.3 as 1.2.3), a bare name at latest.
#
#   DEP_MIN_AGE_DAYS      default 30
#   DEP_MIN_VERSION_DAYS  default 7
#   DEP_VET_ALLOW         ERE of package names never vetted (private scopes)
#                         (default for the three: deps.minAgeDays, deps.minVersionDays
#                         and deps.allow in docs/review/delivery.json)
#   DEP_VET_RANGE         base..head for --diff instead of the working tree
#   DEP_VET_TIMEOUT       seconds for the whole run, default 6
#   DEP_REGISTRY, DEP_OSV endpoints (default registry.npmjs.org, api.osv.dev)
#   DEP_VET=off           print nothing, exit 0
set -uo pipefail
[ "${DEP_VET:-on}" = "off" ] && exit 0
[ $# -eq 0 ] && { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

DELIVERY_CONFIG_MODULE="$(cd "$(dirname "$0")" && pwd)/config.mjs" exec node --input-type=module - "$@" <<'NODE'
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
const env = process.env;
const REG = (env.DEP_REGISTRY || 'https://registry.npmjs.org').replace(/\/$/, '');
const OSV = (env.DEP_OSV || 'https://api.osv.dev').replace(/\/$/, '');
let deps = {};
try { const cfg = await import(env.DELIVERY_CONFIG_MODULE); deps = cfg.load({ optional: true }).deps || {}; deps.allow = cfg.ere(deps.allow); } catch {}
const MIN_AGE = Number(env.DEP_MIN_AGE_DAYS || deps.minAgeDays || 30);
const MIN_VER = Number(env.DEP_MIN_VERSION_DAYS || deps.minVersionDays || 7);
const BUDGET = Number(env.DEP_VET_TIMEOUT || 6) * 1000;
const allow = env.DEP_VET_ALLOW || deps.allow ? new RegExp(env.DEP_VET_ALLOW || deps.allow) : null;
const signal = AbortSignal.timeout(BUDGET);
const days = iso => Math.floor((Date.now() - Date.parse(iso)) / 86400000);
const git = (...a) => { try { return execFileSync('git', a, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); } catch { return ''; } };

function fromDiff(files) {
  const range = env.DEP_VET_RANGE || '';
  const [base, head] = range ? range.split('..') : ['HEAD', ''];
  if (!files.length) {
    const changed = range ? git('diff', '--name-only', range) : git('diff', '--name-only', 'HEAD') + git('ls-files', '--others', '--exclude-standard');
    files = changed.split('\n').filter(f => /(^|\/)package\.json$/.test(f) && !f.includes('node_modules/'));
  }
  const deps = s => { try { const p = JSON.parse(s || '{}'); return Object.assign({}, p.dependencies, p.devDependencies, p.optionalDependencies); } catch { return {}; } };
  const specs = new Set();
  for (const f of files) {
    if (!/(^|\/)package\.json$/.test(f)) continue;
    const before = deps(git('show', `${base}:${f}`));
    let now = '';
    if (head) now = git('show', `${head}:${f}`); else { try { now = fs.readFileSync(f, 'utf8'); } catch {} }
    for (const [name, spec] of Object.entries(deps(now))) if (before[name] !== spec) specs.add(`${name}@${spec}`);
  }
  return [...specs];
}

function parse(raw) {
  let s = raw.replace(/^['"]|['"]$/g, '');
  const alias = s.match(/^(?:@[^/]+\/)?[^@]+@npm:(.+)$/);
  if (alias) s = alias[1];
  const at = s.lastIndexOf('@');
  const name = at > 0 ? s.slice(0, at) : s;
  const want = at > 0 ? s.slice(at + 1) : '';
  if (/^(workspace|file|link|portal|catalog|patch):/.test(want) || want === '*') return null;
  const local = /^(\.|\/|~)/.test(s) || /^(file|link|workspace):/.test(s);
  if (local) return null;
  if (/:\/\/|^(git\+|github:|gitlab:|bitbucket:)/.test(s) || /:\/\/|^(git\+|github:|gitlab:|bitbucket:)/.test(want) || !/^(@[a-z0-9-~][a-z0-9-._~]*\/)?[a-z0-9-~][a-z0-9-._~]*$/i.test(name))
    return { raw: s, foreign: true };
  return { name, want };
}

async function vet({ name, want }) {
  const out = [];
  const res = await fetch(`${REG}/${name.replace('/', '%2F')}`, { signal, headers: { accept: 'application/json' } });
  if (res.status === 404) return [`BLOCK ${name} — not in the registry; check the name against the docs it came from`];
  if (!res.ok) return [`SKIP ${name} — registry answered ${res.status}; not vetted`];
  const doc = await res.json();
  const versions = doc.versions || {}, tags = doc['dist-tags'] || {}, time = doc.time || {};
  const base = want.replace(/^[\^~>=<v\s]+/, '').split(/[\s|]/)[0];
  const version = versions[want] ? want : tags[want] ? tags[want] : versions[base] ? base : tags.latest;
  const id = `${name}@${version}`;
  if (time.created && days(time.created) < MIN_AGE) out.push(`BLOCK ${id} — package first published ${days(time.created)} days ago (under ${MIN_AGE})`);
  else if (time[version] && days(time[version]) < MIN_VER) out.push(`BLOCK ${id} — this version was published ${days(time[version])} days ago (under ${MIN_VER}); pin the one before it`);
  const scripts = (versions[version] || {}).scripts || {};
  const hooks = ['preinstall', 'install', 'postinstall'].filter(k => scripts[k]);
  if (hooks.length) out.push(`FLAG ${id} — runs ${hooks.join(', ')} on install`);
  try {
    const r = await fetch(`${OSV}/v1/querybatch`, { method: 'POST', signal, headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ queries: [{ package: { name, ecosystem: 'npm' }, version }] }) });
    const ids = r.ok ? (((await r.json()).results || [])[0]?.vulns || []).map(v => v.id) : [];
    const mal = ids.filter(i => i.startsWith('MAL-')), rest = ids.filter(i => !i.startsWith('MAL-'));
    if (mal.length) out.push(`BLOCK ${id} — reported as malware: ${mal.join(', ')}`);
    if (rest.length) out.push(`FLAG ${id} — ${rest.length} known advisor${rest.length > 1 ? 'ies' : 'y'}: ${rest.slice(0, 3).join(', ')}${rest.length > 3 ? ', …' : ''}`);
  } catch { out.push(`SKIP ${id} — advisory database did not answer; advisories not checked`); }
  return out;
}

(async () => {
  const argv = process.argv.slice(2);
  const raw = argv[0] === '--diff' ? fromDiff(argv.slice(1)) : argv;
  const lines = [];
  const jobs = [];
  for (const r of [...new Set(raw)]) {
    const p = parse(r);
    if (!p) continue;
    if (p.foreign) { lines.push(`FLAG ${p.raw} — not a registry package; nothing to vet it against`); continue; }
    if (allow && allow.test(p.name)) continue;
    jobs.push(vet(p).catch(() => [`SKIP ${p.name} — registry did not answer; not vetted`]));
  }
  for (const r of await Promise.all(jobs)) lines.push(...r);
  if (lines.length) console.log(lines.join('\n'));
  process.exit(lines.some(l => l.startsWith('BLOCK ')) ? 1 : 0);
})();
NODE
