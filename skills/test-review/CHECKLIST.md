# Test Review Checklist

Seven categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). For
each finding, name what wrong code this test would let through: "this is
weak" without "X could break and this stays green" is not a finding.

## Before you start

### Version baseline

Read the installed test stack before applying the rules:

```bash
node -e 'const p=require("./package.json"),d={...p.dependencies,...p.devDependencies};for(const k of ["vitest","jest","@jest/globals","mocha","@testing-library/react","@testing-library/react-native","@testing-library/angular","@nestjs/testing","supertest","msw","playwright","@playwright/test","cypress","nock"])if(d[k])console.log(k,d[k])'
```

- **Vitest or Jest** — `vi.useFakeTimers()` / `jest.useFakeTimers()` exist;
  a real `setTimeout` wait is never necessary.
- **`node:test`** — no built-in fake timers; a timer wait needs
  `mock.timers` (Node 20.4+) or the code under test takes a clock.
- **Testing Library present** — queries by role and text are the baseline;
  `container.querySelector` and test IDs are the fallback, not the default.
- **`@nestjs/testing` present** — the module under test is built with
  `Test.createTestingModule`; a hand-`new`ed service with hand-built
  dependencies bypasses DI and the project's providers.

### Tooling coverage

Do not assume what lint catches. Run once per review:

```bash
npx eslint --print-config <file> | grep -E '"(jest|vitest)/(no-disabled-tests|no-focused-tests|expect-expect|valid-expect|no-conditional-expect|no-identical-title|no-standalone-expect|valid-title)'
```

Rules that resolve to `"error"` are the build's job — skip them. `"warn"`
does not fail the build — still report. Absent rules (`expect-expect`,
`no-focused-tests`, `no-conditional-expect`) have zero automated coverage
and are this skill's job. `scripts/scan.sh` targets the absent set. When the
dispatch handed you a coverage table from the static gate, use that and skip
the command.

For the full picture — every analyzer the repository has or lacks, and the
strict recipe for each missing one — `bash
${CLAUDE_PLUGIN_ROOT}/skills/delivery-pipeline/scripts/static-gate.sh
coverage` and its `STATIC-SETUP.md`.

## Severity floor

Always 🔴, regardless of effort. The `.only` / `.skip` and no-assertion rows
are lint-checkable: when the project holds `no-focused-tests`,
`no-disabled-tests` or `expect-expect` at error they never reach a review
and the Do NOT report list applies; the floor is for what lint cannot see.

- a test that still passes with the change under test reverted
- a test with no assertion, or whose only assertion cannot fail
  (`expect(true).toBe(true)`, `expect(x).toBe(x)`, `expect(fn).toBeDefined()`)
- `.only` or `.skip` left in
- the module under test, or the dependency whose behaviour the test claims to
  check, is mocked so the code path never runs

## 1. Can it fail?

- **[hard] Survives reversion** — the revert check (SKILL.md step 5) says the
  test passes without the change. It tests nothing the change added.
- **[hard] Asserts the mock, not the unit** — the mock returns X, the test
  asserts X came back. The unit could be `return dep()` or `return 42` and
  one of those passes anyway.
- **[hard] No assertion** — a call with no `expect`/`assert`, or one whose
  assertion is inside a branch or callback that may never run.
- **[hard] Assertion on a mock call as the only assertion** —
  `toHaveBeenCalled` alone proves the wiring, not the result. Fine as a
  second assertion, never the first.
- **[prefer] Swallowed failure** — `try { … } catch {}` around the act, or
  an async assertion that is not awaited, so a rejection passes.

## 2. Mocking

- **[hard] Mocks the unit under test** — `vi.mock('./thing')` for the file
  the test imports as its subject, or a `spyOn` on the method being tested.
- **[hard] Mocks what the test claims to verify** — "saves the order" with
  the repository mocked to succeed asserts nothing about saving.
- **[prefer] Mocks what could run for real** — pure utils, in-memory maps,
  date formatting. A mock of a pure function is a second implementation to
  keep in sync.
- **[prefer] Mock shape drifts from the real one** — a mock returning a
  field the real type no longer has, or typed `any`. The test passes against
  an API that does not exist.
- **[context] Global mocks with no reset** — `vi.mock` at module scope with
  state shared across tests; report when a test depends on a previous one's
  calls.

## 3. Behaviour, not implementation

- **[hard] Asserts private state or call order** — reaching into internals,
  `toHaveBeenNthCalledWith` on incidental order, asserting a debounce fired
  exactly N times when the contract is "eventually".
- **[prefer] Name describes the method, not the behaviour** — "calls
  findOne" tells the reader nothing; "returns 404 when the order belongs to
  another tenant" does.
- **[prefer] One behaviour per test** — five unrelated asserts under one
  name mean the failure message says nothing.
- **[context] Testing the framework** — that a getter gets, that a DTO has a
  field, that `class-validator` validates. Report only when it displaces a
  test of the project's logic.

## 4. Covers the change

Judge against the diff, not the whole test file.

- **[hard] New branch without a case** — an `if`, a `catch`, an early
  return the change adds and no test reaches. Name the branch.
- **[hard] Error path untested** on a change to error handling, auth,
  money or data deletion — the happy path is the case least likely to be
  wrong.
- **[prefer] Boundary untested** — empty input, one item, the limit, the
  off-by-one the change moved.
- **[context] Happy path only** elsewhere — report when the change's point
  was a guard or an edge.

## 5. Determinism and isolation

- **[hard] Real time** — `await new Promise(r => setTimeout(r, N))`,
  `sleep`, `waitFor` with a long timeout hiding a race. Use fake timers or
  await the condition.
- **[hard] `.only` / `.skip`** — the floor; `.skip` with a linked issue and
  a date is the one exception, and the project layer must say so.
- **[hard] Shared mutable state** across tests with no `beforeEach` reset —
  a module-level array, a mocked singleton, a DB row created once.
- **[prefer] Real network, filesystem or clock** without the project's
  fixture strategy — `msw`, a test container, an injected clock.
- **[prefer] Order dependence** — a test that fails alone or when shuffled.
  Random data without a seed belongs here.

## 6. Snapshots

- **[hard] Snapshot as the only assertion on logic** — a snapshot proves
  "unchanged", never "correct". Fine for a rendered tree; not for a
  calculation, a query, a payload.
- **[prefer] Large snapshot** — past roughly fifty lines nobody reads the
  diff; approval becomes `-u`.
- **[context] Inline snapshot** for a short serialisation is fine; report
  only when it hides a value the test should state.

## 7. Reinvention and noise

- **[hard] Hand-rolled helper the project already has** — a render wrapper,
  a factory, a fixture builder, an auth stub. `scripts/inventory.sh` lists
  what exists; name the real export.
- **[prefer] Duplicate case** — two tests that assert the same thing with
  different names.
- **[prefer] Test longer than the unit** with no reason given — usually
  setup that a factory would remove.
- **[context] Console noise** — output the project's runner does not
  silence; report when it hides a real failure.
- **[prefer] Comments that narrate the test** — the name says what it
  checks. A comment stays, on one line, only for why a fixture value or an
  ordering matters. No ticket, PR, date or link in a comment or a test name.

## Do NOT report

- A coverage percentage. Coverage is a number about lines, not about
  whether wrong code fails.
- Missing e2e or integration tests for a unit-level change — a PR-level
  concern, not this file's.
- The project's test style — `describe` nesting, `it` vs `test`, BDD
  wording, file placement. Consistency with the sibling is the bar.
- A test type the project has decided against; check the project layer.
- Anything the runner's lint already **errors** on (see Tooling coverage).
- Restating the project's instructions file as if it were a finding.
- Rewriting untouched sibling tests. Review the file in front of you.
