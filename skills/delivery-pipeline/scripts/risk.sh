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
#   RISK_HIGH    extra ERE for paths that are always high   (project layer)
#   RISK_MEDIUM  extra ERE for paths that are always medium
set -uo pipefail

MAX_LOW="${RISK_MAX_LOW_FILES:-5}"

if [ $# -gt 0 ]; then
  paths=("$@")
else
  paths=()
  while IFS= read -r line; do [ -n "$line" ] && paths+=("$line"); done
fi
[ ${#paths[@]} -eq 0 ] && { echo "usage: risk.sh <path>... | git diff --name-only | risk.sh" >&2; exit 2; }

# Returns "class<TAB>rule" for one path. High rules first, then low, then medium.
classify() {
  local p="$1"
  if [ -n "${RISK_HIGH:-}" ] && [[ "$p" =~ ${RISK_HIGH} ]]; then echo $'high\tRISK_HIGH'; return; fi
  if [ -n "${RISK_MEDIUM:-}" ] && [[ "$p" =~ ${RISK_MEDIUM} ]]; then echo $'medium\tRISK_MEDIUM'; return; fi

  # high — one-way doors
  [[ "$p" =~ \.prisma$ || "$p" =~ (^|/)migrations/ || "$p" =~ \.sql$ ]] && { echo $'high\tschema or migration'; return; }
  [[ "$p" =~ (^|/)(libs|packages)/(shared|contracts|api-types|api-contract)(/|$) ]] && { echo $'high\tshared contract package'; return; }
  [[ "$p" =~ (^|/)(auth|guards|strategies|session)(/|\.) || "$p" =~ \.(guard|strategy)\.ts$ || "$p" =~ (jwt|passport|oauth) ]] && { echo $'high\tauth, guard, session'; return; }
  [[ "$p" =~ (payment|billing|ledger|invoice|checkout|wallet|stripe|subscription) ]] && { echo $'high\tmoney path'; return; }
  [[ "$p" =~ (^|/)\.env(\.|$) || "$p" =~ (secret|credential) ]] && { echo $'high\tenv or secrets'; return; }
  [[ "$p" =~ (^|/)\.github/workflows/ || "$p" =~ (^|/)(Dockerfile|docker-compose[^/]*|helm|terraform|k8s|deploy|infra)(/|\.|$) ]] && { echo $'high\tCI, deploy, infra'; return; }

  # low — local, visible, cheap
  [[ "$p" =~ \.(spec|test)\.[cm]?[jt]sx?$ || "$p" =~ (^|/)(__tests__|test|tests|e2e|cypress|playwright)/ ]] && { echo $'low\ttests'; return; }
  [[ "$p" =~ \.(md|mdx|txt)$ || "$p" =~ (^|/)docs/ ]] && { echo $'low\tdocs'; return; }
  [[ "$p" =~ \.(css|scss|sass|less|styl)$ || "$p" =~ (^|/)(styles|theme|assets|public|static|fonts|images)/ ]] && { echo $'low\tstyling or assets'; return; }
  [[ "$p" =~ (^|/)(i18n|locales|translations)/ ]] && { echo $'low\tcopy, i18n'; return; }
  [[ "$p" =~ (eslint|prettier|editorconfig|tsconfig|vitest|jest|babel|vite|webpack)[^/]*$ || "$p" =~ (^|/)\.(vscode|idea)/ ]] && { echo $'low\tdev tooling config'; return; }
  [[ "$p" =~ (^|/)(features|pages|views|screens|routes)/.*\.(tsx|jsx|vue|svelte|html)$ || "$p" =~ (^|/)(features|pages|views|screens)/.*\.component\.ts$ ]] && { echo $'low\tfeature-local UI'; return; }

  # medium — shared behaviour, reversible
  [[ "$p" =~ \.(service|controller|module|resolver|interceptor|filter|pipe|middleware)\.ts$ ]] && { echo $'medium\tNestJS unit'; return; }
  [[ "$p" =~ (^|/)(components/ui|hooks|lib|utils|shared|common|store|state|api|services)(/|$) ]] && { echo $'medium\tshared primitive, hook or util'; return; }
  [[ "$p" =~ (^|/)package\.json$ || "$p" =~ (^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock)$ ]] && { echo $'medium\tdependency change'; return; }
  [[ "$p" =~ \.(tsx|jsx|vue|svelte)$ || "$p" =~ \.component\.ts$ || "$p" =~ \.html$ ]] && { echo $'low\tleaf component'; return; }

  echo $'medium\tno rule matched — unsure is medium'
}

rank() { case "$1" in high) echo 3;; medium) echo 2;; *) echo 1;; esac; }

top=1
for p in "${paths[@]}"; do
  IFS=$'\t' read -r cls rule < <(classify "$p")
  printf '%-7s %s  (%s)\n' "$cls" "$p" "$rule"
  r=$(rank "$cls"); [ "$r" -gt "$top" ] && top=$r
done

n=${#paths[@]}
note=""
if [ "$n" -gt "$MAX_LOW" ] && [ "$top" -lt 2 ]; then top=2; note="  (raised: $n files > RISK_MAX_LOW_FILES=$MAX_LOW)"; fi
case "$top" in 3) cls=high;; 2) cls=medium;; *) cls=low;; esac
echo "files: $n"
echo "class: $cls$note"
