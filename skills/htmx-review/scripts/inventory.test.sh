#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo shop
mkdir -p web/templates web/static internal/cart node_modules/x
cat > web/templates/layout.gohtml <<'HTML'
<html>
<head>
  <meta name="htmx-config" content='{"defaultSwapStyle":"outerHTML"}'>
  <script src="https://unpkg.com/htmx.org@2.0.11" integrity="sha384-x"></script>
</head>
<body hx-headers='{"X-CSRF-Token": "{{ .CSRF }}"}' hx-ext="response-targets">
  <div id="toast"></div>
  {{ block "content" . }}{{ end }}
</body>
</html>
HTML
cat > web/templates/cart.gohtml <<'HTML'
{{ define "cart" }}
<ul id="items">{{ range .Items }}<li id="item-{{ .ID }}">{{ .Name }}</li>{{ end }}</ul>
<button hx-get="/cart" hx-target="#items" hx-disabled-elt="this">Reload</button>
<button hx-get="/cart" hx-target="#summary">Summary</button>
<button hx-delete="/cart/1" hx-target="#item-7" hx-indicator="#toast" x-data="{}">Delete</button>
<div hx-on::after-request="done()"></div>
{{ end }}
HTML
printf 'package web\n\ntempl Row(item Item) {\n\t<tr hx-target:inherited="#items"></tr>\n}\n' > web/templates/row.templ
echo 'version: "2.0.11",' > web/static/htmx.min.js
echo '<div hx-get="/x">' > node_modules/x/index.html
cat > internal/cart/handler.go <<'GO'
package cart

func Show(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("HX-Request") == "true" {
		w.Header().Set("HX-Push-Url", "/cart")
	}
}
GO
echo 'package cart' > internal/cart/cart_templ.go

out=$(bash "$inventory" .)
htmx=$(under 'htmx')
sees   "the script tag"                 'layout.gohtml:4:https://unpkg.com/htmx.org@2.0.11' "$htmx"
sees   "the vendored file's version"    'web/static/htmx.min.js  version 2.0.11' "$htmx"
sees   "the config meta"                'htmx-config' "$htmx"
sees   "the extension in use"           'hx-ext="response-targets"' "$htmx"
majors=$(under 'which major')
sees   "htmx 2 syntax counted"          'htmx 2 only.* 3$' "$majors"
sees   "htmx 4 syntax counted"          'htmx 4 only.* 1$' "$majors"
kinds=$(under 'templates')
sees   "templates by kind"              '\.gohtml +2' "$kinds"
sees   "the layout"                     'layout +web/templates/layout.gohtml' "$kinds"
partials=$(under 'partials and components')
sees   "a defined template"             'cart +web/templates/cart.gohtml' "$partials"
sees   "a block"                        'content +web/templates/layout.gohtml' "$partials"
sees   "a templ component"              'Row +web/templates/row.templ' "$partials"
sees   "attribute counts"               '3 hx-target$' "$(under 'attributes in use')"
sees   "an inherited attribute by its full name" 'hx-target:inherited' "$(under 'attributes in use')"
missing=$(under 'hx-target ids that no template defines')
sees   "a target with no element"       '#summary +web/templates/cart.gohtml' "$missing"
misses "a target that exists"           '#items|#toast' "$missing"
misses "a target with a generated id"   '#item-7' "$missing"
server=$(under 'server side')
sees   "who reads HX-Request"           'reads HX-Request: internal/cart/handler.go' "$server"
sees   "nobody sets Vary"               'sets Vary there: +none' "$server"
sees   "the response headers in use"    '1 "HX-Push-Url"' "$server"
sees   "no CSRF middleware"             'CSRF defence: none found in Go' "$server"
sees   "the CSRF header"                'CSRF header: web/templates/layout.gohtml' "$server"
sees   "no policy"                      'Content-Security-Policy: none found' "$server"
sees   "Alpine beside htmx"             'Alpine \(x-data\) +1' "$(under 'other client-side code')"
misses "node_modules is not read"       'node_modules' "$out"

echo "# an empty directory"
mkdir -p "$tmp/empty"
out=$(bash "$inventory" "$tmp/empty")
sees   "nothing loaded"                 'none' "$(under 'htmx')"
sees   "no partials"                    'none' "$(under 'partials and components')"
has "not a directory"                   1 'not a directory' bash "$inventory" "$tmp/nope"

finish
