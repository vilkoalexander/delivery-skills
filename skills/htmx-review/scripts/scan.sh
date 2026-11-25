#!/usr/bin/env bash
# Mechanical pre-scan for htmx-review. Catches the deterministic smells so
# the review spends judgement on the rest. Heuristic — flags, not a verdict.
#
# No compiler reads an hx- attribute: a misspelled one, one from another htmx
# major, or one that evaluates a template value as JavaScript renders without
# an error and fails in the browser.
#
# Usage: scan.sh <template: .html .gohtml .tmpl .templ>
# Env:   HTMX_VERSION  2 or 4, when detection from the repository is wrong
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <template>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || dirname "$file")

# Prints "MAJOR<TAB>where it was read from", or nothing.
detect_version() {
  local hit
  if [ -n "${HTMX_VERSION:-}" ]; then
    printf '%s\tHTMX_VERSION\n' "$HTMX_VERSION"
    return
  fi
  hit=$(grep -rhoE --include='*.html' --include='*.gohtml' --include='*.tmpl' --include='*.templ' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor 'htmx\.org@[0-9]+' "$root" 2>/dev/null | sort -u | head -1)
  if [ -n "$hit" ]; then
    printf '%s\ta script tag (%s)\n' "${hit#htmx.org@}" "$hit"
    return
  fi
  hit=$(grep -rhoE --include='package.json' --exclude-dir=node_modules '"htmx\.org": *"[^0-9]*[0-9]+' "$root" 2>/dev/null | head -1)
  if [ -n "$hit" ]; then
    printf '%s\tpackage.json\n' "$(printf '%s' "$hit" | grep -oE '[0-9]+$')"
    return
  fi
  hit=$(find "$root" -name 'htmx*.js' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -1)
  if [ -n "$hit" ]; then
    local version
    version=$(grep -oE 'version: ?["'"'"'][0-9]+' "$hit" 2>/dev/null | grep -oE '[0-9]+$' | head -1)
    [ -n "$version" ] && printf '%s\t%s\n' "$version" "${hit#"$root"/}"
  fi
}

detected=$(detect_version)
major=${detected%%$'\t'*}
case "$major" in
  2|4) echo "htmx: $major (from ${detected#*$'\t'})" ;;
  1)   echo "htmx: 1 (from ${detected#*$'\t'}) — end of life; the version rules below assume 2" ; major=2 ;;
  *)   echo "htmx: version not found — set HTMX_VERSION=2 or 4; only the rules common to both ran"; major="" ;;
esac
echo

found_any=0

# flag LABEL LINES — prints a finding with the lines that caused it
flag() {
  printf '## %s\n%s\n\n' "$1" "$2"
  found_any=1
}

# report LABEL REGEX — flags every line of the file that matches
report() {
  local matches
  matches=$(grep -nE -- "$2" "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

# Every opening tag on one line, as "LINE:<tag …>". A ">" inside a quoted
# value or a {{ }} / { } expression does not end the tag.
tags=$(awk '
  {
    line = $0
    n = length(line)
    for (i = 1; i <= n; i++) {
      c = substr(line, i, 1)
      if (!in_tag) {
        if (c == "<" && substr(line, i + 1, 1) ~ /[A-Za-z]/) { in_tag = 1; tag = ""; start = NR; quote = ""; depth = 0 }
        else continue
      }
      tag = tag c
      if (quote != "") { if (c == quote) quote = ""; continue }
      if (c == "\"" || c == "\x27") { quote = c; continue }
      if (c == "{") depth++
      else if (c == "}" && depth > 0) depth--
      else if (c == ">" && depth == 0) { printf "%d:%s\n", start, tag; in_tag = 0 }
    }
    if (in_tag) tag = tag " "
  }
' "$file" | sed -E 's/[[:space:]]+/ /g')

# tags_where LABEL HAS [LACKS] — flags every tag that matches HAS and not LACKS
tags_where() {
  local matches
  matches=$(printf '%s\n' "$tags" | grep -E -- "$2")
  [ -n "${3:-}" ] && matches=$(printf '%s\n' "$matches" | grep -vE -- "$3")
  [ -n "$matches" ] && flag "$1" "$matches"
}

verb='hx-(get|post|put|patch|delete)='
mutating='hx-(post|put|patch|delete)='
interactive='^[0-9]+:<(a|button|form|input|select|textarea|details|summary|body|html)[ >/]'
passive_trigger='hx-trigger=["{`'"'"'][^"]*(load|revealed|intersect|every |sse:|from:)'

# --- attributes that are not htmx ----------------------------------------------
report "hx-on=\"…\" — the htmx 1 form; htmx 2 and 4 take hx-on:<event>" 'hx-on="'
report "hx-ws / hx-sse as plain attributes — htmx 1; they are extensions since 2" '(^|[[:space:]])hx-(ws|sse)="'
report "hx-optimistic — not an attribute of htmx 2 or 4" 'hx-optimistic'

# --- loading htmx ----------------------------------------------------------------
tags_where "htmx loaded with no pinned version — a new major changes behaviour without a commit" \
  '<script[^>]*htmx\.org(@latest|@next|/dist|"|/[a-z])' 'htmx\.org@[0-9]+\.[0-9]+\.[0-9]+'
tags_where "htmx loaded from a CDN with no integrity attribute" \
  '<script[^>]*src="https?://[^"]*htmx' 'integrity='

# --- escaping and evaluated attributes -------------------------------------------
report "Escaping bypass in a template — prove the value never holds user input" \
  '\|[[:space:]]*(safeHTML|safeJS|safeURL|safeAttr|safeCSS|noescape|unescape|raw)\b|@?templ\.(Raw|SafeURL|SafeCSS|SafeScript)\(|template\.(HTML|JS|URL|HTMLAttr)\('
tags_where "Template value inside an attribute htmx evaluates as JavaScript — HTML escaping does not make it safe there" \
  '(hx-on[:-][^=]*=|hx-(vals|headers)=.(js|javascript):|hx-vars=|hx-trigger=[^ ]*\[)[^>]*(\{\{|\{ )'
tags_where "Attribute evaluated as JavaScript (hx-on, js: values, a trigger filter) — it needs 'unsafe-eval' in the CSP; confirm the project layer allows it" \
  'hx-on[:-]|hx-(vals|headers)=.(js|javascript):|hx-vars=|hx-trigger="[^"]*\['
report "Inline <script> in a template — it runs again on every swap that brings it in, and a strict CSP needs a nonce on it" \
  '<script>|<script type="text/javascript">'
tags_where "Request to another origin — blocked by default; if it is allowed on purpose, the response is trusted as HTML" \
  "$verb"'"(https?:)?//'

# --- semantics and accessibility ---------------------------------------------------
tags_where "Request on an element that is not interactive — no keyboard access, no role; use a button or a link" \
  "$verb" "$interactive|$passive_trigger|role=|tabindex="
tags_where "Link that sends a write — a link is a navigation to assistive technology and to middle-click; use a button" \
  '^[0-9]+:<a [^>]*'"$mutating"
tags_where "hx-get to a URL named like an action — a GET must not change state: CSRF defences and prefetch let it through" \
  'hx-get=["{][^>]*/(delete|remove|destroy|logout|approve|reject|cancel|toggle|create|update|archive|restore|mark|send|pay)([/?" -]|$)'
tags_where "hx-delete with no hx-confirm — confirm the action can be undone or is confirmed elsewhere" \
  'hx-delete=' 'hx-confirm'

# --- requests that race ---------------------------------------------------------------
tags_where "Write with nothing that stops a second submit — add hx-disabled-elt (htmx 2), hx-disable (htmx 4) or hx-sync" \
  '^[0-9]+:<(form|button)[^>]*'"$mutating" 'hx-disabled-elt|hx-disable=|hx-sync'
tags_where "Request per keystroke — add delay:<time> to the trigger" \
  'hx-trigger="[^"]*(keyup|keydown|input)' 'delay:|throttle:'
tags_where "Input-driven request with no hx-sync — a slow early response overwrites a later one" \
  'hx-trigger="[^"]*(keyup|input|change|search)' 'hx-sync'
tags_where "Polling — name what stops it and what it costs with every tab open" \
  'hx-trigger="[^"]*every [0-9]'

# --- swaps -------------------------------------------------------------------------------
tags_where "hx-swap-oob with no id — an out-of-band element is matched by id" \
  'hx-swap-oob=' ' id=|hx-swap-oob="[^"]*:'
tags_where "hx-boost — every link and form below it becomes a body swap; scripts in <head> and third-party widgets do not re-run" \
  'hx-boost="true"'

# --- the other major -------------------------------------------------------------------
if [ "$major" = 4 ]; then
  tags_where "hx-disable with no value — in htmx 4 it disables elements during a request; hx-ignore is what stops htmx processing user content" \
    ' hx-disable( |>|/)'
  report "Attribute removed or renamed in htmx 4 (hx-disabled-elt → hx-disable, hx-request → hx-config, hx-ext → the extensions config, hx-vars / hx-params / hx-disinherit / hx-inherit / hx-history gone, hx-prompt is an extension)" \
    'hx-(disabled-elt|request|ext|vars|params|disinherit|inherit|history|prompt)='
  report "sse-* / ws-* attributes — htmx 4 takes hx-sse:* and hx-ws:*" '(^|[[:space:]])(sse|ws)-(connect|swap|send|close)='
  report "htmx 2 event name — htmx 4 names events with colons (htmx:after:swap, htmx:config:request)" \
    'htmx:[a-z]+[A-Z][A-Za-z]*|hx-on::?[a-z]+-[a-z]+(-[a-z]+)*='
  report "queue: in hx-trigger — removed in htmx 4; use hx-sync" 'hx-trigger="[^"]*queue:'
  tags_where "Attribute on a container with no :inherited — htmx 4 does not pass it down to the children" \
    '^[0-9]+:<(html|body|main|section|article|div|nav|ul|ol|table|tbody|header|footer|aside)[^>]* hx-(target|swap|headers|include|indicator|confirm|boost|select|sync|vals)=' \
    "$verb|hx-action="
elif [ "$major" = 2 ]; then
  report "htmx 4 syntax in an htmx 2 project (:inherited, hx-ignore, hx-status:, hx-action, hx-method, hx-config, hx-sse: / hx-ws:) — htmx 2 ignores it" \
    'hx-[a-z-]+:inherited|hx-ignore|hx-status:|hx-(action|method|config)=|hx-(sse|ws):'
  report "htmx 4 event name — htmx 2 names events in camelCase (htmx:afterSwap) and kebab-case in hx-on" \
    'htmx:[a-z]+:[a-z]+|hx-on::[a-z]+:[a-z]+'
  report "innerMorph / outerMorph — built into htmx 4; htmx 2 needs the idiomorph extension and hx-swap=\"morph\"" \
    'hx-swap="(inner|outer)Morph'
else
  both=$(grep -cE 'hx-disabled-elt|hx-ext=|htmx:[a-z]+[A-Z]' "$file")
  other=$(grep -cE ':inherited|hx-ignore|hx-status:|htmx:[a-z]+:[a-z]+' "$file")
  if [ "$both" -gt 0 ] && [ "$other" -gt 0 ]; then
    flag "htmx 2 and htmx 4 syntax in one file" "  $both line(s) of htmx 2 syntax, $other of htmx 4"
  fi
fi

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
