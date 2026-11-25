#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

new_repo shop
mkdir -p web/templates
cat > web/templates/layout.gohtml <<'HTML'
<html>
<head>
  <script src="https://unpkg.com/htmx.org@2.0.11"></script>
  <script src="https://unpkg.com/htmx.org"></script>
</head>
<body hx-boost="true">{{ template "content" . }}</body>
</html>
HTML

echo "# an htmx 2 template"
cat > web/templates/cart.gohtml <<'HTML'
{{ define "content" }}
<div hx-get="/cart/items" hx-target="#items">Show</div>
<div hx-get="/cart/total" hx-trigger="load">…</div>
<a href="/cart" hx-post="/cart/clear">Clear</a>
<button hx-get="/cart/delete/{{ .ID }}">Remove</button>
<button hx-delete="/cart/{{ .ID }}"
        hx-target="#items">Delete</button>
<form hx-post="/cart" hx-target="#items">
  <input name="q" hx-get="/search" hx-trigger="keyup changed">
</form>
<form hx-post="/orders" hx-disabled-elt="find button"><button>Pay</button></form>
<div hx-swap-oob="true">count</div>
<div id="count" hx-swap-oob="true">count</div>
<span hx-get="/status" hx-trigger="every 2s">…</span>
<button hx-on:click="track('{{ .Name }}')">Track</button>
<button hx-post="/a" hx-sync="this:drop" hx-vals='js:{n: 1}'>A</button>
<p>{{ .Note | safeHTML }}</p>
<div hx-target:inherited="#items" hx-on="click: go()"></div>
<div hx-get="https://other.example/x" hx-trigger="load"></div>
<script>document.body.addEventListener('htmx:after:swap', init)</script>
<button hx-post="/b" hx-optimistic="true" hx-sync="this">B</button>
<button hx-get="/more" hx-swap="outerMorph">More</button>
{{ if gt .Count 1 }}<b>many</b>{{ end }}
{{ end }}
HTML
out=$(bash "$scan" web/templates/cart.gohtml)
sees  "the version and where it came from"     '^htmx: 2 \(from a script tag' "$out"
flags "hx-on=\"…\""
flags "hx-optimistic"
flags "Escaping bypass in a template"
flags "Template value inside an attribute htmx evaluates as JavaScript"
flags "Attribute evaluated as JavaScript"
flags "Inline <script>"
flags "Request to another origin"
flags "Request on an element that is not interactive"
passive=$(under 'Request on an element that is not interactive')
sees   "the clickable div"                     'hx-get="/cart/items"' "$passive"
misses "a load trigger is not a click"         '/cart/total' "$passive"
misses "a button is interactive"               '/cart/delete' "$passive"
flags "Link that sends a write"
flags "hx-get to a URL named like an action"
flags "hx-delete with no hx-confirm"
sees  "a tag that wraps is read whole"         '^6:<button hx-delete.*hx-target="#items">' "$(under 'hx-delete with no hx-confirm')"
flags "Write with nothing that stops a second submit"
double=$(under 'Write with nothing that stops a second submit')
sees   "the bare form"                         'hx-post="/cart"' "$double"
misses "the form that disables its button"     '/orders' "$double"
flags "Request per keystroke"
flags "Input-driven request with no hx-sync"
flags "Polling"
flags "hx-swap-oob with no id"
eq    "only the element without an id"         "$(under 'hx-swap-oob with no id' | wc -l | tr -d ' ')" 1
flags "htmx 4 syntax in an htmx 2 project"
flags "htmx 4 event name"
flags "innerMorph / outerMorph"
unflags "Attribute removed or renamed in htmx 4"
unflags "htmx 2 event name"

out=$(bash "$scan" web/templates/layout.gohtml)
flags "htmx loaded with no pinned version"
eq    "only the unpinned tag"                  "$(under 'htmx loaded with no pinned version' | wc -l | tr -d ' ')" 1
flags "htmx loaded from a CDN with no integrity attribute"
flags "hx-boost"

echo "# the same project on htmx 4"
cat > web/templates/list.templ <<'HTML'
package web

templ List(items []Item) {
	<div hx-target="#items" hx-swap="outerHTML">
		<button hx-get="/items" hx-disabled-elt="this">Reload</button>
	</div>
	<div hx-target:inherited="#items"><button hx-get="/items">Reload</button></div>
	<div hx-disable>@templ.Raw(items[0].Note)</div>
	<div hx-ext="sse" sse-connect="/events" hx-on::after-request="done()"></div>
	<body hx-on:htmx:afterSwap="init()"></body>
	<input hx-get="/search" hx-trigger="input delay:300ms, queue:last" hx-sync="this:replace"/>
	<button hx-post="/a" hx-disable="this" hx-status:422="target:#errors">A</button>
	<button hx-get={ "/orders/" + id + "/cancel" }>Cancel</button>
}
HTML
out=$(HTMX_VERSION=4 bash "$scan" web/templates/list.templ)
sees  "the override is named"                  '^htmx: 4 \(from HTMX_VERSION\)' "$out"
flags "hx-disable with no value"
flags "Attribute removed or renamed in htmx 4"
flags "sse-\* / ws-\* attributes"
flags "htmx 2 event name"
events=$(under 'htmx 2 event name')
sees   "a camelCase event"                     'afterSwap' "$events"
sees   "a kebab-case hx-on"                    'after-request' "$events"
flags "hx-get to a URL named like an action"
flags "queue: in hx-trigger"
flags "Attribute on a container with no :inherited"
inherited=$(under 'Attribute on a container with no :inherited')
sees   "the container"                         '^4:<div hx-target="#items"' "$inherited"
misses "the one that says inherited"           'hx-target:inherited' "$inherited"
flags "Escaping bypass in a template"
unflags "htmx 4 syntax in an htmx 2 project"
unflags "Write with nothing that stops a second submit"

echo "# a clean fragment, no version anywhere"
rm web/templates/layout.gohtml web/templates/cart.gohtml web/templates/list.templ
cat > web/templates/row.gohtml <<'HTML'
<tr id="item-{{ .ID }}">
  <td>{{ .Name }}</td>
  <td><button hx-delete="/items/{{ .ID }}" hx-confirm="Delete {{ .Name }}?" hx-target="closest tr" hx-swap="outerHTML" hx-sync="this:drop">Delete</button></td>
</tr>
HTML
out=$(bash "$scan" web/templates/row.gohtml)
sees  "the version is asked for"               '^htmx: version not found — set HTMX_VERSION' "$out"
sees  "nothing to flag"                        '^clean — no mechanical smells$' "$out"
echo '{"dependencies":{"htmx.org":"^4.0.2"}}' > package.json
has "the version from package.json"            0 '^htmx: 4 \(from package.json\)' bash "$scan" web/templates/row.gohtml

echo "# usage"
has "no argument"                              1 'usage: scan.sh' bash "$scan"
has "a missing file"                           1 'not found: nope.html' bash "$scan" nope.html

finish
