# Sources

References behind `CHECKLIST.md`. Not loaded during a review. Checked
2026-11-25: htmx 2.0.11 (npm `latest`) and htmx 4.0.2 (npm `next`), templ
v0.3.1118.

- [htmx releases](https://github.com/bigskysoftware/htmx/releases) and the [npm dist-tags](https://registry.npmjs.org/htmx.org) — which version is `latest`, which is `next`
- [htmx 4.0.0 is released](https://four.htmx.org/announcements/2026-08-28-htmx-4.0.0-is-released) — htmx 2 supported indefinitely, 4 becomes `latest` in 2027
- [htmx 2 → 4 migration guide](https://four.htmx.org/migration-guide-htmx-4/) and [What's new in htmx 4](https://four.htmx.org/docs/whats-new-in-htmx-4) — the version baseline table: `fetch`, explicit inheritance, swapped 4xx/5xx, the renames, the removed attributes and config, the event names, the request headers
- [htmx 4 — Polling](https://four.htmx.org/patterns/polling) — no status 286; return the element without its trigger
- [htmx 1 → 2 migration guide](https://htmx.org/migration-guide-htmx-1/) — `hx-on`, extensions out of core, `hx-ws` / `hx-sse`, DELETE parameters in the URL
- [htmx 2 documentation — Security](https://htmx.org/docs/#security), [Caching](https://htmx.org/docs/#caching), [htmx 4 documentation](https://four.htmx.org/docs/) — escape everything, `hx-disable` / `hx-ignore`, `allowEval`, `selfRequestsOnly` and `mode`, the history cache, `Vary: HX-Request`, CSRF through `hx-headers`
- [Web security basics (with htmx)](https://htmx.org/essays/web-security-basics-with-htmx/) — only call routes you control, auto-escaping engine, user content only inside tags, cookie attributes
- [hx-swap-oob](https://htmx.org/attributes/hx-swap-oob/), [hx-boost](https://htmx.org/attributes/hx-boost/), [hx-sync](https://htmx.org/attributes/hx-sync/), [hx-disabled-elt](https://htmx.org/attributes/hx-disabled-elt/), [hx-trigger](https://htmx.org/attributes/hx-trigger/) — matching by id, table elements in a `<template>`, redirects under boost, request ordering
- [htmx extensions](https://htmx.org/extensions/) — response-targets, idiomorph, SSE and WebSocket on htmx 2
- [templ — Injection attacks](https://templ.guide/security/injection-attacks), [Rendering raw HTML](https://templ.guide/syntax-and-usage/rendering-raw-html/), [Content security policy](https://templ.guide/security/content-security-policy/) — what templ escapes, what it does not (`js:` values, trigger filters, Alpine and Datastar attributes), `templ.Raw`, `templ.WithNonce`
- [package html/template](https://pkg.go.dev/html/template) — contextual escaping and the typed strings that bypass it
- [net/http CrossOriginProtection](https://pkg.go.dev/net/http#CrossOriginProtection) — checks `Sec-Fetch-Site`, passes every GET; why a state-changing `hx-get` is a merge blocker
- [CVE-2025-47909](https://osv.dev/vulnerability/CVE-2025-47909) — gorilla/csrf
- [donseba/go-htmx](https://github.com/donseba/go-htmx) — a Go helper that knows both majors' headers; angelofallars/htmx-go knows htmx 2 only and was last released in 2024
- [WAI-ARIA Authoring Practices — live regions and focus](https://www.w3.org/WAI/ARIA/apg/practices/) and [WCAG 2.2 — 4.1.3 Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html) — §7
- [Flavio Copes — the AHA stack, updated](https://flaviocopes.com/ahastack-update/) — agents reach for `fetch()` and a JSON endpoint out of habit and know htmx 4 poorly; why §1 and §8 exist

Not confirmed from a primary page, stated in the checklist on reasoning or
practitioner consensus: `html/template` escapes a value inside `hx-on:*` or a
`js:` value as an HTML attribute only, not as JavaScript; templ does not
URL-sanitize `hx-get` / `hx-post` values; whether htmx 4 has an equivalent of
the `htmx:validateUrl` event; that `hx-disable` on htmx 4 takes the same
selector values `hx-disabled-elt` took on 2; the focus and `aria-live` behaviour in §7 comes
from the ARIA practices, not from htmx's documentation. No published list of
agent mistakes in htmx was found: the mixed-version rules are derived from
the two migration guides.
