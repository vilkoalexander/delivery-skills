#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

phases='implement|gate|review|fix|verify|cross|report|final'
risks='low|medium|high'
keys=(phase chunk of name risk plan round)

usage() {
  echo "usage: mark.sh phase=<${phases}> chunk=N of=M [name=<text>] [risk=<${risks}>] [plan=<path>] [round=N]" >&2
  echo "       phase=final needs no chunk" >&2
  exit 2
}

die() {
  echo "mark: $1" >&2
  exit 2
}

is_key() {
  [[ " ${keys[*]} " == *" $1 "* ]]
}

[ $# -gt 0 ] || usage

fields=()
phase=""
chunk=""
seen=" "
for pair in "$@"; do
  [[ $pair == *=* ]] || die "expected key=value, got '$pair'"
  key=${pair%%=*}
  value=${pair#*=}
  is_key "$key" || die "unknown key '$key'"
  [[ $seen != *" $key "* ]] || die "repeated key '$key'"
  seen+="$key "

  case $key in
    phase)
      [[ $value =~ ^($phases)$ ]] || die "phase must be one of: ${phases//|/, } (got '$value')"
      phase=$value
      fields+=("phase=$value")
      ;;
    risk)
      [[ $value =~ ^($risks)$ ]] || die "risk must be one of: ${risks//|/, } (got '$value')"
      fields+=("risk=$value")
      ;;
    chunk|of|round)
      [[ $value =~ ^[0-9]+$ ]] || die "$key must be a whole number (got '$value')"
      [ "$key" = chunk ] && chunk=$value
      fields+=("$key:=$value")
      ;;
    *)
      fields+=("$key=$value")
      ;;
  esac
done

[ -n "$phase" ] || die "missing phase"
[ -n "$chunk" ] || [ "$phase" = final ] || die "missing chunk"

bash "$here/event.sh" mark mark "${fields[@]}" || true
