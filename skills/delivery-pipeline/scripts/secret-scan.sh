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
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "secret-scan: not a git repository" >&2; exit 2; }
cd "$root"

paths=("$@")
if [ ${#paths[@]} -eq 0 ] && [ ! -t 0 ] && IFS= read -r -t 1 l; then
  [ -n "$l" ] && paths+=("$l")
  while IFS= read -r -t 1 l; do [ -n "$l" ] && paths+=("$l"); done
fi
if [ ${#paths[@]} -eq 0 ]; then
  if [ -n "$range" ]; then while IFS= read -r l; do paths+=("$l"); done < <(git diff --name-only "$range")
  else while IFS= read -r l; do paths+=("$l"); done < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u); fi
fi

scan=()
for p in ${paths[@]+"${paths[@]}"}; do
  case "$p" in
    *pnpm-lock.yaml|*package-lock.json|*yarn.lock|*bun.lock|*bun.lockb|*.min.js|*.map|*.snap|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.woff|*.woff2|*.ttf|*.zip|*.gz) ;;
    *) scan+=("$p") ;;
  esac
done
[ ${#scan[@]} -eq 0 ] && { echo "SECRETS: 0 hits"; exit 0; }

# Added lines of the diff, as "path:line:text".
added() {
  if [ -n "$range" ]; then git diff -U0 "$range" -- "$@"
  else git diff -U0 HEAD -- "$@"; for f in "$@"; do [ -f "$f" ] || continue; git ls-files --error-unmatch "$f" >/dev/null 2>&1 || { printf '+++ b/%s\n' "$f"; sed 's/^/+/' "$f"; }; done; fi |
  awk '/^\+\+\+ b\//{f=substr($0,7);n=0;next} /^@@/{split($3,a,/[,+]/);n=a[2]-1;next} /^\+/{n++;print f":"n":"substr($0,2);next} /^-/{next} {n++}'
}

adds=$(added "${scan[@]}" 2>/dev/null | LC_ALL=C grep -a . || true)
[ -n "$allow" ] && adds=$(printf '%s\n' "$adds" | grep -vE -- "$allow" || true)

hits=""
rule() { # flags, name, ERE over the added lines
  local out; out=$(printf '%s\n' "$3" | LC_ALL=C grep -a"$1"E -- "$4" | sed -E 's/^([^:]*:[0-9]+):.*/\1/' | sed "s/\$/ — $2/")
  [ -n "$out" ] && hits="$hits$out"$'\n'
}

rule "" "AWS access key id"       "$adds" '(^|[^A-Z0-9])(AKIA|ASIA)[0-9A-Z]{16}([^A-Z0-9]|$)'
rule "" "private key block"       "$adds" '-----BEGIN ([A-Z]+ )*PRIVATE KEY-----'
rule "" "GitHub token"            "$adds" '(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})'
rule "" "Slack token"             "$adds" 'xox[baprs]-[A-Za-z0-9-]{10,}'
rule "" "Stripe live key"         "$adds" '(sk|rk)_live_[A-Za-z0-9]{16,}'
rule "" "API key (sk- format)"    "$adds" '(^|[^A-Za-z0-9_-])sk-(ant-|proj-)?[A-Za-z0-9_-]{32,}'
rule "" "Google API key"          "$adds" '(^|[^A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}([^A-Za-z0-9_-]|$)'
rule "" "npm token"               "$adds" '(^|[^A-Za-z0-9])npm_[A-Za-z0-9]{36}'

placeholder='(example|changeme|change-me|placeholder|dummy|sample|your[-_ ]|xxxx|\*\*\*|<[^>]+>|\$\{|\{\{|process\.env|import\.meta\.env|localhost|127\.0\.0\.1)'
generic=$(printf '%s\n' "$adds" \
  | grep -vE '^[^:]*(\.(spec|test)\.[a-z]+|\.example|\.sample|\.mdx?|\.txt):' \
  | grep -vE '^[^:]*(^|/)(__tests__|tests?|e2e|fixtures|__fixtures__|__mocks__|mocks|docs|cypress|playwright)/' \
  | grep -viE -- "$placeholder" || true)
rule "" "password in a URL"       "$generic" '[a-z][a-z0-9+.-]*://[^/[:space:]:@"'"'"']+:[^@/[:space:]"'"'"']{3,}@'
named='(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key)'
# 16+ characters with a digit: long enough and mixed enough not to be a label or a config path.
literal=$(printf '%s\n' "$generic" | grep -E '["'"'"'`][A-Za-z_+/=.-]*[0-9][A-Za-z0-9_+/=.-]*["'"'"'`]' || true)
rule "i" "literal assigned to a secret-named key" "$literal" "$named"'["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'`][A-Za-z0-9_+/=.-]{16,}["'"'"'`]'
envfile=$(printf '%s\n' "$generic" | grep -E '^[^:]*(^|/)\.env[^/:]*:' || true)
rule "i" "value in a committed env file" "$envfile" '^[^:]*:[0-9]+:[[:space:]]*(export[[:space:]]+)?[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|KEY)[A-Z0-9_]*=["'"'"']?[^[:space:]"'"'"']{8,}'
rule "" "JSON web token"          "$generic" 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'

hits=$(printf '%s' "$hits" | sort -u)
n=0; [ -n "$hits" ] && n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
[ "$n" -gt 0 ] && printf '%s\n' "$hits"
echo "SECRETS: $n hits"
[ "$n" -gt 0 ] && { echo "move each value to the environment and rotate it if it was real; a false hit goes in SECRET_ALLOW"; exit 1; }
exit 0
