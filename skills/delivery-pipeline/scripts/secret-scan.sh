#!/usr/bin/env bash
# Fails when a line the change adds holds a credential. Reads added lines only,
# so a secret already in the repo is not this chunk's failure.
#
#   bash secret-scan.sh [path...]              default: every changed path
#   git diff --name-only | bash secret-scan.sh
#
# Prints `path:line — rule` per hit, never the matched text, and exits 1 on
# any hit. Vendor key formats are checked everywhere; the generic rules
# (password in a URL, a literal assigned to a secret-named key) skip tests,
# fixtures, docs and *.example files, and values that read as placeholders.
#
#   SECRET_DIFF_RANGE  base..head to scan instead of the working tree vs HEAD
#   SECRET_ALLOW       ERE over `path:line:text`; matching lines are not hits
#                      (default: secrets.allow in docs/review/delivery.json)
set -uo pipefail

range="${SECRET_DIFF_RANGE:-}"
allow="${SECRET_ALLOW:-$(node "$(dirname "$0")/config.mjs" get secrets.allow 2>/dev/null)}"
if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "secret-scan: not a git repository" >&2
  exit 2
fi
cd "$root"

# ------------------------------------------------------------- which paths
paths=("$@")

# A harness can hand a pipe that never closes; wait one second for each line.
read_paths_from_stdin() {
  local line
  [ -t 0 ] && return 0
  while IFS= read -r -t 1 line; do
    [ -n "$line" ] && paths+=("$line")
  done
}

changed_paths() {
  if [ -n "$range" ]; then
    git diff --name-only "$range"
  else
    { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
  fi
}

[ ${#paths[@]} -gt 0 ] || read_paths_from_stdin
if [ ${#paths[@]} -eq 0 ]; then
  while IFS= read -r path; do
    paths+=("$path")
  done < <(changed_paths)
fi

scannable=()
for path in ${paths[@]+"${paths[@]}"}; do
  case "$path" in
    *pnpm-lock.yaml|*package-lock.json|*yarn.lock|*bun.lock|*bun.lockb) ;;
    *.min.js|*.map|*.snap) ;;
    *.svg|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.woff|*.woff2|*.ttf|*.zip|*.gz) ;;
    *) scannable+=("$path") ;;
  esac
done
if [ ${#scannable[@]} -eq 0 ]; then
  echo "SECRETS: 0 hits"
  exit 0
fi

# ------------------------------------------------------------- added lines
is_tracked() {
  git ls-files --error-unmatch "$1" > /dev/null 2>&1
}

# A diff of the paths; an untracked file counts as added whole.
diff_of() {
  local file
  if [ -n "$range" ]; then
    git diff -U0 "$range" -- "$@"
    return
  fi
  git diff -U0 HEAD -- "$@"
  for file in "$@"; do
    [ -f "$file" ] || continue
    is_tracked "$file" && continue
    printf '+++ b/%s\n' "$file"
    sed 's/^/+/' "$file"
  done
}

# Turns a -U0 diff into "path:line:text", one line per added line.
number_added_lines() {
  awk '
    /^\+\+\+ b\// { file = substr($0, 7); line = 0; next }
    /^@@/         { split($3, hunk, /[,+]/); line = hunk[2] - 1; next }
    /^\+/         { line++; print file ":" line ":" substr($0, 2); next }
    /^-/          { next }
                  { line++ }
  '
}

added=$(diff_of "${scannable[@]}" 2>/dev/null | number_added_lines | LC_ALL=C grep -a . || true)
if [ -n "$allow" ]; then
  added=$(printf '%s\n' "$added" | grep -vE -- "$allow" || true)
fi

# ------------------------------------------------------------------- rules
hits=""

# rule NAME LINES REGEX [i] — records "path:line — NAME" for each matching line, never the text
rule() {
  local name=$1 lines=$2 regex=$3 ignore_case=${4:-} found
  found=$(printf '%s\n' "$lines" \
    | LC_ALL=C grep -a"$ignore_case"E -- "$regex" \
    | sed -E 's/^([^:]*:[0-9]+):.*/\1/' \
    | sed "s/\$/ — $name/")
  [ -n "$found" ] && hits="$hits$found"$'\n'
}

quote="[\"'\`]"
url_quote="\"'"

rule "AWS access key id"    "$added" '(^|[^A-Z0-9])(AKIA|ASIA)[0-9A-Z]{16}([^A-Z0-9]|$)'
rule "private key block"    "$added" '-----BEGIN ([A-Z]+ )*PRIVATE KEY-----'
rule "GitHub token"         "$added" '(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})'
rule "Slack token"          "$added" 'xox[baprs]-[A-Za-z0-9-]{10,}'
rule "Stripe live key"      "$added" '(sk|rk)_live_[A-Za-z0-9]{16,}'
rule "API key (sk- format)" "$added" '(^|[^A-Za-z0-9_-])sk-(ant-|proj-)?[A-Za-z0-9_-]{32,}'
rule "Google API key"       "$added" '(^|[^A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}([^A-Za-z0-9_-]|$)'
rule "npm token"            "$added" '(^|[^A-Za-z0-9])npm_[A-Za-z0-9]{36}'

# The generic rules guess, so they skip tests, fixtures, docs, examples and placeholder values.
test_or_doc_file='^[^:]*(\.(spec|test)\.[a-z]+|\.example|\.sample|\.mdx?|\.txt):'
test_or_doc_dir='^[^:]*(^|/)(__tests__|tests?|e2e|fixtures|__fixtures__|__mocks__|mocks|docs|cypress|playwright)/'
placeholder='(example|changeme|change-me|placeholder|dummy|sample|your[-_ ]|xxxx|\*\*\*|<[^>]+>|\$\{|\{\{|process\.env|import\.meta\.env|localhost|127\.0\.0\.1)'
generic=$(printf '%s\n' "$added" \
  | grep -vE "$test_or_doc_file" \
  | grep -vE "$test_or_doc_dir" \
  | grep -viE -- "$placeholder" || true)

rule "password in a URL" "$generic" "[a-z][a-z0-9+.-]*://[^/[:space:]:@$url_quote]+:[^@/[:space:]$url_quote]{3,}@"

secret_name='(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key)'
# 16+ characters with a digit: long enough and mixed enough not to be a label or a config path.
with_mixed_literal=$(printf '%s\n' "$generic" | grep -E "${quote}[A-Za-z_+/=.-]*[0-9][A-Za-z0-9_+/=.-]*$quote" || true)
rule "literal assigned to a secret-named key" "$with_mixed_literal" \
  "${secret_name}[$url_quote]?[[:space:]]*[:=][[:space:]]*${quote}[A-Za-z0-9_+/=.-]{16,}$quote" i

in_env_file=$(printf '%s\n' "$generic" | grep -E '^[^:]*(^|/)\.env[^/:]*:' || true)
rule "value in a committed env file" "$in_env_file" \
  "^[^:]*:[0-9]+:[[:space:]]*(export[[:space:]]+)?[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|KEY)[A-Z0-9_]*=[$url_quote]?[^[:space:]$url_quote]{8,}" i

rule "JSON web token" "$generic" 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'

# ------------------------------------------------------------------ report
hits=$(printf '%s' "$hits" | sort -u)
count=0
if [ -n "$hits" ]; then
  count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
  printf '%s\n' "$hits"
fi
echo "SECRETS: $count hits"
if [ "$count" -gt 0 ]; then
  echo "move each value to the environment and rotate it if it was real; a false hit goes in SECRET_ALLOW"
  exit 1
fi
exit 0
