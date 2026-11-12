#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
phases='implement|gate|review|fix|verify|cross|report|final'
keys=(phase chunk of name risk plan round)

usage() {
  echo "usage: mark.sh phase=<${phases}> chunk=N of=M [name=<text>] [risk=<low|medium|high>] [plan=<path>] [round=N]" >&2
  echo "       phase=final needs no chunk" >&2
  exit 2
}
die() { echo "mark: $1" >&2; exit 2; }
is_key() { case " ${keys[*]} " in *" $1 "*) return 0 ;; esac; return 1; }

[ $# -gt 0 ] || usage
args=()
phase=""; chunk=""; seen=" "
for pair in "$@"; do
  [[ $pair == *=* ]] || die "expected key=value, got '$pair'"
  key=${pair%%=*}
  value=${pair#*=}
  is_key "$key" || die "unknown key '$key'"
  case $seen in *" $key "*) die "repeated key '$key'" ;; esac
  seen+="$key "
  case $key in
    phase) [[ $value =~ ^($phases)$ ]] || die "phase must be one of: ${phases//|/, } (got '$value')"; phase=$value; args+=("phase=$value") ;;
    risk) [[ $value =~ ^(low|medium|high)$ ]] || die "risk must be one of: low, medium, high (got '$value')"; args+=("risk=$value") ;;
    chunk|of|round) [[ $value =~ ^[0-9]+$ ]] || die "$key must be a whole number (got '$value')"; args+=("$key:=$value"); [ "$key" = chunk ] && chunk=$value ;;
    *) args+=("$key=$value") ;;
  esac
done
[ -n "$phase" ] || die "missing phase"
[ -n "$chunk" ] || [ "$phase" = final ] || die "missing chunk"

bash "$here/event.sh" mark mark "${args[@]}" || true
