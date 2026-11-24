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
# Exit 1 when any line is BLOCK, 2 when the config or a limit is invalid, else 0. A range is vetted at its base version
# (^1.2.3 as 1.2.3), a bare name at latest.
#
#   DEP_MIN_AGE_DAYS      default 30
#   DEP_MIN_VERSION_DAYS  default 7
#   DEP_VET_ALLOW         ERE of package names never vetted (private scopes)
#                         (default for the three: deps.minAgeDays, deps.minVersionDays
#                         and deps.allow in docs/review/delivery.json)
#   DEP_VET_RANGE         base..head for --diff instead of the working tree
#   DELIVERY_BASE         tree-ish --diff compares the working tree with (default HEAD)
#   DEP_VET_TIMEOUT       seconds for the whole run, default 6
#   DEP_REGISTRY, DEP_OSV endpoints (default registry.npmjs.org, api.osv.dev)
#   DEP_VET=off           print nothing, exit 0
set -uo pipefail
[ "${DEP_VET:-on}" = "off" ] && exit 0
if [ $# -eq 0 ]; then
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi

DELIVERY_CONFIG_MODULE="$(cd "$(dirname "$0")" && pwd)/config.mjs" exec node --input-type=module - "$@" <<'NODE'
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const env = process.env;
const REGISTRY = (env.DEP_REGISTRY || 'https://registry.npmjs.org').replace(/\/$/, '');
const OSV = (env.DEP_OSV || 'https://api.osv.dev').replace(/\/$/, '');

function stop(message) {
  console.error(`dep-vet: ${message}`);
  process.exit(2);
}

let config = {};
try {
  const configModule = await import(env.DELIVERY_CONFIG_MODULE);
  config = configModule.load({ optional: true }).deps || {};
  config.allow = configModule.ere(config.allow);
} catch (error) {
  stop(error.message);
}

function days(name, value, fallback) {
  if (value === undefined || value === '') return fallback;
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) stop(`${name} must be a number of days, got '${value}'`);
  return number;
}

const MIN_PACKAGE_AGE_DAYS = days('DEP_MIN_AGE_DAYS (deps.minAgeDays)', env.DEP_MIN_AGE_DAYS || config.minAgeDays, 30);
const MIN_VERSION_AGE_DAYS = days('DEP_MIN_VERSION_DAYS (deps.minVersionDays)', env.DEP_MIN_VERSION_DAYS || config.minVersionDays, 7);
const allowPattern = env.DEP_VET_ALLOW || config.allow;
let allowed = null;
try {
  allowed = allowPattern ? new RegExp(allowPattern) : null;
} catch {
  stop(`DEP_VET_ALLOW (deps.allow) is not a valid pattern: ${allowPattern}`);
}
const signal = AbortSignal.timeout(Number(env.DEP_VET_TIMEOUT || 6) * 1000);

const MANIFEST = /(^|\/)package\.json$/;
const REMOTE_SOURCE = /:\/\/|^(git\+|github:|gitlab:|bitbucket:)/;
const LOCAL_PROTOCOL = /^(workspace|file|link|portal|catalog|patch):/;
const PACKAGE_NAME = /^(@[a-z0-9-~][a-z0-9-._~]*\/)?[a-z0-9-~][a-z0-9-._~]*$/i;

const daysSince = iso => Math.floor((Date.now() - Date.parse(iso)) / 86400000);

function git(...args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch {
    return '';
  }
}

function dependenciesOf(manifestText) {
  try {
    const manifest = JSON.parse(manifestText || '{}');
    return {
      ...manifest.peerDependencies,
      ...manifest.dependencies,
      ...manifest.devDependencies,
      ...manifest.optionalDependencies,
    };
  } catch {
    return {};
  }
}

const root = git('rev-parse', '--show-toplevel').trim() || process.cwd();
const inRoot = (...args) => git('-C', root, ...args);

function baseAndHead(range) {
  if (!range) return [env.DELIVERY_BASE || (inRoot('rev-parse', '-q', '--verify', 'HEAD') ? 'HEAD' : ''), ''];
  if (range.includes('...')) {
    const [left, right] = range.split('...');
    return [inRoot('merge-base', left || 'HEAD', right || 'HEAD').trim(), right || 'HEAD'];
  }
  const [base, head] = range.split('..');
  return [base, head || 'HEAD'];
}

// Paths from the git root, whatever directory the script runs in.
function changedManifests(range, base) {
  const changed = range
    ? inRoot('diff', '-z', '--name-only', '--no-renames', range)
    : (base ? inRoot('diff', '-z', '--name-only', '--no-renames', base) : inRoot('ls-files', '-z', '--cached'))
      + inRoot('ls-files', '-z', '--others', '--exclude-standard');
  return changed.split('\0').filter(file => MANIFEST.test(file) && !file.includes('node_modules/'));
}

// The specs (name@range) a diff adds or re-versions in the given package.json files.
function specsFromDiff(named) {
  const range = env.DEP_VET_RANGE || '';
  const [base, head] = baseAndHead(range);
  const files = named.length
    ? named.map(file => path.relative(root, path.resolve(file)))
    : changedManifests(range, base);

  const specs = new Set();
  for (const file of files) {
    if (!MANIFEST.test(file)) continue;
    const before = dependenciesOf(base ? inRoot('show', `${base}:${file}`) : '');
    let afterText = '';
    if (head) {
      afterText = inRoot('show', `${head}:${file}`);
    } else {
      try { afterText = fs.readFileSync(path.join(root, file), 'utf8'); } catch {}
    }
    for (const [name, wanted] of Object.entries(dependenciesOf(afterText))) {
      if (before[name] !== wanted) specs.add(`${name}@${wanted}`);
    }
  }
  return [...specs];
}

// Returns { name, wanted } for a registry package, { raw, foreign: true } for one
// that comes from somewhere else, and null for a local one that needs no vetting.
function parseSpec(raw) {
  let spec = raw.replace(/^['"]|['"]$/g, '');
  const alias = spec.match(/^(?:@[^/]+\/)?[^@]+@npm:(.+)$/);
  if (alias) spec = alias[1];

  const at = spec.lastIndexOf('@');
  const name = at > 0 ? spec.slice(0, at) : spec;
  const wanted = at > 0 ? spec.slice(at + 1) : '';

  if (LOCAL_PROTOCOL.test(wanted) || wanted === '*') return null;
  if (/^(\.|\/|~)/.test(spec) || /^(file|link|workspace):/.test(spec)) return null;
  if (REMOTE_SOURCE.test(spec) || REMOTE_SOURCE.test(wanted) || !PACKAGE_NAME.test(name)) {
    return { raw: spec, foreign: true };
  }
  return { name, wanted };
}

// A range is vetted at its base version (^1.2.3 as 1.2.3), a tag at what it points to, a bare name at latest.
function resolveVersion(wanted, versions, tags) {
  if (versions[wanted]) return wanted;
  if (tags[wanted]) return tags[wanted];
  const base = wanted.replace(/^[\^~>=<v\s]+/, '').split(/[\s|]/)[0];
  if (versions[base]) return base;
  return tags.latest;
}

async function advisoryFindings(name, version, id) {
  try {
    const response = await fetch(`${OSV}/v1/querybatch`, {
      method: 'POST',
      signal,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ queries: [{ package: { name, ecosystem: 'npm' }, version }] }),
    });
    const advisories = response.ok ? (((await response.json()).results || [])[0]?.vulns || []).map(v => v.id) : [];
    const malware = advisories.filter(advisory => advisory.startsWith('MAL-'));
    const others = advisories.filter(advisory => !advisory.startsWith('MAL-'));

    const findings = [];
    if (malware.length) findings.push(`BLOCK ${id} — reported as malware: ${malware.join(', ')}`);
    if (others.length) {
      const noun = others.length > 1 ? 'advisories' : 'advisory';
      const shown = others.slice(0, 3).join(', ') + (others.length > 3 ? ', …' : '');
      findings.push(`FLAG ${id} — ${others.length} known ${noun}: ${shown}`);
    }
    return findings;
  } catch {
    return [`SKIP ${id} — advisory database did not answer; advisories not checked`];
  }
}

async function vet({ name, wanted }) {
  const response = await fetch(`${REGISTRY}/${name.replace('/', '%2F')}`, { signal, headers: { accept: 'application/json' } });
  if (response.status === 404) return [`BLOCK ${name} — not in the registry; check the name against the docs it came from`];
  if (!response.ok) return [`SKIP ${name} — registry answered ${response.status}; not vetted`];

  const doc = await response.json();
  const versions = doc.versions || {};
  const published = doc.time || {};
  const version = resolveVersion(wanted, versions, doc['dist-tags'] || {});
  if (!version) return [`BLOCK ${name} — the registry has no published version of it`];
  const id = `${name}@${version}`;
  const findings = [];

  if (published.created && daysSince(published.created) < MIN_PACKAGE_AGE_DAYS) {
    findings.push(`BLOCK ${id} — package first published ${daysSince(published.created)} days ago (under ${MIN_PACKAGE_AGE_DAYS})`);
  } else if (published[version] && daysSince(published[version]) < MIN_VERSION_AGE_DAYS) {
    findings.push(`BLOCK ${id} — this version was published ${daysSince(published[version])} days ago (under ${MIN_VERSION_AGE_DAYS}); pin the one before it`);
  }

  const scripts = (versions[version] || {}).scripts || {};
  const installScripts = ['preinstall', 'install', 'postinstall'].filter(hook => scripts[hook]);
  if (installScripts.length) findings.push(`FLAG ${id} — runs ${installScripts.join(', ')} on install`);

  findings.push(...(await advisoryFindings(name, version, id)));
  return findings;
}

const args = process.argv.slice(2);
const rawSpecs = args[0] === '--diff' ? specsFromDiff(args.slice(1)) : args;

const lines = [];
const lookups = [];
for (const raw of new Set(rawSpecs)) {
  const spec = parseSpec(raw);
  if (!spec) continue;
  if (spec.foreign) {
    lines.push(`FLAG ${spec.raw} — not a registry package; nothing to vet it against`);
    continue;
  }
  if (allowed && allowed.test(spec.name)) continue;
  lookups.push(vet(spec).catch(() => [`SKIP ${spec.name} — registry did not answer; not vetted`]));
}
for (const findings of await Promise.all(lookups)) lines.push(...findings);

if (lines.length) console.log(lines.join('\n'));
process.exit(lines.some(line => line.startsWith('BLOCK ')) ? 1 : 0);
NODE
