# Static setup — the strict recipes

Loaded only when `scripts/static-gate.sh coverage` ends with a `SETUP:` line
and a tooling chunk is being proposed or built. Each section is one item the
coverage report can name. The bar throughout: **warnings fail the build**,
**type-aware lint on**, and every rule a rubric's severity floor depends on
at `error`. Everything here is a one-time chunk; every review after it stops
paying for that class of finding.

Pick the sections the report named. Do not install what the project does not
use — the Angular section on a React repo is noise.

Written 28 September 2026 from the packages' documentation, without a live
check. Flat-config export names (`configs.strictTypeChecked`,
`configs['recommended-latest']`, `flatConfigs.strict`) move between majors:
before the tooling chunk is built, the implementer reads each named
package's current README and takes the names from there.

## typescript

`tsconfig.json`, `compilerOptions`:

```jsonc
{
  "strict": true,                              // noImplicitAny, strictNullChecks, useUnknownInCatchVariables, …
  "noUncheckedIndexedAccess": true,            // arr[i] is T | undefined — the one most projects lack
  "exactOptionalPropertyTypes": true,          // ?: T means absent, not undefined
  "noImplicitReturns": true,
  "noImplicitOverride": true,
  "noFallthroughCasesInSwitch": true,
  "noPropertyAccessFromIndexSignature": true,  // obj.foo on a Record needs obj["foo"]
  "verbatimModuleSyntax": true,                // type imports are explicit; needed by isolated builds
  "isolatedModules": true,
  "skipLibCheck": true
}
```

Angular, `angularCompilerOptions`: `strictTemplates`, `strictInjectionParameters`,
`strictInputAccessModifiers` all `true`.

Script: `"typecheck": "tsc --noEmit -p tsconfig.json"` (per project in a
monorepo: `tsc -b` with project references). Turning on
`noUncheckedIndexedAccess` or `exactOptionalPropertyTypes` on an existing
codebase produces errors in bulk; that is the tooling chunk's diff, and the
implementer fixes them as `!== undefined` guards, not as `!` assertions.

## eslint

Flat config, `typescript-eslint` with the type-checked strict preset, and
the project service so no `parserOptions.project` list goes stale:

```bash
npm i -D eslint typescript-eslint eslint-config-prettier
```

```js
// eslint.config.js
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  { languageOptions: { parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname } } },
  {
    rules: {
      '@typescript-eslint/no-floating-promises': 'error',   // an unawaited prisma call is a silent no-op
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unsafe-assignment': 'error',
      '@typescript-eslint/require-await': 'error',
      '@typescript-eslint/switch-exhaustiveness-check': 'error',
      '@typescript-eslint/consistent-type-imports': 'error',
      'no-console': 'error',                                // backend logs go through the logger; see observability-review
    },
  },
  { files: ['**/*.js', '**/*.mjs'], ...tseslint.configs.disableTypeChecked },
  prettier,                                                  // last: turns off formatting rules, prettier owns them
  { ignores: ['dist/**', 'coverage/**', 'node_modules/**'] },
);
```

Script: `"lint": "eslint . --max-warnings=0"`. Without `--max-warnings=0` a
`warn` never fails anything and is scrolled past forever; the coverage
report lists it as absent for that reason. `strictTypeChecked` on an existing
codebase: run it once, fix what is real, and disable a rule only per file
with a one-line reason, never globally.

## react

```bash
npm i -D eslint-plugin-react eslint-plugin-react-hooks eslint-plugin-jsx-a11y
# React Native adds:
npm i -D eslint-plugin-react-native
# With the React Compiler enabled:
npm i -D eslint-plugin-react-compiler
```

```js
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';
import jsxA11y from 'eslint-plugin-jsx-a11y';

// add to the config array, scoped to tsx:
{
  files: ['**/*.tsx'],
  plugins: { react, 'react-hooks': reactHooks, 'jsx-a11y': jsxA11y },
  settings: { react: { version: 'detect' } },
  rules: {
    ...reactHooks.configs['recommended-latest'].rules,     // rules-of-hooks error, exhaustive-deps warn
    'react-hooks/exhaustive-deps': 'error',                 // warn is absent under --max-warnings=0 anyway
    'react/jsx-key': ['error', { checkFragmentShorthand: true }],
    'react/jsx-no-leaked-render': 'error',                  // {count && <X/>} renders "0"
    'react/no-array-index-key': 'error',
    ...jsxA11y.flatConfigs.strict.rules,
  },
}
// React Native, same block:
//   'react-native/no-inline-styles': 'error', 'react-native/no-unused-styles': 'error',
//   'react-native/no-raw-text': 'error'
// React Compiler:  'react-compiler/react-compiler': 'error'
```

## angular

```bash
ng add angular-eslint          # or: npm i -D angular-eslint
```

```js
import angular from 'angular-eslint';

{ files: ['**/*.ts'], extends: [...angular.configs.tsRecommended],
  processor: angular.processInlineTemplates,
  rules: {
    '@angular-eslint/prefer-standalone': 'error',
    '@angular-eslint/prefer-inject': 'error',
    '@angular-eslint/prefer-signals': 'error',
    '@angular-eslint/prefer-on-push-component-change-detection': 'error',
    '@angular-eslint/no-async-lifecycle-method': 'error',
  } },
{ files: ['**/*.html'], extends: [...angular.configs.templateRecommended, ...angular.configs.templateAccessibility],
  rules: {
    '@angular-eslint/template/prefer-control-flow': 'error',
    '@angular-eslint/template/use-track-by-function': 'error',
    '@angular-eslint/template/click-events-have-key-events': 'error',
    '@angular-eslint/template/interactive-supports-focus': 'error',
  } },
```

Plus `strictTemplates` in `tsconfig.json` (typescript section above): the
compiler then owns template type errors and `@for` without `track`.

## tests

One plugin, matching the runner. Its rules are what makes "a test that
cannot fail" a build error instead of a review finding.

```bash
npm i -D @vitest/eslint-plugin       # vitest
npm i -D eslint-plugin-jest          # jest
```

```js
import vitest from '@vitest/eslint-plugin';      // or: import jest from 'eslint-plugin-jest';

{ files: ['**/*.{test,spec}.{ts,tsx}', '**/__tests__/**'],
  plugins: { vitest },
  rules: {
    ...vitest.configs.recommended.rules,
    'vitest/expect-expect': 'error',            // a test with no assertion
    'vitest/no-focused-tests': 'error',         // .only
    'vitest/no-disabled-tests': 'error',        // .skip
    'vitest/no-conditional-expect': 'error',    // expect inside if / catch
    'vitest/no-standalone-expect': 'error',
    'vitest/valid-expect': 'error',             // unawaited async matcher
    'vitest/prefer-strict-equal': 'error',
    'vitest/no-identical-title': 'error',
    '@typescript-eslint/unbound-method': 'off',  // false positives on expect(fn).toHaveBeenCalled
  } },
```

Same rule names under `jest/`. What no lint rule can see — a test that
passes with the change reverted — is `test-review`'s `revert-check.sh`.

## boundaries

Import direction and cycles. Pick one:

- **Nx workspace** — `@nx/enforce-module-boundaries` with project tags in
  each `project.json` (`"tags": ["scope:api", "type:feature"]`) and
  `depConstraints` in the root ESLint config: a `type:ui` project may not
  import `type:data-access`; a `scope:web` project may not import
  `scope:api`. This is the gate `api-contract-review` asks about.
- **Plain repo** — `eslint-plugin-boundaries` with one `element` per layer
  (`features`, `shared`, `app`) and `boundaries/element-types` at `error`;
  or `dependency-cruiser` with `--config .dependency-cruiser.cjs` in the
  lint script, which also draws the graph.

Both: `eslint-plugin-import-x` with `import-x/no-cycle: 'error'` and
`import-x/no-extraneous-dependencies: 'error'` (a client bundle importing a
backend-only package).

## prettier

```bash
npm i -D prettier eslint-config-prettier
```

`.prettierrc`: `{ "singleQuote": true, "trailingComma": "all", "printWidth": 100 }`
— the values matter less than the file existing. Script:
`"format:check": "prettier --check ."`. `eslint-config-prettier` goes last in
the ESLint config so the two never fight. Style then leaves code review
entirely; nobody types a nit about quotes again.

## dead-code

```bash
npm i -D knip
```

`knip` finds unused files, exports, types and dependencies with zero config
on most setups; `knip.json` scopes it for monorepos. Script: `"knip": "knip"`,
in CI. It is what catches the abstraction an implementer built for one
caller and then stopped calling.

## hooks

Local and CI, the same commands:

```bash
npm i -D husky lint-staged
npx husky init
```

`.husky/pre-commit`: `npx lint-staged`. `package.json`:

```json
"lint-staged": {
  "*.{ts,tsx}": ["eslint --max-warnings=0 --fix", "prettier --write"],
  "*.{json,md,yml}": ["prettier --write"],
  "*.prisma": ["prisma format"]
}
```

CI runs, in this order and each failing the job: `typecheck`, `lint`,
`format:check`, `knip`, `test`, and for Prisma projects
`prisma validate` and `prisma migrate diff --from-migrations ./prisma/migrations --to-schema-datamodel ./prisma/schema.prisma --exit-code` (drift).

Secrets: `gitleaks` as a pre-commit hook (`gitleaks protect --staged`) and in
CI (`gitleaks detect`). Nothing in a review rubric can see a key that was
already pushed.

## What no tool covers

The coverage report's ABSENT list will shrink to this: tenant scoping,
index leading columns, money types, ledger immutability, whether a catch
logs, whether a test asserts the mock, whether a component reinvents a
shared primitive. Those are the rubrics' job by design; the recipes above
are so a reviewer never spends attention on anything else.
