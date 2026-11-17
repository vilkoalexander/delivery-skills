#!/usr/bin/env bash
set -euo pipefail

log="${DELIVERY_LOG:-$HOME/.claude/delivery-skills/log.jsonl}"
required=(plan chunk risk mode implementer reviewer fix_rounds findings verify decision)
optional=(static human_found)
numeric='chunk|fix_rounds|findings|static|human_found'

usage() {
  echo "usage: run-log.sh add ${required[*]/%/=<value>} [${optional[*]/%/=<n>}]" >&2
  echo "       run-log.sh stats" >&2
  exit 2
}

die() {
  echo "run-log: $1" >&2
  exit 2
}

is_key() {
  [[ " ${required[*]} ${optional[*]} " == *" $1 "* ]]
}

# one_of KEY VALUE ALLOWED — ALLOWED is an alternation such as 'low|medium|high'
one_of() {
  [[ $2 =~ ^($3)$ ]] || die "$1 must be one of: ${3//|/, } (got '$2')"
}

print_stats() {
  if [ ! -s "$log" ]; then
    echo "run-log: no entries in $log"
    return
  fi
  jq -rs '
    def total(field): map(field // 0) | add;
    def decided(value): map(select(.decision == value)) | length;
    (["risk", "chunks", "static", "review", "human", "accepted", "edited", "rejected"] | @tsv),
    (group_by(.risk)[]
      | [.[0].risk, length, total(.static), total(.findings), total(.human_found),
         decided("accepted"), decided("edited"), decided("rejected")]
      | @tsv)
  ' "$log" | column -t
  echo "static, review, human: defects each caught, in the order they run"
}

if [ "${1:-}" = stats ]; then
  print_stats
  exit 0
fi
[ "${1:-}" = add ] || usage
shift

fields=()
seen=" "
for pair in "$@"; do
  [[ $pair == *=* ]] || die "expected key=value, got '$pair'"
  key=${pair%%=*}
  value=${pair#*=}
  is_key "$key" || die "unknown key '$key'"
  [[ $seen != *" $key "* ]] || die "repeated key '$key'"

  case $key in
    risk)     one_of risk "$value" 'low|medium|high' ;;
    mode)     one_of mode "$value" 'gated|long' ;;
    verify)   one_of verify "$value" 'pass|fail|none' ;;
    decision) one_of decision "$value" 'accepted|edited|rejected' ;;
  esac
  if [[ $key =~ ^($numeric)$ ]]; then
    [[ $value =~ ^[0-9]+$ ]] || die "$key must be a whole number (got '$value')"
  fi

  fields+=(--arg "$key" "$value")
  seen+="$key "
done

for key in "${required[@]}"; do
  [[ $seen == *" $key "* ]] || die "missing $key"
done

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
base=$(git rev-parse HEAD 2>/dev/null || echo none)
entry=$(jq -cn "${fields[@]}" \
  --arg ts "$(date -u +%FT%TZ)" --arg project "$root" --arg base "$base" '
  $ARGS.named
  | with_entries(
      if (.key | IN("chunk", "fix_rounds", "findings", "static", "human_found")) then .value |= tonumber else . end
    )
')

mkdir -p "$(dirname "$log")"
printf '%s\n' "$entry" >> "$log"
bash "$(dirname "$0")/event.sh" log chunk_logged "entry:=$entry" || true
