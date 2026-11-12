#!/usr/bin/env bash
set -euo pipefail
log="${DELIVERY_LOG:-$HOME/.claude/delivery-skills/log.jsonl}"
keys=(plan chunk risk mode implementer reviewer fix_rounds findings verify decision)
optional=(static human_found)

usage() {
  echo "usage: run-log.sh add ${keys[*]/%/=<value>} [${optional[*]/%/=<n>}]" >&2
  echo "       run-log.sh stats" >&2
  exit 2
}
die() { echo "run-log: $1" >&2; exit 2; }
is_key() { case " ${keys[*]} ${optional[*]} " in *" $1 "*) return 0 ;; esac; return 1; }
oneof() { # key value allowed-pattern
  [[ $2 =~ ^($3)$ ]] || die "$1 must be one of: ${3//|/, } (got '$2')"
}

if [ "${1:-}" = stats ]; then
  [ -s "$log" ] || { echo "run-log: no entries in $log"; exit 0; }
  jq -rs '
    def n(f): map(f // 0) | add;
    def d(v): map(select(.decision == v)) | length;
    (["risk", "chunks", "static", "review", "human", "accepted", "edited", "rejected"] | @tsv),
    (group_by(.risk)[] | [.[0].risk, length, n(.static), n(.findings), n(.human_found),
       d("accepted"), d("edited"), d("rejected")] | @tsv)' "$log" | column -t
  echo "static, review, human: defects each caught, in the order they run"
  exit 0
fi
[ "${1:-}" = add ] || usage
shift

args=()
seen=" "
for pair in "$@"; do
  [[ $pair == *=* ]] || die "expected key=value, got '$pair'"
  key=${pair%%=*}
  value=${pair#*=}
  is_key "$key" || die "unknown key '$key'"
  case $seen in *" $key "*) die "repeated key '$key'" ;; esac
  case $key in
    risk) oneof risk "$value" 'low|medium|high' ;;
    mode) oneof mode "$value" 'gated|long' ;;
    verify) oneof verify "$value" 'pass|fail|none' ;;
    decision) oneof decision "$value" 'accepted|edited|rejected' ;;
    chunk|fix_rounds|findings|static|human_found) [[ $value =~ ^[0-9]+$ ]] || die "$key must be a whole number (got '$value')" ;;
  esac
  args+=(--arg "$key" "$value")
  seen+="$key "
done

for key in "${keys[@]}"; do
  case $seen in *" $key "*) ;; *) die "missing $key" ;; esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
base=$(git rev-parse HEAD 2>/dev/null || echo none)
line=$(jq -cn "${args[@]}" \
  --arg ts "$(date -u +%FT%TZ)" --arg project "$root" --arg base "$base" \
  '$ARGS.named | with_entries(if (.key | IN("chunk", "fix_rounds", "findings", "static", "human_found")) then .value |= tonumber else . end)')

mkdir -p "$(dirname "$log")"
printf '%s\n' "$line" >> "$log"
bash "$(dirname "$0")/event.sh" log chunk_logged "entry:=$line" || true
