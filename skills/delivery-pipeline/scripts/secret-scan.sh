#!/usr/bin/env bash
# Fails when a line the change adds holds a credential. Not a gate step: the
# project's CI owns credentials. risk.sh runs it before the content pass, so
# no added line with a credential leaves the machine.
#
#   bash secret-scan.sh [path...]              default: every changed path
#   git diff --name-only | bash secret-scan.sh
#
# Prints `path:line — rule` per hit, never the matched text. Exits 1 on any
# hit and 2 when it could not scan (bad pattern, bad range, invalid config). Vendor key formats are checked everywhere; the generic rules
# (password in a URL, a literal assigned to a secret-named key) skip tests,
# fixtures, docs and *.example files, and values that read as placeholders.
#
#   SECRET_DIFF_RANGE  base..head to scan instead of the working tree vs HEAD
#   SECRET_ALLOW       ERE over `path:line:text`; matching lines are not hits
#                      (default: secrets.allow in docs/review/delivery.json)
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "secret-scan: not a git repository" >&2
  exit 2
fi
cd "$root"
source "$here/lib/changes.sh"

range="${SECRET_DIFF_RANGE:-}"
allow="${SECRET_ALLOW:-}"
[ -n "$allow" ] || allow=$(config_get secrets.allow) || exit 2
valid_ere "SECRET_ALLOW (secrets.allow)" "$allow" || exit 2
load_paths "$range" "$@" || exit 2

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

added=$(added_lines "$range" "${scannable[@]}") || exit 2
if [ -n "$allow" ]; then
  added=$(printf '%s\n' "$added" | LC_ALL=C grep -avE -- "$allow" || true)
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
rule "GitLab token"         "$added" '(^|[^A-Za-z0-9])gl(pat|dt|rt|cbt)-[A-Za-z0-9_-]{20,}'
rule "SendGrid key"         "$added" '(^|[^A-Za-z0-9])SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}'
rule "Twilio key"           "$added" '(^|[^A-Za-z0-9])SK[0-9a-f]{32}([^0-9a-f]|$)'
rule "Hugging Face token"   "$added" '(^|[^A-Za-z0-9])hf_[A-Za-z0-9]{30,}'
rule "Stripe webhook secret" "$added" '(^|[^A-Za-z0-9])whsec_[A-Za-z0-9]{24,}'
rule "Slack webhook URL"    "$added" 'hooks\.slack\.com/services/T[A-Za-z0-9]+/B[A-Za-z0-9]+/[A-Za-z0-9]{16,}'
rule "Google OAuth token"   "$added" '(^|[^A-Za-z0-9])ya29\.[A-Za-z0-9_-]{20,}'
rule "DigitalOcean token"   "$added" '(^|[^A-Za-z0-9])do[opr]_v1_[a-f0-9]{64}'
rule "Azure storage key"    "$added" 'AccountKey=[A-Za-z0-9+/]{40,}={0,2}'

# The generic rules guess, so they skip tests, fixtures, docs, examples and placeholder values.
test_or_doc_file='^[^:]*(\.(spec|test)\.[a-z]+|\.example|\.sample|\.mdx?|\.txt):'
test_or_doc_dir='^[^:]*(^|/)(__tests__|tests?|e2e|fixtures|__fixtures__|__mocks__|mocks|docs|cypress|playwright)/'
placeholder='(example|changeme|change-me|placeholder|dummy|sample|your[-_ ]|xxxx|\*\*\*|<[^>]+>|\{\{|localhost|127\.0\.0\.1)'
env_reference='(\$\{|process\.env|import\.meta\.env)'
outside_tests=$(printf '%s\n' "$added" \
  | LC_ALL=C grep -avE "$test_or_doc_file" \
  | LC_ALL=C grep -avE "$test_or_doc_dir" \
  | LC_ALL=C grep -aviE -- "$placeholder" || true)
generic=$(printf '%s\n' "$outside_tests" | LC_ALL=C grep -avE -- "$env_reference" || true)

rule "password in a URL" "$generic" "[a-z][a-z0-9+.-]*://[^/[:space:]:@$url_quote]+:[^@/[:space:]$url_quote]{3,}@"

secret_name='(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key)'
# 16+ characters with a digit: long enough and mixed enough not to be a label or a config path.
with_mixed_literal=$(printf '%s\n' "$generic" | LC_ALL=C grep -aE "${quote}[A-Za-z_+/=.-]*[0-9][A-Za-z0-9_+/=.-]*$quote" || true)
rule "literal assigned to a secret-named key" "$with_mixed_literal" \
  "${secret_name}[$url_quote]?[[:space:]]*[:=][[:space:]]*${quote}[A-Za-z0-9_+/=.-]{16,}$quote" i

# A value with no quotes is how YAML, .properties, .toml and .ini files write one.
in_config_file=$(printf '%s\n' "$generic" | LC_ALL=C grep -aE '^[^:]*\.(ya?ml|properties|toml|ini|conf|cfg):' || true)
rule "value of a secret-named key in a config file" "$in_config_file" \
  "^[^:]*:[0-9]+:[[:space:]-]*[A-Za-z0-9_.-]*${secret_name}[A-Za-z0-9_.-]*[[:space:]]*[:=][[:space:]]*[A-Za-z_+/=.-]*[0-9][A-Za-z0-9_+/=.-]{15,}[[:space:]]*(#.*)?\$" i

# A line that reads the environment can still carry the real value as its fallback.
with_env_reference=$(printf '%s\n' "$outside_tests" | LC_ALL=C grep -aE -- "$env_reference" || true)
rule "literal fallback next to an env reference" "$with_env_reference" \
  "${secret_name}.*(\|\||\?\?|:-)[[:space:]]*${quote}?[A-Za-z_+/=.-]*[0-9][A-Za-z0-9_+/=.-]{15,}" i

in_env_file=$(printf '%s\n' "$generic" | LC_ALL=C grep -aE '^[^:]*(^|/)\.env[^/:]*:' || true)
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
