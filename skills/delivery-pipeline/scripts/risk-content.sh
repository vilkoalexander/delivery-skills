#!/usr/bin/env bash
# Raises a risk class from what a diff *does*, using TypeSafe's Jev model.
#
#   git diff | bash scripts/risk-content.sh [--floor low|medium|high] [--floors <file>]
#   git diff base..head -- <paths> | bash scripts/risk-content.sh --floor medium
#
# risk.sh sees paths; this sees hunks. Each changed file becomes one request:
# the file's diff is the state, and the escalators from the Risk class table
# are the questions, each a yes/no with a probability. The class is then
# raised in code, never by the model:
#
#   deletes_data, auth_or_money, prod_data_path  >= RISK_P_ACT  -> high
#   signature_changed, caller_sees_change        >= RISK_P_ACT  -> one class up
#   any predicate in [RISK_P_UNSURE, RISK_P_ACT)               -> unsure: at least medium
#
# An unsure predicate is listed only when a yes would still raise the file:
# nothing is listed for a file already at high, and the one-class-up
# predicates are not listed for a file already there.
#
# A brand-new file (`new file mode` in its header) has no existing callers or
# signatures, so the two one-class-up predicates are ignored for it in code.
#
# --floor is the starting class for every file; --floors names a file of
# `class<TAB>path` lines (what risk.sh prints, tab-separated) giving each file
# its own start, with --floor for the rest. It never lowers a floor. Output
# mirrors risk.sh: one line per file (class, path, predicates that fired),
# `unsure:` lines for the human, then `files:` and `class:` for the set.
#
#   TYPESAFE_API_KEY        required; absent -> "skipped", exit 0
#   TYPESAFE_API_URL        default https://api.typesafe.ai/v1/systemone
#   RISK_CONTENT_MODEL      default jev-latest
#   RISK_P_ACT              default 0.7   probability that counts as yes
#   RISK_P_UNSURE           default 0.5   below this counts as no
#   RISK_CONTENT_MAX_CHARS  default 100000 per file; longer hunks are cut and the file marked unsure
#   RISK_CONTENT_DRY=1      print the requests as JSON lines, call nothing
#
# Exit 0 on a verdict, 1 when any request failed (the file is listed unsure
# and the set is at least medium), 2 on usage error. Needs node >= 18.
set -uo pipefail

floor="low"
floors=""
while [ $# -gt 0 ]; do
  case "$1" in
    --floor) floor="${2:-}"; shift 2;;
    --floors) floors="${2:-}"; shift 2;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2;;
    *) echo "risk-content.sh: unknown argument $1" >&2; exit 2;;
  esac
done
case "$floor" in low|medium|high) ;; *) echo "risk-content.sh: --floor must be low, medium or high" >&2; exit 2;; esac
[ -n "$floors" ] && [ ! -r "$floors" ] && { echo "risk-content.sh: cannot read --floors $floors" >&2; exit 2; }

if [ -z "${TYPESAFE_API_KEY:-}" ]; then
  echo "skipped: no TYPESAFE_API_KEY"
  exit 0
fi

script=$(cat <<'EOF'
const fs = require('node:fs');

const floor = process.argv[1];
const floorsFile = process.argv[2];
const env = process.env;
const DRY = env.RISK_CONTENT_DRY === '1';
const ENDPOINT = env.TYPESAFE_API_URL || 'https://api.typesafe.ai/v1/systemone';
const MODEL = env.RISK_CONTENT_MODEL || 'jev-latest';
const P_ACT = Number(env.RISK_P_ACT || 0.7);
const P_UNSURE = Number(env.RISK_P_UNSURE || 0.5);
const MAX_CHARS = Number(env.RISK_CONTENT_MAX_CHARS || 100000);

// Literal yes/no questions. Jev answers what is written, so each names the
// exact condition and the criteria say what yes and no mean.
const QUESTIONS = {
  signature_changed: {
    type: 'noul',
    instructions: 'The diff renames an existing exported function, method, class, type or value, removes or renames one of its parameters or properties, makes an optional one required, or changes its return type.',
    criteria: { yes: 'Some existing call or use of the declaration would no longer be valid as written.', no: 'Only new declarations are added; a body changes with the same name, parameters and return type; or an optional parameter or property with a default is added and every existing call stays valid.' },
  },
  caller_sees_change: {
    type: 'noul',
    instructions: 'Code that already called the changed code before this diff would now receive different data, a different side effect or a different error, and no feature flag or option guards the new path.',
    criteria: { yes: 'An existing call site gets a different value, a different side effect or a different error with no flag in front of it.', no: 'Existing calls get the same data and effects; only appearance changes such as class names, styles, spacing, copy or layout; or the new behaviour is behind a flag that defaults off.' },
  },
  prod_data_path: {
    type: 'noul',
    instructions: 'The changed code runs on the server and reads or writes the system of record: a database, queue, file store or third-party API that holds production records.',
    criteria: { yes: 'Server-side hunks touch a repository, ORM, SQL, migration, queue producer or consumer, object storage or an outbound call to a third-party system.', no: 'Client or UI code, including screens, hooks and components that call its own backend API or use device storage; or tests, docs, config and pure computation.' },
  },
  deletes_data: {
    type: 'noul',
    instructions: 'The change deletes stored records, drops a column or table, or removes data that was persisted before.',
    criteria: { yes: 'A delete, drop, truncate or remove of persisted data appears in the hunks.', no: 'Nothing persisted is removed.' },
  },
  auth_or_money: {
    type: 'noul',
    instructions: 'The change alters authentication, authorization, session handling, payment, billing, ledger or pricing logic.',
    criteria: { yes: 'The hunks change who may do what, how identity is checked, or how money is computed, moved or recorded.', no: 'None of those concerns appear in the hunks.' },
  },
  additive_only: {
    type: 'noul',
    instructions: 'The diff only adds new code that nothing existing calls yet, and changes no line that was already there.',
    criteria: { yes: 'Every hunk adds new declarations or files and no existing line is modified or removed.', no: 'Some existing line is modified or removed, or new code is wired into an existing call path.' },
  },
};
const HIGH = ['deletes_data', 'auth_or_money', 'prod_data_path'];
const UP = ['signature_changed', 'caller_sees_change'];
const RANK = { low: 1, medium: 2, high: 3 };
const NAME = { 1: 'low', 2: 'medium', 3: 'high' };

const floors = {};
if (floorsFile) {
  for (const line of fs.readFileSync(floorsFile, 'utf8').split('\n')) {
    const m = /^(low|medium|high)\t(.+)$/.exec(line);
    if (m) floors[m[2]] = m[1];
  }
}
const floorOf = (path) => floors[path] || floor;

function splitDiff(text) {
  const files = [];
  let cur = null;
  for (const line of text.split('\n')) {
    const m = /^diff --git a\/(.*?) b\/(.*)$/.exec(line);
    if (m) { cur = { path: m[2], lines: [] }; files.push(cur); continue; }
    if (cur) cur.lines.push(line);
  }
  return files.map(f => ({ path: f.path, diff: f.lines.join('\n'), isNew: f.lines.some(l => /^new file mode /.test(l)) }));
}

function request(file) {
  let diff = file.diff, truncated = false;
  if (diff.length > MAX_CHARS) { diff = diff.slice(0, MAX_CHARS) + '\n[... cut by risk-content.sh ...]'; truncated = true; }
  return { truncated, body: { model: MODEL, state: { path: file.path, diff }, questions: QUESTIONS } };
}

async function ask(body) {
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { authorization: `Bearer ${env.TYPESAFE_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  const json = await res.json();
  const out = {};
  for (const k of Object.keys(QUESTIONS)) {
    const a = json.answers && json.answers[k];
    if (!a || typeof a.noul !== 'number') throw new Error(`no noul answer for ${k}`);
    out[k] = a.noul;
  }
  return out;
}

function judge(path, p, truncated, isNew) {
  const start = RANK[floorOf(path)];
  let rank = start;
  const fired = [], maybeHigh = [], maybeUp = [];
  const tag = (k) => `${k} p=${p[k].toFixed(2)}`;
  for (const k of HIGH) {
    if (p[k] >= P_ACT) { rank = 3; fired.push(tag(k)); }
    else if (p[k] >= P_UNSURE) maybeHigh.push(tag(k));
  }
  let up = false;
  if (!isNew) for (const k of UP) {
    if (p[k] >= P_ACT) { up = true; fired.push(tag(k)); }
    else if (p[k] >= P_UNSURE) maybeUp.push(tag(k));
  }
  if (up) rank = Math.max(rank, Math.min(3, start + 1));
  // Only list what could still move the file.
  const unsure = [];
  if (rank < 3) unsure.push(...maybeHigh);
  if (rank < Math.min(3, start + 1)) unsure.push(...maybeUp);
  if (truncated && rank < 3) unsure.push('diff cut at RISK_CONTENT_MAX_CHARS');
  if (unsure.length && rank < 2) rank = 2;
  let rule = fired.length ? fired.join(', ') : (p.additive_only >= P_ACT ? `additive only p=${p.additive_only.toFixed(2)}` : 'no escalator');
  if (isNew) rule = `new file; ${rule}`;
  return { path, rank, rule, unsure };
}

async function main() {
  const text = fs.readFileSync(0, 'utf8');
  const files = splitDiff(text);
  const reqs = files.map(request);

  if (DRY) {
    for (const r of reqs) process.stdout.write(JSON.stringify(r.body) + '\n');
    return 0;
  }

  let failed = false;
  const results = await Promise.all(reqs.map(async (r, i) => {
    try {
      const p = await ask(r.body);
      return judge(files[i].path, p, r.truncated, files[i].isNew);
    } catch (e) {
      failed = true;
      return { path: files[i].path, rank: Math.max(2, RANK[floorOf(files[i].path)]), rule: 'not evaluated', unsure: [`error: ${e.message}`] };
    }
  }));

  let top = Math.max(RANK[floor], ...results.map(r => RANK[floorOf(r.path)]), 1);
  for (const r of results) {
    console.log(`${r.rank === 3 ? 'high   ' : r.rank === 2 ? 'medium ' : 'low    '} ${r.path}  (${r.rule})`);
    if (r.rank > top) top = r.rank;
  }
  const unsureLines = results.filter(r => r.unsure.length);
  if (unsureLines.length) for (const r of unsureLines) console.log(`unsure: ${r.path}  (${r.unsure.join(', ')})`);
  else console.log('unsure: none');
  console.log(`files: ${results.length}`);
  console.log(`class: ${NAME[top]}`);
  return failed ? 1 : 0;
}

main().then(code => { process.exitCode = code; }, e => { console.error(`risk-content.sh: ${e.message}`); process.exitCode = 1; });
EOF
)

node -e "$script" "$floor" "$floors"
