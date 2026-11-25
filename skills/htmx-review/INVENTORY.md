# Template Inventory

A fragment is reviewed against things that are not in its file: the htmx
major the layout loads, the element its `hx-target` names, the handler behind
its URL. **`scripts/inventory.sh` is authoritative for what exists.**

It prints, each section capped at `INVENTORY_LIMIT` lines (default 40):

| Section | Read it for |
| --- | --- |
| htmx | The version and how it is loaded: script tag, `package.json`, a vendored file. The `htmx-config` meta and the extensions in use. Two different versions here is a finding on its own. |
| which major the templates are written for | Counts of syntax only htmx 2 has, only htmx 4 has, and htmx 1 leftovers. A project on 2 with a non-zero htmx 4 count has markup that does nothing. |
| templates | File kinds and the layouts. `.templ` beside `.gohtml` means two escaping models. |
| partials and components | Every `{{ define }}`, `{{ block }}` and `templ` component with its file. The reinvention check of §8 starts here. |
| attributes in use | What this codebase actually uses. An attribute the file under review introduces alone deserves a second look. |
| hx-target ids that no template defines | A static `#id` in `hx-target`, `hx-indicator` or `hx-include` with no element of that id in any template. An id built from a template value is matched by its prefix. |
| server side of the contract | The Go files that read `HX-Request`, whether they set `Vary`, the `HX-` headers in use, the CSRF defence, the Content-Security-Policy. |
| other client-side code | Alpine, hyperscript, Datastar, inline scripts. Each one is another place where state lives. |

In a monorepo pass the application directory: `bash scripts/inventory.sh <app>`.

The project layer (`docs/review/htmx-review.md`, template in
`templates/htmx-review.md`) adds what a listing cannot: the htmx major and
the rule for files during an upgrade, whether the Content-Security-Policy
allows evaluated attributes, how a fragment endpoint is told from a page
endpoint, the symptom → use-this-partial table, and the known ceilings.

Layers: a layout owns `<head>`, the htmx script and the page-wide
attributes; a page fills the layout; a partial is one swappable unit with a
stable root id. A partial used by one page stays beside that page — do not
extract on first use.
