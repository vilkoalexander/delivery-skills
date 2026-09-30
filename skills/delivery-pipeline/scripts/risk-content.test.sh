#!/usr/bin/env bash
# Tests for risk-content.sh and the router in risk.sh.
#
#   bash skills/delivery-pipeline/scripts/risk-content.test.sh
#
# Runs against a fake TypeSafe endpoint on localhost; never calls the real API.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'kill "${server_pid:-}" 2>/dev/null; wait "${server_pid:-}" 2>/dev/null; rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   - $1"; }
nok()  { fail=$((fail+1)); echo "FAIL - $1"; printf '%s\n' "$2" | sed 's/^/       /'; }
assert_contains() { # name haystack needle
  if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else nok "$1" "expected to contain: $3"$'\n'"got:"$'\n'"$2"; fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then nok "$1" "expected NOT to contain: $3"$'\n'"got:"$'\n'"$2"; else ok "$1"; fi
}

# ---------------------------------------------------------------- fixtures
diff_two_files="$tmp/two.diff"
cat > "$diff_two_files" <<'EOF'
diff --git a/src/users/users.service.ts b/src/users/users.service.ts
index 1111111..2222222 100644
--- a/src/users/users.service.ts
+++ b/src/users/users.service.ts
@@ -10,7 +10,7 @@ export class UsersService {
-  findOne(id: string) {
+  findOne(id: string, opts: { withDeleted?: boolean } = {}) {
     return this.repo.findOne(id);
   }
diff --git a/src/features/profile/Avatar.tsx b/src/features/profile/Avatar.tsx
index 3333333..4444444 100644
--- a/src/features/profile/Avatar.tsx
+++ b/src/features/profile/Avatar.tsx
@@ -1,3 +1,4 @@
+import { Image } from 'react-native';
 export function Avatar() {
   return null;
 }
EOF

diff_new_file="$tmp/new.diff"
cat > "$diff_new_file" <<'EOF'
diff --git a/src/users/users.helper.ts b/src/users/users.helper.ts
new file mode 100644
index 0000000..5555555
--- /dev/null
+++ b/src/users/users.helper.ts
@@ -0,0 +1,3 @@
+export function fullName(u: { first: string; last: string }) {
+  return `${u.first} ${u.last}`;
+}
EOF

# Fake endpoint: answers come from the JSON file named by FAKE_ANSWERS, keyed
# by state.path; a path with no entry gets every noul at 0.05.
fake_server="$tmp/server.mjs"
cat > "$fake_server" <<'EOF'
import http from 'node:http';
import fs from 'node:fs';
const log = process.env.FAKE_LOG;
const srv = http.createServer((req, res) => {
  let body = '';
  req.on('data', c => body += c);
  req.on('end', () => {
    const answers = JSON.parse(fs.readFileSync(process.env.FAKE_ANSWERS, 'utf8'));
    const r = JSON.parse(body);
    if (log) fs.appendFileSync(log, JSON.stringify(r) + '\n');
    const p = r.state.path;
    const out = {};
    for (const k of Object.keys(r.questions)) out[k] = { type: 'noul', noul: (answers[p] || {})[k] ?? 0.05 };
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ model: 'jev-fake', answers: out, usage: { input_tokens: 1, output_tokens: 1 } }));
  });
});
srv.listen(0, '127.0.0.1', () => { fs.writeFileSync(process.env.FAKE_PORT_FILE, String(srv.address().port)); });
EOF
answers="$tmp/answers.json"
export FAKE_ANSWERS="$answers" FAKE_PORT_FILE="$tmp/port" FAKE_LOG="$tmp/requests.log"
echo '{}' > "$answers"
node "$fake_server" 2>/dev/null & server_pid=$!
for _ in $(seq 1 50); do [ -s "$FAKE_PORT_FILE" ] && break; sleep 0.1; done
port=$(cat "$FAKE_PORT_FILE")
export TYPESAFE_API_URL="http://127.0.0.1:$port/v1/systemone"

run_content() { bash "$here/risk-content.sh" "$@" 2>&1; }
set_answers() { printf '%s' "$1" > "$answers"; }

# ---------------------------------------------------------------- risk-content.sh
echo "# risk-content.sh"

out=$(env -u TYPESAFE_API_KEY bash "$here/risk-content.sh" < "$diff_two_files" 2>&1); rc=$?
assert_contains "no key: says skipped" "$out" "skipped: no TYPESAFE_API_KEY"
[ "$rc" -eq 0 ] && ok "no key: exit 0" || nok "no key: exit 0" "rc=$rc"

out=$(RISK_CONTENT_DRY=1 TYPESAFE_API_KEY=x run_content < "$diff_two_files")
assert_contains "dry run: one request per file (service)" "$out" '"path":"src/users/users.service.ts"'
assert_contains "dry run: one request per file (tsx)" "$out" '"path":"src/features/profile/Avatar.tsx"'
assert_contains "dry run: asks signature_changed" "$out" '"signature_changed"'
assert_contains "dry run: asks deletes_data" "$out" '"deletes_data"'
assert_contains "dry run: state carries the hunk" "$out" 'withDeleted'
assert_not_contains "dry run: does not report a class" "$out" 'class:'

set_answers '{}'
out=$(TYPESAFE_API_KEY=x run_content --floor low < "$diff_two_files")
assert_contains "all low probabilities: floor stays" "$out" "class: low"
assert_contains "all low probabilities: no unsure" "$out" "unsure: none"

set_answers '{"src/users/users.service.ts":{"deletes_data":0.95}}'
out=$(TYPESAFE_API_KEY=x run_content --floor low < "$diff_two_files")
assert_contains "deletes_data high: file is high" "$out" "high    src/users/users.service.ts"
assert_contains "deletes_data high: names the rule" "$out" "deletes_data p=0.95"
assert_contains "deletes_data high: set is high" "$out" "class: high"

set_answers '{"src/users/users.service.ts":{"signature_changed":0.9}}'
out=$(TYPESAFE_API_KEY=x run_content --floor low < "$diff_two_files")
assert_contains "signature changed from low: one class up" "$out" "class: medium"
out=$(TYPESAFE_API_KEY=x run_content --floor medium < "$diff_two_files")
assert_contains "signature changed from medium: one class up" "$out" "class: high"

set_answers '{"src/features/profile/Avatar.tsx":{"prod_data_path":0.5}}'
out=$(TYPESAFE_API_KEY=x run_content --floor low < "$diff_two_files")
assert_contains "borderline: file listed unsure" "$out" "unsure: src/features/profile/Avatar.tsx"
assert_contains "borderline: unsure names the predicate" "$out" "prod_data_path p=0.50"
assert_contains "borderline: unsure is medium" "$out" "class: medium"

set_answers '{"src/features/profile/Avatar.tsx":{"deletes_data":0.95}}'
out=$(TYPESAFE_API_KEY=x run_content --floor high < "$diff_two_files")
assert_contains "never lowers: high floor stays high" "$out" "class: high"

: > "$FAKE_LOG"
set_answers '{}'
TYPESAFE_API_KEY=x run_content --floor low < "$diff_two_files" > /dev/null
req=$(head -1 "$FAKE_LOG")
assert_contains "request: model defaults to jev-latest" "$req" '"model":"jev-latest"'
assert_contains "request: every question is a noul" "$req" '"type":"noul"'
assert_not_contains "request: no choice questions" "$req" '"type":"choice"'

set_answers '{"src/users/users.helper.ts":{"caller_sees_change":0.8,"signature_changed":0.38,"additive_only":0.79}}'
out=$(TYPESAFE_API_KEY=x run_content --floor low < "$diff_new_file")
assert_contains "new file: caller/signature predicates ignored" "$out" "low     src/users/users.helper.ts  (new file"
assert_contains "new file: not listed unsure for signature" "$out" "unsure: none"
assert_contains "new file: class stays" "$out" "class: low"
set_answers '{"src/users/users.helper.ts":{"prod_data_path":0.9}}'
out=$(TYPESAFE_API_KEY=x run_content --floor low < "$diff_new_file")
assert_contains "new file: high predicates still apply" "$out" "class: high"

floors="$tmp/floors"
printf 'low\tsrc/features/profile/Avatar.tsx\nmedium\tsrc/users/users.service.ts\n' > "$floors"
set_answers '{"src/users/users.service.ts":{"signature_changed":0.9},"src/features/profile/Avatar.tsx":{"signature_changed":0.9}}'
out=$(TYPESAFE_API_KEY=x run_content --floors "$floors" < "$diff_two_files")
assert_contains "per-file floors: tsx goes low -> medium" "$out" "medium  src/features/profile/Avatar.tsx"
assert_contains "per-file floors: service goes medium -> high" "$out" "high    src/users/users.service.ts"
set_answers '{}'
out=$(TYPESAFE_API_KEY=x run_content --floors "$floors" < "$diff_two_files")
assert_contains "per-file floors: each file keeps its own floor" "$out" "low     src/features/profile/Avatar.tsx  (no escalator)"
assert_contains "per-file floors: set is the highest file" "$out" "class: medium"

# ---------------------------------------------------------------- risk.sh router
echo "# risk.sh router"

out=$(env -u TYPESAFE_API_KEY bash "$here/risk.sh" src/users/users.service.ts 2>&1)
assert_contains "no key: escalators fall back to controller" "$out" "escalators: controller"
assert_contains "no key: path class still printed" "$out" "class: medium"

out=$(TYPESAFE_API_KEY=x RISK_CONTENT=off bash "$here/risk.sh" src/users/users.service.ts 2>&1)
assert_contains "RISK_CONTENT=off: controller" "$out" "escalators: controller"

set_answers '{}'
out=$(TYPESAFE_API_KEY=x RISK_DIFF_FILE="$diff_two_files" bash "$here/risk.sh" src/features/profile/Avatar.tsx src/users/users.service.ts 2>&1)
assert_contains "router: content pass starts from each file's path class (low)" "$out" "low     src/features/profile/Avatar.tsx  (no escalator)"
assert_contains "router: content pass starts from each file's path class (medium)" "$out" "medium  src/users/users.service.ts  (no escalator)"

set_answers '{"src/features/profile/Avatar.tsx":{"auth_or_money":0.92}}'
out=$(TYPESAFE_API_KEY=x RISK_DIFF_FILE="$diff_two_files" bash "$here/risk.sh" src/features/profile/Avatar.tsx 2>&1)
assert_contains "with key: escalators jev" "$out" "escalators: jev"
assert_contains "with key: path floor line kept" "$out" "low     src/features/profile/Avatar.tsx  (feature-local UI)"
assert_contains "with key: content raised the set" "$out" "class: high"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
