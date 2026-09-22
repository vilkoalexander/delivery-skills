# Angular review — project layer

Loaded by `angular-review` at step 2. Keep every entry a real path or selector.

## API generation

`<signals + standalone + built-in control flow | decorators + NgModules | mid-migration: new files use signals, existing files stay until touched>`

Angular `<version>`. Zoneless: `<yes | no | planned>`.

## Reference units

| Concern | Read |
| --- | --- |
| A feature page with route-driven state | `<app>/src/app/<feature>/<x>-page.component.ts` |
| A shared presentational component (inputs, OnPush, no service) | `<ui-lib>/src/lib/<x>/<x>.component.ts` |
| A data-access service with `toSignal` at the boundary | `<feature-lib>/data-access/src/lib/<x>.service.ts` |
| A typed reactive form | `<app>/src/app/<feature>/<x>-form.component.ts` |

## Styling system

- `<SCSS with design tokens in <styles-lib> | Tailwind | Angular Material theme>`.
- Design doc: `<path>` — its "do not" list is binding.
- Global styles allowed only in `<path>`; everything else is encapsulated.

## Symptom → use this instead

| The component hand-rolls… | Use |
| --- | --- |
| A page shell with title and actions | `<ui-page-header>` |
| A confirm dialog | `ConfirmDialogService.open()` |
| A date in the user's locale | `localDate` pipe |
| A loading skeleton | `<ui-skeleton>` |
| An empty-list placeholder | `<ui-empty-state>` |
| HTTP with auth + error mapping | `ApiClient` — never raw `HttpClient` in a component |

## Known ceilings — don't recommend past these

- `<ui-table>` is presentational; sorting and paging state live in the page.
- `<legacy module X>` stays on NgModules until `<condition>`; do not flag its files.

## Testing policy

`<Component harness tests for shared UI; no snapshot tests | Cypress component tests | …>`

## Deferred — never propose as gaps

`<SSR, i18n runtime switching, …>`
