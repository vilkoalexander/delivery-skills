#!/usr/bin/env bash
# Suggests a risk class for a set of changed paths.
#
#   bash scripts/risk.sh <path>...
#   git diff --name-only | bash scripts/risk.sh
#
# Prints one line per path (class, path, matched rule), then the file count and
# the class for the set: the highest class any path hit, raised to medium when
# more than RISK_MAX_LOW_FILES paths (default 5) changed. It sees paths only —
# it cannot know a signature changed or a caller exists — so it is a floor to
# tag from, never a verdict.
#
#   RISK_HIGH    extra ERE for paths that are always high
#   RISK_MEDIUM  extra ERE for paths that are always medium
#                (default for both: risk.high and risk.medium in docs/review/delivery.json)
#
# With TYPESAFE_API_KEY set, the path class becomes a floor and risk-content.sh
# reads the hunks for the escalators (signature changed, caller sees a change,
# production data path, deletes data, auth or money). The last line then says
# who owns the escalators: `escalators: jev` when the content pass ran,
# `escalators: controller` when it did not and the controller must apply the
# escalator bullets from SKILL.md itself.
#
#   RISK_CONTENT=off    skip the content pass even with a key
#   RISK_DIFF_RANGE     base..head for the content pass (default: working tree)
#   RISK_DIFF_FILE      read the diff from this file instead of git
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
max_low_files="${RISK_MAX_LOW_FILES:-5}"

source "$here/lib/changes.sh"

project_high="${RISK_HIGH:-}"
[ -n "$project_high" ] || project_high=$(config_get risk.high) || exit 2
project_medium="${RISK_MEDIUM:-}"
[ -n "$project_medium" ] || project_medium=$(config_get risk.medium) || exit 2
valid_ere "RISK_HIGH (risk.high)" "$project_high" || exit 2
valid_ere "RISK_MEDIUM (risk.medium)" "$project_medium" || exit 2

paths=("$@")
# A harness can hand a pipe that never closes; wait one second for each line.
if [ ${#paths[@]} -eq 0 ] && [ ! -t 0 ]; then
  while IFS= read -r -t 1 line; do
    [ -n "$line" ] && paths+=("$(unquote_git_path "$line")")
  done
fi
if [ ${#paths[@]} -eq 0 ] && git rev-parse --git-dir > /dev/null 2>&1; then
  while IFS= read -r -d '' line; do paths+=("$line"); done < <(changed_paths 2> /dev/null)
fi
if [ ${#paths[@]} -eq 0 ]; then
  echo "usage: risk.sh [path...]    paths also on stdin; with none, each path that differs from DELIVERY_BASE (default HEAD)" >&2
  exit 2
fi

# ------------------------------------------------------------ path rules
# class :: rule :: pattern (ERE over the path). The first line that matches wins.
# A pattern that starts with (?i) is matched against the path in lower case.
rules=(
  # a chunk that edits these changes what the gate checks
  'high :: the config of the gate :: (^|/)docs/review/(delivery\.json|drift\.checks)$'

  # prose and styles are never the auth or money logic they are named after
  'low :: docs :: \.(md|mdx)$'
  'low :: styling or assets :: \.(css|scss|sass|less|styl)$'
  'medium :: dependency change :: (^|/)requirements[^/]*\.txt$'

  # high — one-way doors
  'high :: schema or migration :: \.prisma$|(^|/)migrations?/|\.sql$|Entity\.(java|kt)$|\.entity\.ts$'
  'high :: shared contract package :: (^|/)(libs|packages)/(shared|contracts|api-types|api-contract)(/|$)'
  'high :: auth, guard, session :: (^|/)(auth|guards|strategies|session|security|acl)(/|\.)|\.(guard|strategy)\.ts$|(Security|Auth[a-z]*|Jwt|Token|Permission)[A-Za-z]*\.(java|kt)$'
  'high :: auth, guard, session :: (?i)(jwt|passport|oauth)'
  'high :: money path :: (?i)(payment|billing|ledger|invoice|checkout|wallet|stripe|subscription)'
  'high :: env or secrets :: (^|/)\.env(\.|$)'
  'high :: env or secrets :: (?i)(^|[^a-z])(secrets?|credentials?)([^a-z]|$)'
  'high :: CI, deploy, infra :: (^|/)\.github/workflows/|(^|/)(Dockerfile|docker-compose[^/]*|helm|terraform|k8s|deploy|infra)(/|\.|$)'

  # low — local, visible, cheap
  'low :: tests :: \.(spec|test)\.[cm]?[jt]sx?$|(^|/)(__tests__|test|tests|e2e|cypress|playwright|testFixtures|integrationTest)/|(Test|Tests|IT)\.(java|kt)$'
  'low :: docs :: \.txt$|(^|/)docs/'
  'low :: styling or assets :: (^|/)(styles|theme|assets|public|static|fonts|images)/'
  'low :: copy, i18n :: (^|/)(i18n|locales|translations)/'
  'low :: dev tooling config :: (^|/)\.?(eslint|prettier|editorconfig|tsconfig|vitest|jest|babel|vite|webpack)[^/]*$|(^|/)\.(vscode|idea)/'
  'low :: feature-local UI :: (^|/)(features|pages|views|screens|routes)/.*\.(tsx|jsx|vue|svelte|html)$|(^|/)(features|pages|views|screens)/.*\.component\.ts$'

  # medium — shared behaviour, reversible
  'medium :: NestJS unit :: \.(service|controller|module|resolver|interceptor|filter|pipe|middleware)\.ts$'
  'medium :: Spring unit :: (Controller|Service|ServiceImpl|Repository|Specification|Configuration|Config|Listener|Handler|Filter|Aspect)\.(java|kt)$'
  'medium :: runtime configuration :: (^|/)application[^/]*\.(yml|yaml|properties)$'
  'medium :: shared primitive, hook or util :: (^|/)(components/ui|hooks|lib|utils|shared|common|store|state|api|services)(/|$)'
  'medium :: dependency change :: (^|/)package\.json$|(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock)$|(^|/)(build|settings)\.gradle(\.kts)?$|(^|/)(pom\.xml|gradle\.properties|libs\.versions\.toml)$'

  'low :: leaf component :: \.(tsx|jsx|vue|svelte)$|\.component\.ts$|\.html$'
)

# Prints "class<TAB>rule" for one path.
classify() {
  local path=$1 lower rule class name pattern subject
  if [ -n "$project_high" ] && [[ $path =~ $project_high ]]; then
    printf 'high\tRISK_HIGH\n'
    return
  fi
  if [ -n "$project_medium" ] && [[ $path =~ $project_medium ]]; then
    printf 'medium\tRISK_MEDIUM\n'
    return
  fi

  lower=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
  for rule in "${rules[@]}"; do
    class=${rule%% :: *}
    rule=${rule#* :: }
    name=${rule%% :: *}
    pattern=${rule#* :: }
    subject=$path
    if [[ $pattern == '(?i)'* ]]; then
      pattern=${pattern#'(?i)'}
      subject=$lower
    fi
    if [[ $subject =~ $pattern ]]; then
      printf '%s\t%s\n' "$class" "$name"
      return
    fi
  done
  printf 'medium\tno rule matched — unsure is medium\n'
}

rank_of() {
  case "$1" in
    high)   echo 3 ;;
    medium) echo 2 ;;
    *)      echo 1 ;;
  esac
}

class_of() {
  case "$1" in
    3) echo high ;;
    2) echo medium ;;
    *) echo low ;;
  esac
}

# --------------------------------------------------------- class for the set
floors=$(mktemp)
trap 'rm -f "$floors"' EXIT

highest=1
for path in "${paths[@]}"; do
  IFS=$'\t' read -r class rule < <(classify "$path")
  printf '%-7s %s  (%s)\n' "$class" "$path" "$rule"
  printf '%s\t%s\n' "$class" "$path" >> "$floors"
  rank=$(rank_of "$class")
  [ "$rank" -gt "$highest" ] && highest=$rank
done

file_count=${#paths[@]}
note=""
if [ "$file_count" -gt "$max_low_files" ] && [ "$highest" -lt 2 ]; then
  highest=2
  note="  (raised: $file_count files > RISK_MAX_LOW_FILES=$max_low_files)"
fi
class=$(class_of "$highest")
echo "files: $file_count"

manifest=$'\t''(.*/)?(package\.json|pnpm-lock\.yaml|package-lock\.json|yarn\.lock|(build|settings)\.gradle(\.kts)?|pom\.xml|gradle\.properties|libs\.versions\.toml|requirements[^/]*\.txt)$'
dependency_paths=$(grep -cE "$manifest" "$floors")
if [ "$dependency_paths" -gt 0 ] && [ "$dependency_paths" -lt "$file_count" ]; then
  echo "mixed: dependency change shares the chunk with other paths ($((file_count - dependency_paths))); a version bump goes in its own chunk"
fi

# ---------------------------------------------------------------- router
if [ -z "${TYPESAFE_API_KEY:-}" ] || [ "${RISK_CONTENT:-on}" = "off" ]; then
  echo "class: $class$note"
  echo "escalators: controller"
  exit 0
fi

# The content pass sends file text to an outside service: never an env file, a
# lockfile, or anything from a change the secret scan has a hit in.
sendable=()
for path in "${paths[@]}"; do
  case "$path" in
    .env|.env.*|*/.env|*/.env.*|*.pem|*.key|*.p12|*.pfx|*.keystore|*.jks) ;;
    *pnpm-lock.yaml|*package-lock.json|*yarn.lock|*bun.lock|*bun.lockb) ;;
    *) sendable+=("$path") ;;
  esac
done
if [ -z "${RISK_DIFF_FILE:-}" ]; then
  if [ ${#sendable[@]} -eq 0 ]; then
    echo "class: $class$note"
    echo "escalators: controller  (no path the content pass may read)"
    exit 0
  fi
  if ! SECRET_DIFF_RANGE="${RISK_DIFF_RANGE:-}" bash "$here/secret-scan.sh" "${sendable[@]}" > /dev/null 2>&1; then
    echo "class: $class$note"
    echo "escalators: controller  (content pass not run: the secret scan does not pass on these paths)"
    exit 0
  fi
fi

diff_for_content_pass() {
  if [ -n "${RISK_DIFF_FILE:-}" ]; then
    cat "$RISK_DIFF_FILE"
    return
  fi
  changes_diff "${RISK_DIFF_RANGE:-}" --src-prefix=a/ --dst-prefix=b/ -- "${sendable[@]}"
}

echo "paths: $class$note"
echo "--- content (${RISK_CONTENT_MODEL:-jev-latest})"
if diff_for_content_pass | bash "$here/risk-content.sh" --floor "$class" --floors "$floors"; then
  if [ "${RISK_CONTENT_DRY:-}" = "1" ]; then
    echo "escalators: controller  (dry run)"
  else
    echo "escalators: jev"
  fi
else
  echo "escalators: controller  (content pass failed; apply the escalators yourself)"
  exit 1
fi
