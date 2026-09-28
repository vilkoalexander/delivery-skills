# Test review — project layer

Loaded by `test-review` at step 2. Keep every entry a real path or export.
Everything in `<angle brackets>` is a placeholder — replace it or delete the row.

## Stack

- Runner: `<vitest | jest | node:test>` — config at `<vitest.config.ts>`, setup at `<test/setup.ts>`.
- UI: `<@testing-library/react-native>` through `<src/test-utils/render.tsx>` (wraps providers; never use the library's `render` directly).
- Backend: `<@nestjs/testing>` with `<test/create-testing-module.ts>`; database through `<test/db.ts>` (`<transaction per test | truncate | testcontainers>`).
- Network: `<msw handlers at src/mocks/handlers.ts>`; no real HTTP in unit tests.
- Clock: `<vi.useFakeTimers | injected Clock from src/lib/clock.ts>`.

## Symptom → use this instead

| The test hand-rolls… | Use |
| --- | --- |
| A user / tenant / order object | `<test/factories/user.ts: buildUser()>` |
| Providers around a component | `<src/test-utils/render.tsx: render()>` |
| An authenticated request | `<test/auth.ts: asUser(user)>` |
| A repository or Prisma stub | `<test/prisma-mock.ts>` |
| A queue or event bus stub | `<test/queue-stub.ts>` |

## Reference tests

| Concern | Read |
| --- | --- |
| A service with tenant scoping and an error path | `<apps/api/src/orders/orders.service.spec.ts>` |
| A component with async data and empty state | `<src/features/<x>/<X>Screen.test.tsx>` |
| A controller through supertest | `<apps/api/test/orders.e2e-spec.ts>` |

## Decided against — do not recommend

- `<Snapshot tests for screens; visual review is manual>`
- `<Unit tests for pure Prisma wrappers; covered by e2e>`
- `<`.skip` is allowed only with an issue link and a date in the title>`
