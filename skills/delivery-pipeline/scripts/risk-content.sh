#!/usr/bin/env bash
# Raises a risk class from what a diff *does*, using TypeSafe's Jev model.
#
#   git diff | bash scripts/risk-content.sh [--floor low|medium|high]
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
# It never lowers the floor. Output mirrors risk.sh: one line per file (class,
# path, predicates that fired), `unsure:` lines for the human, then `files:`
# and `class:` for the set.
#
#   TYPESAFE_API_KEY        required; absent -> "skipped", exit 0
#   TYPESAFE_API_URL        default https://api.typesafe.ai/v1/systemone
#   RISK_CONTENT_MODEL      default jev-latest
#   RISK_P_ACT              default 0.7   probability that counts as yes
#   RISK_P_UNSURE           default 0.35  below this counts as no
#   RISK_CONTENT_MAX_CHARS  default 100000 per file; longer hunks are cut and the file marked unsure
#   RISK_CONTENT_DRY=1      print the requests as JSON lines, call nothing
#
# Exit 0 on a verdict, 1 when any request failed (the file is listed unsure
# and the set is at least medium), 2 on usage error. Needs node >= 18.
set -uo pipefail

floor="low"
while [ $# -gt 0 ]; do
  case "$1" in
    --floor) floor="${2:-}"; shift 2;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2;;
    *) echo "risk-content.sh: unknown argument $1" >&2; exit 2;;
  esac
done
case "$floor" in low|medium|high) ;; *) echo "risk-content.sh: --floor must be low, medium or high" >&2; exit 2;; esac

if [ -z "${TYPESAFE_API_KEY:-}" ]; then
  echo "skipped: no TYPESAFE_API_KEY"
  exit 0
fi

script=$(cat <<'EOF'
const fs = require('node:fs');

const floor = process.argv[1];
const env = process.env;
const DRY = env.RISK_CONTENT_DRY === '1';
const ENDPOINT = env.TYPESAFE_API_URL || 'https://api.typesafe.ai/v1/systemone';
const MODEL = env.RISK_CONTENT_MODEL || 'jev-latest';
const P_ACT = Number(env.RISK_P_ACT || 0.7);
const P_UNSURE = Number(env.RISK_P_UNSURE || 0.35);
const MAX_CHARS = Number(env.RISK_CONTENT_MAX_CHARS || 100000);

// Literal yes/no questions. Jev answers what is written, so each names the
// exact condition and the criteria say what yes and no mean.
const QUESTIONS = {
  signature_changed: {
    type: 'noul',
    instructions: 'The diff changes the name, parameters or return type of a function, method, class, type or exported value that existed before the change.',
    criteria: { yes: 'An existing declaration is renamed, gains or loses a parameter, or changes what it returns.', no: 'Only new declarations are added, or bodies change with the same name, parameters and return type.' },
  },
  caller_sees_change: {
    type: 'noul',
    instructions: 'Code that already called the changed code before this diff would now receive different data or behaviour, and no feature flag or option guards the new path.',
    criteria: { yes: 'An existing call site gets a different result, side effect or error with no flag in front of it.', no: 'Existing calls behave as before, or the new behaviour is behind a flag that defaults off.' },
  },
  prod_data_path: {
    type: 'noul',
    instructions: 'The changed code reads or writes a database, queue, file store or external API that holds real records in production.',
    criteria: { yes: 'The hunks touch repository, ORM, SQL, queue, storage or HTTP client calls on the production data path.', no: 'The hunks are UI, formatting, tests, docs, config or pure computation with no data store or external call.' },
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

function splitDiff(text) {
  const files = [];
  let cur = null;
  for (const line of text.split('\n')) {
    const m = /^diff --git a\/(.*?) b\/(.*)$/.exec(line);
    if (m) { cur = { path: m[2], lines: [] }; files.push(cur); continue; }
    if (cur) cur.lines.push(line);
  }
  return files.map(f => ({ path: f.path, diff: f.lines.join('\n') }));
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

function judge(path, p, truncated) {
  let rank = RANK[floor];
  const fired = [], unsure = [];
  const tag = (k) => `${k} p=${p[k].toFixed(2)}`;
  for (const k of HIGH) {
    if (p[k] >= P_ACT) { rank = 3; fired.push(tag(k)); }
    else if (p[k] >= P_UNSURE) unsure.push(tag(k));
  }
  let up = false;
  for (const k of UP) {
    if (p[k] >= P_ACT) { up = true; fired.push(tag(k)); }
    else if (p[k] >= P_UNSURE) unsure.push(tag(k));
  }
  if (up) rank = Math.max(rank, Math.min(3, RANK[floor] + 1));
  if (truncated) unsure.push('diff cut at RISK_CONTENT_MAX_CHARS');
  if (unsure.length && rank < 2) rank = 2;
  const rule = fired.length ? fired.join(', ') : (p.additive_only >= P_ACT ? `additive only p=${p.additive_only.toFixed(2)}` : 'no escalator');
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
      return judge(files[i].path, p, r.truncated);
    } catch (e) {
      failed = true;
      return { path: files[i].path, rank: Math.max(2, RANK[floor]), rule: 'not evaluated', unsure: [`error: ${e.message}`] };
    }
  }));

  let top = RANK[floor];
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

main().then(code => process.exit(code), e => { console.error(`risk-content.sh: ${e.message}`); process.exit(1); });
EOF
)

node -e "$script" "$floor"
