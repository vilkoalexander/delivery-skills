# htmx review — project layer

Loaded by `htmx-review` at step 2. Also the source for the scan env:
`HTMX_VERSION=<2|4>`. Keep every entry a real path or template name.

## htmx

htmx `<2.0.11 | 4.0.2>`, loaded from `<web/templates/layout.gohtml: a vendored file | a CDN with integrity>`.
Upgrade: `<staying on 2 | moving to 4: new files use 4 syntax behind htmx-2-compat, existing files stay until touched>`.
Extensions: `<response-targets, idiomorph | none>`.
`htmx-config`: `<the keys the layout sets, and why>`.

Template engine: `<html/template | templ>`. Other client-side code: `<Alpine for menus and dialogs | none>`.

## Security

- Content-Security-Policy: `<set in middleware, no 'unsafe-eval': hx-on and js: values do not run | none>`. Nonce: `<templ.WithNonce | none>`.
- CSRF: `<http.CrossOriginProtection, no token | hx-headers on <body> with X-CSRF-Token>`.
- User-authored HTML is rendered in: `<templates/comment.gohtml, under hx-disable and after sanitizing | nowhere>`.
- Escaping bypasses allowed: `<render.Markdown returns sanitized template.HTML | none>`.

## Fragment or page

- A handler tells them apart with: `<render.Page(w, r, page, fragment) | HX-Request-Type>`.
- Validation errors answer: `<422 with the form; response-targets swaps it | 200 with the form>`.
- No-JavaScript fallback: `<required: forms keep action and method | not required behind login>`.

## Reference templates

| Concern | Read |
| --- | --- |
| A page that fills the layout | `<web/templates/cart.gohtml>` |
| A form with validation errors and a disabled submit | `<…>` |
| A list row that replaces itself | `<…>` |
| Search with a debounce and `hx-sync` | `<…>` |
| An out-of-band update | `<…>` |

## Symptom → use this instead

| The template hand-rolls… | Use |
| --- | --- |
| A form field with label and error | `{{ template "field" … }}` |
| A flash message | `{{ template "toast" … }}` — the `#toast` region in the layout |
| Pagination | `<…>` |
| A confirm dialog | `hx-confirm` — `<no custom dialog>` |
| A loading indicator | `<the .htmx-indicator in the layout>` |

## Known ceilings — do not recommend past these

- `<the dashboard polls every 5 s by design until SSE is in>`
- `<one ceiling per line, stated as a rule a reviewer can check>`

## Deferred — never propose as gaps

`<offline support, optimistic updates, …>`
