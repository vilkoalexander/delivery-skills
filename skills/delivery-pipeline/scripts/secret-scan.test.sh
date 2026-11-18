#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/secret-scan.sh"

new_repo project
echo base > README.md && commit_all

# added NAME EXPECTED_EXIT PATTERN FILE CONTENT — scans a new file holding one line
added() {
  local name=$1 want=$2 pattern=$3 file=$4 content=$5 out code
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" > "$file"
  out=$(bash "$scan" "$file" 2>&1)
  code=$?
  rm -f "$file"
  if [ "$code" != "$want" ]; then nok "$name" "exit $code, wanted $want"$'\n'"$out"
  elif ! grep -qE -- "$pattern" <<< "$out"; then nok "$name" "no match for $pattern"$'\n'"$out"
  elif [ "$want" = 1 ] && grep -qF -- "$content" <<< "$out"; then nok "$name" "output repeats the secret"$'\n'"$out"
  else ok "$name"; fi
}
# Split so this file never trips a scanner itself.
aws="AKIA""ABCDEFGHIJKLMNOP"
jwt='eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop'

echo "# vendor formats, checked everywhere"
added "AWS key id"                1 "src/a.ts:1 — AWS access key id" src/a.ts "const k = '$aws'"
added "private key block"         1 "private key block"  src/key.ts '-----BEGIN RSA PRIVATE ''KEY-----'
added "GitHub token"              1 "GitHub token"       src/a.ts "token: 'ghp_""0123456789abcdefghijABCDEFGHIJ012345'"
added "Slack token"               1 "Slack token"        src/a.ts "xox""b-0123456789-abcdef"
added "Stripe live key"           1 "Stripe live key"    src/a.ts "sk_""live_0123456789abcdefABCD"
added "sk- key"                   1 "API key"            src/a.ts "const c = new Client('sk-""ant-0123456789abcdef0123456789abcdef')"
added "Google API key"            1 "Google API key"     src/a.ts "key: 'AIza""0123456789abcdefghijABCDEFGHIJ01234'"
added "npm token"                 1 "npm token"          .npmrc   "//registry.npmjs.org/:_authToken=npm_""0123456789abcdefghijABCDEFGHIJ012345"
added "vendor key in a test file" 1 "AWS access key id"  src/a.spec.ts "const k = '$aws'"

echo "# generic rules, skipped in tests, docs and examples"
added "literal on a secret key"   1 "literal assigned"   src/config.ts "  apiKey: 'f3a9c1d27b6e4085a1c2'"
added "password in a URL"         1 "password in a URL"  src/db.ts "const url = 'postgres://app:hunter2secret@db.internal:5432/app'"
added "JWT"                       1 "JSON web token"     src/a.ts "const t = '$jwt'"
added "committed env file"        1 "committed env file" .env.production "STRIPE_SECRET=whsec1234567890"
added "env read is clean"         0 "SECRETS: 0 hits"    src/config.ts "  apiKey: process.env.API_KEY,"
added "short label is clean"      0 "SECRETS: 0 hits"    src/form.ts "  password: 'Password1',"
added "config path is clean"      0 "SECRETS: 0 hits"    src/config.ts "  secretKey: 'config.auth.secret.value',"
added "placeholder URL is clean"  0 "SECRETS: 0 hits"    src/db.ts "const url = 'postgres://user:changeme@db:5432/app'"
added "localhost URL is clean"    0 "SECRETS: 0 hits"    src/db.ts "const url = 'postgres://app:hunter2secret@localhost:5432/app'"
added "JWT in a test is clean"    0 "SECRETS: 0 hits"    src/a.spec.ts "const t = '$jwt'"
added "env example is clean"      0 "SECRETS: 0 hits"    .env.example "STRIPE_SECRET=whsec1234567890"

echo "# what is not scanned"
added "lockfile"                  0 "SECRETS: 0 hits"    package-lock.json "\"integrity\": \"$aws\""
SECRET_ALLOW='src/legacy/' added "SECRET_ALLOW path" 0 "SECRETS: 0 hits" src/legacy/a.ts "const k = '$aws'"

mkdir -p src
echo "const k = '$aws'" > src/old.ts && commit_all old
echo "export const x = 1" >> src/old.ts
has "a secret already committed is not this change's" 0 "SECRETS: 0 hits" bash "$scan" src/old.ts
git checkout -q src/old.ts

echo "# which paths"
printf 'line one\nconst k = "%s"\n' "$aws" > src/new.ts
has "no arguments: every changed path"  1 "src/new.ts:2 — AWS access key id" bash "$scan"
has "paths on stdin"                    1 "src/new.ts:2"                     bash -c "echo src/new.ts | bash '$scan'"
has "a hit says what to do"             1 "move each value to the environment" bash "$scan" src/new.ts
has "counts the hits"                   1 "^SECRETS: 1 hits$"                bash "$scan" src/new.ts
commit_all new
has "committed, so the tree is clean"   0 "SECRETS: 0 hits"                  bash "$scan"
has "SECRET_DIFF_RANGE scans a range"   1 "src/new.ts:2"                     env SECRET_DIFF_RANGE=HEAD~1..HEAD bash "$scan"

mkdir -p "$tmp/plain" && cd "$tmp/plain"
has "outside git" 2 "secret-scan: not a git repository" env GIT_CEILING_DIRECTORIES="$tmp" bash "$scan"

finish
