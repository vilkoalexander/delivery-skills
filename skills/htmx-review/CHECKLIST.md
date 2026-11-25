# htmx Review Checklist

Nine categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). Name the
consequence: "this is wrong" without "the user clicks and nothing happens" is
not a finding.

This rubric covers the template. The handler that serves it is
`go-service-review`, whose §5 holds the server half of the same contract.

## Before you start

### Version baseline

Read the htmx major the project loads before applying any rule:

```bash
grep -rhoE 'htmx\.org@[0-9.]+|"htmx\.org": *"[^"]+"' --include='*.html' --include='*.gohtml' --include='*.tmpl' --include='*.templ' --include=package.json --exclude-dir=node_modules . | sort -u
```

As of November 2026 both majors are current: 2.0.11 is npm `latest` and what
htmx.org documents; 4.0.2 is stable under the `next` tag with its
documentation at four.htmx.org, and becomes `latest` during 2027. htmx 2 stays
supported. There is no htmx 3.

| | htmx 2 | htmx 4 |
| --- | --- | --- |
| Transport | `XMLHttpRequest` | `fetch()` |
| Inheritance | An attribute on a parent applies to its children | Only with `:inherited` — `hx-target:inherited="#x"` |
| A 4xx or 5xx response | Not swapped; needs `responseHandling` or the response-targets extension | Swapped; `hx-status:422="target:#errors"` |
| Request timeout | none | 60 s |
| Stop htmx processing a subtree | `hx-disable` | `hx-ignore` |
| Disable elements during a request | `hx-disabled-elt` | `hx-disable` |
| Event names | `htmx:afterSwap`, `hx-on::after-request` | `htmx:after:swap`, `hx-on::after:request` |
| Extensions | `hx-ext` on an element | Loaded by script tag, allowed in `htmx-config` |
| SSE, WebSocket | Extensions: `sse-connect`, `ws-connect` | Bundled extensions: `hx-sse:connect`, `hx-ws:connect` |
| Morph swap | idiomorph extension, `hx-swap="morph"` | `innerMorph`, `outerMorph` built in |
| History | Snapshot in `localStorage` | Refetches the page; nothing stored |
| Back / restore request | `HX-History-Restore-Request` | `HX-Request-Type: full` |
| Stop polling | Status 286 | Return the element without its `hx-trigger` |
| Request headers | `HX-Trigger`, `HX-Trigger-Name`, `HX-Target` (an id) | `HX-Source`, `HX-Target` as `tag#id` |
| Gone | — | `hx-vars`, `hx-params`, `hx-disinherit`, `hx-inherit`, `hx-history`, `hx-request` (now `hx-config`), `queue:` in `hx-trigger`; `hx-prompt` is an extension |
| Config that guards | `selfRequestsOnly`, `allowEval`, `allowScriptTags` | `mode: 'same-origin'`; no `allowEval` — the Content-Security-Policy decides |

Same in both: `hx-get` / `hx-post` / `hx-put` / `hx-patch` / `hx-delete`,
`hx-target`, `hx-swap`, `hx-trigger`, `hx-swap-oob`, `hx-select`,
`hx-include`, `hx-vals`, `hx-headers`, `hx-confirm`, `hx-indicator`,
`hx-sync`, `hx-push-url`, `hx-boost`, `hx-on:<event>`; a 204 swaps nothing;
`hx-delete` sends its parameters in the query string; the response headers
`HX-Redirect`, `HX-Location`, `HX-Push-Url`, `HX-Replace-Url`, `HX-Refresh`,
`HX-Retarget`, `HX-Reswap`, `HX-Reselect`, `HX-Trigger`. `<hx-partial>` is in
4 and in 2.0.11.

Never valid in either: `hx-on="event: code"`, `hx-ws="…"`, `hx-sse="…"`
(htmx 1), and `hx-optimistic`.

### Tooling coverage

Nothing in a Go build reads an `hx-` attribute. What the build does catch:

| Runs in the build | Do not hand-report |
| --- | --- |
| `templ generate` | A `.templ` file that does not parse, a component called with the wrong arguments, an expression in an `on*` or `hx-on` attribute that is not a script component |
| `html/template` parse at start-up, with a test that renders the template | A syntax error, an undefined template name |
| `npx htmx.org@4 upgrade-check`, when the project runs it | Attributes renamed or removed between 2 and 4 |
| An HTML linter or axe in an end-to-end test | The generic accessibility rules it is configured for |

The rest is this review's job, and `scripts/scan.sh` covers the mechanical
part: syntax of the wrong major, an evaluated attribute, a target that
matches nothing, a write that can be sent twice.

## Severity floor

Always 🔴, regardless of effort:

- user-controlled text emitted without escaping: `template.HTML` and its
  siblings, a `safeHTML`-style function, `templ.Raw`, `text/template`
- a template value inside an attribute htmx evaluates as JavaScript —
  `hx-on:*`, a `js:` value, a trigger filter
- a container of user-authored HTML with nothing that stops htmx processing
  it, or with the other major's attribute for that
- `hx-get` on a URL that changes state
- an attribute that has a different meaning, or none, in the project's htmx
  major and that the feature depends on
- a clickable `<div>` / `<span>` / `<tr>` with a request on it and no role,
  keyboard handler and focusability

A **[hard]** rule that is not on this list is 🟡, unless what it breaks in
this file is one of the lines above.

## 1. Version and generation

- **[hard] Every attribute, event name and config key exists in the
  project's major** — see the baseline. Markup for the other major does
  nothing and raises no error.
- **[hard] `hx-disable` means what this major says.** It is the one name
  with opposite meanings: a guard around user content in 2, "disable this
  element during the request" in 4. Always 🔴 when it guards user content on
  htmx 4.
- **[hard] On htmx 4, an attribute meant for the children says
  `:inherited`.** `hx-target`, `hx-swap`, `hx-headers`, `hx-include`,
  `hx-indicator`, `hx-confirm`, `hx-boost`, `hx-sync` on a container with no
  request of its own apply to nothing. The CSRF header on `<body>` is the one
  that hurts: every write is then sent without it.
- **[hard] Error handling matches how this major treats a 4xx.** On htmx 2 a
  422 with the form in it is not swapped by default. On htmx 4 it is, into
  the normal target — an error page from a proxy included.
- **[hard] htmx is loaded once, at a pinned version, from the layout.**
  `@latest`, `@next`, or no version moves the project to another major
  without a commit. From a CDN it carries `integrity`. A fragment never
  loads it.
- **[hard] Extensions match the major and are loaded.** `hx-ext="sse"` with
  no extension script on htmx 2, or any `hx-ext` on htmx 4, is dead markup.
- **[context] A file moved to htmx 4 syntax ahead of the project**, or left
  behind: follow the project layer's upgrade rule.

## 2. Escaping and evaluated attributes — merge blocker

htmx turns HTML into behaviour. Markup an attacker can write is code.

- **[hard] All user content is escaped by the template engine.**
  `html/template` and templ do it by context. `template.HTML`,
  `template.HTMLAttr`, `template.JS`, `template.URL`, a `safeHTML`-style
  template function and `templ.Raw` turn it off for that value: each use
  needs a value the server made. Always 🔴 with user text.
- **[hard] No template value inside an attribute htmx evaluates.**
  `hx-on:*`, `hx-vals` / `hx-headers` with `js:` or `javascript:`, a filter
  in `hx-trigger="click[…]"`, and `hx-vars` run as JavaScript. The engine
  escaped the value for an HTML attribute, not for a script. Pass data
  through plain JSON `hx-vals`, a `data-` attribute, or a form field. Always
  🔴.
- **[hard] User-authored HTML sits under the guard of this major** —
  `hx-disable` on htmx 2, `hx-ignore` on htmx 4 — and is sanitized of `hx-`,
  `data-hx-` and `on*` attributes and `<script>` before it is stored or
  rendered. A child cannot switch the guard off.
- **[hard] A URL attribute built from data goes through the engine's URL
  handling**: `templ.URL` (templ does it for `href`, `src`, `action`),
  `html/template`'s own filter. `templ.SafeURL` and `template.URL` skip it.
  An `hx-get` built from user input is checked the same way; an engine may
  not treat it as a URL.
- **[hard] Evaluated attributes fit the Content-Security-Policy.** They need
  `'unsafe-eval'`. On a project whose policy forbids it they do nothing; on
  one with no policy, say once that htmx 4 has no `allowEval` switch and the
  policy is the only control.
- **[hard] An inline `<script>` in a fragment carries the nonce** when the
  policy is strict, and is safe to run again: it runs on every swap that
  brings it in.
- **[hard] Requests go to the application's own origin.** A cross-origin
  `hx-get` is blocked by default in both majors; switching that off makes the
  other origin's response trusted HTML.
- **[hard] A write carries the project's CSRF defence** — a header from
  `hx-headers` on `<body>` (`hx-headers:inherited` on 4), or
  `http.CrossOriginProtection` on the server, which needs no token.
- **[context] A page with secrets on htmx 2** is kept out of the
  `localStorage` history snapshot with `hx-history="false"`.

## 3. The request

- **[hard] The verb says what happens.** `hx-get` reads. A GET that deletes,
  logs out, approves or toggles passes every CSRF defence and is fired by a
  prefetch. Always 🔴.
- **[hard] The request is on an element built for it** — `<button>` for an
  action, `<a href>` for navigation, `<form>` for input, `<input>` /
  `<select>` for a filter. See §7 for a `<div>`.
- **[hard] A link stays a link.** `<a hx-post>` is an action dressed as
  navigation: middle-click and "open in new tab" do the wrong thing. An
  `<a hx-get>` keeps a real `href`.
- **[prefer] A form keeps `action` and `method`**, and a boosted link its
  `href`, so the page works before the script loads and when it fails. The
  project layer may waive this for an application behind a login.
- **[hard] The values the handler reads are sent.** A button outside its
  form needs `hx-include`. On htmx 4 `hx-delete` no longer includes the
  enclosing form. `hx-delete` values arrive in the query string.
- **[hard] `hx-vals` is JSON with double-quoted keys**, in a single-quoted
  attribute. A value from the template goes through the engine's JSON
  encoding, not string concatenation.
- **[hard] `hx-trigger` matches the intent.** A text input uses
  `input changed delay:300ms` (or `keyup`), not a request per keystroke.
  `load` and `revealed` fire again when the element is swapped back in: a
  fragment that contains its own `hx-trigger="load"` is a loop.
- **[hard] Polling stops.** Name the condition and how the server signals it
  in this major. `every 1s` on a list page, in every open tab, is the load
  test nobody ran.
- **[prefer] `hx-push-url` on a request that changes what the page is** —
  a tab, a filter, a detail view — so reload and Back return to it. Then the
  URL must answer a full page on a plain GET.
- **[context] `hx-boost`** turns every link and form below it into a body
  swap. Scripts in `<head>` do not re-run, a third-party widget is not
  re-initialised, and a link to a file download needs `hx-boost="false"`.

## 4. The swap

- **[hard] `hx-target` names an element that exists when the response
  arrives.** `scripts/inventory.sh` lists static targets with no matching
  id. A target inside the element being replaced is gone after the first
  swap.
- **[hard] The response and the swap style fit each other.** `outerHTML`
  needs a response whose root is the replacement for the target, with the
  same id and the same `hx-` attributes, or the second click does nothing.
  `innerHTML` needs the content without the wrapper, or the wrapper nests.
- **[hard] Ids are unique and stable.** A list row has an id built from its
  key, not from its position. Morph swaps, out-of-band swaps and focus
  restoration all match by id.
- **[hard] An out-of-band element has an id that exists in the page**, and
  is a top-level element of the response. A `<tr>`, `<td>` or `<li>` on its
  own is dropped by the HTML parser: wrap it in `<template>`. On htmx 4 a
  response that is only out-of-band content skips the main swap.
- **[hard] A table fragment is valid inside a table.** A `<tr>` response
  targets a `<tbody>` or a `<tr>`, never a `<div>`.
- **[prefer] One swap per interaction.** More than two out-of-band
  fragments for one click means the target is too small: swap the common
  parent, or send an `HX-Trigger` event the other regions listen for.
- **[context] `hx-select` on a large response** downloads the whole page to
  keep one node. A fragment endpoint is the fix when the page is expensive.
- **[context] Swapping the `<body>` or a large region** drops focus, scroll
  position and the state of open widgets inside it. Morph, or a smaller
  target.
- **[context] A swap that removes an element with a request in flight**
  from inside it: the response has nowhere to go.

## 5. The server half

Read the handler behind each URL the template requests. The rules are in
`go-service-review` §5; check them from this side:

- **[hard] The handler returns HTML shaped for this target**, not JSON and
  not the whole page.
- **[hard] A URL that answers a page or a fragment sets `Vary:
  HX-Request`**, and gives a full page to a history restore.
- **[hard] The failure path renders something the user sees.** Validation
  errors come back in the form, with the status this major swaps, and the
  values the user typed still in the fields.
- **[hard] A redirect after a write is an `HX-Redirect` or `HX-Location`
  header**, unless the request was boosted.
- **[hard] The fragment is rendered by the same template the full page
  uses.** A second copy of the markup for the fragment endpoint drifts.
- **[context] An expired session during an htmx request** answers a login
  page into a table cell. The server answers 401 with `HX-Redirect`, or the
  layout handles the status.

## 6. Races, loading and errors

- **[hard] A write cannot be sent twice.** The submit control is disabled
  for the request — `hx-disabled-elt` on 2, `hx-disable` on 4 — or the
  element has `hx-sync="this:drop"`.
- **[hard] Requests that update one region are ordered.** Search-as-you-type
  and dependent selects need `hx-sync` (`this:replace`, or
  `closest form:abort`): without it a slow early response overwrites a later
  one.
- **[hard] Something shows that a request is running** when it can take
  longer than a moment: `hx-indicator`, or the `htmx-request` class in CSS.
- **[hard] A network failure and a 5xx are visible.** On htmx 2 neither
  swaps anything: without a handler for `htmx:responseError` and
  `htmx:sendError`, or the response-targets extension, the user clicks and
  nothing happens. On htmx 4 a 5xx body is swapped into the target: the
  server's error page must be a fragment that fits there.
- **[context] A destructive action** has `hx-confirm`, or an undo.
- **[context] Optimistic UI written by hand** in `hx-on` must put the old
  state back on failure. Without that, do not fake it.
- **[context] On htmx 4 the default timeout is 60 s.** A request that
  legitimately runs longer — an export, a slow report — is cut; on htmx 2 it
  never times out. Either way a long job belongs in the background with a
  polled status.

## 7. Accessibility

A swap is silent to a screen reader and can drop keyboard focus.

- **[hard] No request on a non-interactive element** without `role`,
  `tabindex="0"` and a key handler. Use a `<button>`. Always 🔴 for a click
  trigger; `load`, `revealed` and `intersect` triggers are not clicks.
- **[hard] Focus survives the swap.** When the focused element is replaced,
  the replacement has the same id, or the response moves focus on purpose.
  Replacing a form after a failed submit must not send focus to the top of
  the page.
- **[hard] A region updated without a navigation is announced** —
  `aria-live="polite"` on the container, `role="alert"` for an error — or
  focus moves to it.
- **[hard] A validation message is tied to its field** with
  `aria-describedby` and `aria-invalid`, not only coloured.
- **[prefer] The busy state is exposed**: `aria-busy="true"` on the target
  during the request, and a disabled control is really `disabled`.
- **[prefer] A boosted or pushed navigation updates `<title>`** and moves
  focus to the main heading or landmark.
- **[context] An indicator that is only a spinner image** needs a text
  alternative.

## 8. Over-engineering and reuse

The bias in generated htmx is toward the SPA it was trained on.

- **[hard] No JSON round trip where a swap would do.** `fetch()` and a JSON
  endpoint, with the DOM built in a script, is a second rendering path next
  to the templates. The handler returns the fragment.
- **[hard] Reinvention** — a row, a form field, an error block, a
  pagination control, a flash message that a partial or a component already
  renders. **Run `scripts/inventory.sh` before judging this.** Name the
  replacement by its real template name and file.
- **[hard] State lives on the server.** A hidden input, a `data-` attribute
  or an Alpine store that mirrors what the server already knows goes stale
  after the next swap.
- **[prefer] Client-side code is for what never leaves the browser** — a
  menu, a toggle, a focus trap. Alpine or a few lines in `hx-on` for that
  are fine where the project layer allows them; a second framework for it is
  not.
- **[prefer] `hx-on` holds one statement.** More than that is a function in
  a script file, called from the attribute or bound to an event.
- **[prefer] Page-wide attributes sit on the layout once** — the CSRF
  header, the default indicator — not on every form.
- **[context] A fragment endpoint per tiny region.** Ten endpoints that each
  render one `<span>` of one page are one endpoint and one target.
- **[context] A partial with parameters nobody passes**, or extracted for
  one caller. Generalize on the second use.

## 9. Comment quality

<!-- comment-rules:start — the short form of comment-cleanup/RULES.md, the same text in each checklist -->
The default is no comment; a rename, an extracted function or a type comes
first.

- **[hard] Delete comments that restate the code or describe the change** —
  "now uses", "added", "fixed", a banner, a step number, a doc comment that
  repeats the signature or the types.
- **[hard] Delete commented-out code** — git remembers it.
- **[hard] No ticket, PR, SHA, date or link in a comment** — the code does
  not know the outside world; those live in commit messages and PR bodies.
- **[prefer] A comment that stays is one line and one of four kinds** — why
  this and not the obvious alternative, an outside constraint, a warning
  about what breaks if edited, a workaround with its removal condition. On a
  constant or a field: only units, where a number comes from, a domain term,
  or what null means, and only when a rename cannot say it.
- **[context] A missing comment** is a finding only for one of those four
  kinds, with the consequence named.
- **[context] A comment the diff removed** that was still true and one of the
  four kinds — restore it.
- **[hard] A lint, type or check suppression states its reason.**
<!-- comment-rules:end -->

In this stack:

- `<!-- … -->` is sent to every browser. A comment for the next developer is
  a template comment — `{{/* … */}}`, or `//` in a `.templ` file. An HTML
  comment that names an internal route, a ticket or a person is a finding
  beyond comment quality.
- A restated line reads like `<!-- cart items -->` above `<ul id="cart-items">`.
- A deliberate escaping bypass, a request that must not be boosted, and a
  target that is replaced by an out-of-band swap from another endpoint each
  need a comment of one of the four kinds.

---

## Do NOT report

- Anything the build already fails on (see Tooling coverage).
- Restating the project's instructions file as if it were a finding.
- A violation in markup the change did not touch.
- A migration: htmx 2 to 4 or back, `html/template` to templ, htmx to
  Datastar or Alpine AJAX, or a client framework. The project's major and
  engine are its own choice; htmx 2 is supported.
- htmx 2 syntax in an htmx 2 project as "outdated".
- Styling, class names and layout taste.
- Generic HTML accessibility unrelated to a swap or a request — that is an
  accessibility audit, not this rubric.
- Features and ceilings the project layer lists as deferred or known.
- A speculative failure. If the finding needs "might" or "could, if", find the
  line that makes it real or drop it.
