# React screen authoring — project layer

Loaded by `react-screen-authoring` at step 1. Keep every entry a real path,
export or command. Everything in `<angle brackets>` is a placeholder — replace
it or delete the row.

## Where the rules live

- Architecture doc: `<apps/<app>/ARCHITECTURE.md>` — the roles table there is
  authoritative when it and the plugin checklist disagree.
- Lint config with the role blocks: `<apps/<app>/eslint.config.mjs>`.
- Current rule severity: `<warn with a reported count | error>`.

## Reference files (read one of each before writing the same kind)

| Kind | Read |
| --- | --- |
| A builder and its spec | `<src/features/<x>/lib/<buildSection>.ts>` and `<lib/__tests__/<buildSection>.spec.ts>` |
| A coupled-form reducer and its spec | `<src/features/<x>/lib/<xFormState>.ts>` |
| A container | `<src/features/<x>/screens/<X>Screen.tsx>` |
| A view | `<src/features/<x>/components/<X>View.tsx>` |
| A sheet that keeps the draft contract | `<src/features/<x>/components/<X>Sheet.tsx>` |
| A behaviour hook with why-comments at the right altitude | `<src/hooks/<useSomething>.ts>` |
| The navigation param lists | `<src/navigation/types.ts>` |

## Conventions

- Path alias: `<@/*>` -> `<src/*>`. Alias resolves under jest: `<yes | no — use relative imports in anything a spec touches>`.
- Locale bundle: `<package or path>`; builder specs get `t` from `<src/test-helpers/i18n.ts>`, which throws on a missing key.
- Domain labels passed to builders: `<customerLabel, staffLabel, ...>` from `<useSettings()>`.
- Clock values passed to builders: `<todayYmd, nowHm>` from `<the clock hook>`.
- Single-field form hook: `<useFormField>`. Dirty guard: `<useDirtyFormGuard>`.
- Sheet primitive: `<BottomSheet>` (stays mounted through the exit animation).
- Floating-bar clearance hook: `<useBottomBarClearance>`.
- Touch-target token class: `<min-h-touch>`.
- Test-id convention: `<feature.screen.element>`, e.g. `<orders.detail.edit>` in `<file>`.

## Commands

- Lint: `<npx eslint src>`
- Unit tests: `<npm test>`
- E2E flows: `<npm run e2e>`; flows live in `<e2e/flows/>`; run against `<a release build>`.

## Counted exceptions (file-level `eslint-disable` with a why)

| File | Why |
| --- | --- |
| `<src/features/<x>/components/<X>Sheet.tsx>` | `<reseed effect until a shared sheet-session adapter exists>` |

## Deferred — never propose

`<a shared sheet-session adapter, a form library, …>`
