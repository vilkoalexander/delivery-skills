# Reuse Guardrails Checklist

Thirteen items in three layers. An agent re-implements a helper, adds a
dependency the repo already has, or stacks an abstraction on one caller for
one reason: nothing told it otherwise at the moment it wrote the line. Layer A
tells it before, layer B refuses the line as it is written, layer C catches
what got through. A project that has only layer C pays a human to read for
reinvention on every diff.

`bash scripts/audit.sh [root]` tests every item that a script can test and
prints PASS / MISS / MANUAL per id. Each section below is one id: the rule,
how the audit decides, what its absence costs, and the recipe that turns a
MISS into a PASS. Implement only the ids the human names.

| Id | Guardrail | Layer | Audit |
| --- | --- | --- | --- |
| A1 | Reuse lines in the Global Constraints block | before | grep |
| A2 | Shared-layer inventory inside every implementer dispatch | before | grep |
| A3 | `## Reuse` block in every implementer report | before | grep |
| A4 | Project layer names the shared primitives | before | file |
| B1 | Duplicate detection in the lint script | during | dep + script |
| B2 | Hand-roll bans in the lint config, per app | during | config |
| B3 | Size budget per file role | during | config |
| B4 | Reuse scan in the static gate | during | grep |
| B5 | Lint on write | during | hooks |
| C1 | Reinvention rule in every domain rubric the project ships | after | grep |
| C2 | Reuse scan before every reviewer | after | grep |
| C3 | Branch-wide duplicate check in the whole-tree review | after | grep |
| C4 | A hand-caught finding becomes a rule | after | manual |

A project that ships none of `delivery-pipeline`, `chunked-delivery`,
`review-routing` or a `*-review` rubric of its own inherits this plugin's,
and the ids that live in those files pass by inheritance. A project that
copies one of them owns it, and the audit reads the copy.

## A — before the code exists

### A1 Reuse lines in the Global Constraints block

**Rule.** The block every reviewer and implementer gets carries three lines
a reviewer can check:

```
- A new util, hook, component or service helper only when the shared-layer inventory shows none; the report names the search.
- No new abstraction — interface, generic, base class, wrapper, factory — with fewer than two callers in this diff.
- No new runtime dependency unless the plan task names it.
```

**Audit.** The project's `delivery-pipeline` skill, or the plugin's when
there is none, contains all three phrases `inventory shows none`, `fewer than
two callers` and `runtime dependency`.

**Absent.** Reviewers grade reinvention on taste. Two reviewers, two verdicts.

**Recipe.** Paste the three lines into the `## Global Constraints` block of
`.claude/skills/delivery-pipeline/SKILL.md`, after the line about following
the patterns already in the files. Nothing else changes.

### A2 Shared-layer inventory inside every implementer dispatch

**Rule.** Once per chunk the controller runs the inventory script of each
rubric the chunk's paths route to (`react-review`, `nestjs-service-review`,
`api-contract-review`, …) and pastes the output under `## Inventory` in every
implementer dispatch for that chunk. When the plan already names the helper
to use, the task text names it by export and path.

**Audit.** The `delivery-pipeline` in force says `## Inventory` in its
implementer dispatch section.

**Absent.** The implementer writes `useDebounce` next to the project's
`useDebouncedValue`. The reviewer catches it one seat later, or does not.

**Recipe.** The "Implementer dispatch" section of this plugin's
`delivery-pipeline` has the paragraph; a project copy adds the same paragraph
and, when the project keeps its shared code somewhere the rubric scripts do
not look, the extra roots to pass (`inventory.sh <dir>`).

### A3 `## Reuse` block in every implementer report

**Rule.** The report ends with the Proof block and a Reuse block:

```
## Reuse
- reused: <export> from <path>        (one line each, or "nothing")
- searched: <what you looked for> — none found   (one per new helper)
- new shared: <path> — <why nothing above fit>   (or "nothing")
- new dependency: <name> — <plan task that named it>   (or "nothing")
```

A report without it goes back for the block, the same as a report without
Proof. A `new shared` line with no `searched` line above it goes back too.

**Audit.** The `delivery-pipeline` in force contains `## Reuse` in its
implementer report format.

**Absent.** The search never happens; the helper gets written first and
justified never.

**Recipe.** The "Implementer proof" section of this plugin's
`delivery-pipeline` carries the block; a project copy appends the same block
to its implementer report format.

### A4 Project layer names the shared primitives

**Rule.** For each rubric the project uses, `docs/review/<rubric>.md` exists
and its shared-primitives section lists the real exports: the date helper,
the money formatter, the list hook, the base DTO. Templates are in this
plugin's `templates/`.

**Audit.** At least one `docs/review/*.md` exists, and none still holds the
template's angle-bracket placeholders.

**Absent.** Both the implementer and the reviewer derive "what exists" from
a directory listing and a model's memory, which is where reinvention starts.

**Recipe.** Copy `templates/<rubric>.md` to `docs/review/<rubric>.md`, run
that rubric's `scripts/inventory.sh` and paste the exports it prints under
the shared-primitives heading, one line each with the file. Ten minutes per
rubric. Keep the file under a hundred lines.

## B — while the code is written

### B1 Duplicate detection in the lint script

**Rule.** `jscpd` is installed, configured at the repo root, and runs from
the lint script every reviewer and CI step already calls, with a threshold
that fails.

**Audit.** `jscpd` in devDependencies, a `.jscpd.json` or a `jscpd` key in
`package.json`, and a `lint`, `lint:all` or CI script that names it.

**Absent.** DRY is a reviewer's opinion. Cross-task duplication, where two
implementers who never met each other wrote the same twenty lines, has no
other detector.

**Recipe.**

```bash
npm i -D jscpd
```

```jsonc
// .jscpd.json
{
  "threshold": 1,                 // percent duplicated across the scan; fails above
  "minLines": 8,
  "minTokens": 60,
  "reporters": ["console"],
  "ignore": ["**/node_modules/**", "**/dist/**", "**/*.spec.*", "**/*.test.*", "**/__tests__/**", "**/migrations/**", "**/*.d.ts"],
  "absolute": true,
  "gitignore": true
}
```

`package.json`: `"lint:dup": "jscpd apps libs packages src 2>/dev/null"`,
and append `&& npm run lint:dup` to the script CI runs. Start at the threshold
the current tree passes (`jscpd` prints the percentage) and lower it one
point per sprint.

### B2 Hand-roll bans in the lint config, per app

**Rule.** Every app's ESLint config carries `no-restricted-syntax`,
`no-restricted-imports` or `no-restricted-properties` entries that name the
project's own replacement. One entry per thing the project already solved.

**Audit.** Each `eslint.config.*` or `.eslintrc*` under the root and under
`apps/*`, `packages/*`, `libs/*` and `libs/*/*` has at least one such rule;
`*-e2e`, `test-utils` and `testing` packages are skipped. A config with
zero is a MISS for that package. The script sees presence only: a PASS
still needs the human or the implementing agent to open the config and
confirm each entry's message names the replacement by export and path. A
config whose only restrictions are i18n or effect bans counts as PASS for
the script and MISS for the reader.

**Absent.** The lint passes a hand-rolled debounce, a `new Date()` subtraction
and a `toFixed(2)` on a money value, and all three reach a reviewer.

**Recipe.** Add to the app's config, one selector per project helper.
Messages name the replacement by export and path; a ban without a
replacement teaches nothing.

```js
'no-restricted-syntax': ['error',
  { selector: "CallExpression[callee.name='setTimeout'] ~ CallExpression[callee.name='clearTimeout']",
    message: 'Hand-rolled debounce. Use useDebouncedValue from src/hooks.' },
  { selector: "NewExpression[callee.name='Date'] > CallExpression[callee.property.name='getTime']",
    message: 'Date arithmetic. Use the helpers in @shared/utils date.' },
  { selector: "CallExpression[callee.property.name='toFixed'][arguments.0.value=2]",
    message: 'Money formatting. Use formatMoney from @shared/utils money.' },
  { selector: "CallExpression[callee.name='JSON'][callee.property.name='parse'] > CallExpression[callee.property.name='stringify']",
    message: 'Deep clone via JSON. Use structuredClone.' },
],
'no-restricted-imports': ['error', { paths: [
  { name: 'lodash', message: 'Not a dependency here. The helper you want is in src/lib/utils.' },
  { name: 'dayjs', message: 'Dates go through @shared/utils.' },
  { name: 'axios', message: 'HTTP goes through useApi.' },
]}],
```

Replace the names with the project's. `@shared/utils`, `useDebouncedValue`
and `useApi` above are examples, not defaults; the rubric's
`scripts/inventory.sh` prints the real ones.

### B3 Size budget per file role

**Rule.** `max-lines` is set per file role (screen, view, row, service,
controller) and `max-lines-per-function` once. A file over budget is a split,
not an exception.

**Audit.** `max-lines` appears in at least one lint config.

**Absent.** KISS is an adjective. A 600-line service passes lint.

**Recipe.**

```js
{ files: ['**/*.service.ts'],   rules: { 'max-lines': ['error', { max: 300, skipBlankLines: true, skipComments: true }] } },
{ files: ['**/*.controller.ts'], rules: { 'max-lines': ['error', { max: 150, skipBlankLines: true, skipComments: true }] } },
{ files: ['**/screens/**/*.tsx'], rules: { 'max-lines': ['error', { max: 150, skipBlankLines: true, skipComments: true }] } },
{ files: ['**/*.{ts,tsx}'],      rules: { 'max-lines-per-function': ['error', { max: 60, skipBlankLines: true, skipComments: true, IIFEs: true }] } },
```

Set each max to the largest file of that role that the project is happy
with today, then hold it there.

### B4 Reuse scan in the static gate

**Rule.** `scripts/reuse-scan.sh` next to this file runs over every chunk's
changed paths as part of the static gate, on every risk class, and its
output reaches the reviewer and the chunk report's `Reuse:` line.

**Audit.** The `delivery-pipeline` and `chunked-delivery` in force name
`reuse-scan`.

**Absent.** Low-risk chunks skip the reviewer, so a new `utils/format.ts` in
a low-risk chunk reaches the human unflagged.

**Recipe.** This plugin's `static-gate.sh check` already calls the scan when
the plugin is installed. A project copy of `chunked-delivery` adds the
`Reuse:` line to its chunk report and runs
`bash ${CLAUDE_PLUGIN_ROOT}/skills/reuse-guardrails/scripts/reuse-scan.sh`
in its step 3. `REUSE_SHARED` names the project's shared layers when they
are not `utils|lib|helpers|hooks|common|shared|components/ui`.

### B5 Lint on write

**Rule.** A `PostToolUse` hook on `Edit|Write` runs the linter on the file
just written, so an implementer meets B2 and B3 at the line, not at the
gate.

**Audit.** `.claude/settings.json` has a `PostToolUse` entry whose command
names `eslint`, `biome`, `prettier` or `tsc`.

**Absent.** Every ban in B2 costs a gate round trip instead of a retry.

**Recipe.** `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [ { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/lint-on-write.sh" } ] }
    ]
  }
}
```

`.claude/hooks/lint-on-write.sh`:

```bash
#!/usr/bin/env bash
# Lints the file an Edit or Write just touched. Output goes back to the agent.
f=$(jq -r '.tool_input.file_path // empty')
case "$f" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) ;; *) exit 0;; esac
cd "$CLAUDE_PROJECT_DIR" && npx --no-install eslint --max-warnings=0 "$f" 2>&1 | tail -30
exit 0
```

Exit 0 keeps the edit; the lint output is what the agent reads next.

## C — after the code exists

### C1 Reinvention rule in every domain rubric the project ships

**Rule.** Each review rubric the project keeps under `.claude/skills/*-review/`
carries a `[hard]` reinvention rule that tells the reviewer to run the
inventory script before judging it.

**Audit.** Every `.claude/skills/*-review/` whose name is not schema, prisma,
infra, test, observability or migration has a file matching `reinvent` or
`re-implement`, case-insensitively. Those rubrics judge things a helper
cannot rebuild. Rubrics inherited from this plugin pass.

**Absent.** The reviewer with the inventory in hand still has no rule that
says a hand-rolled helper is a finding.

**Recipe.** Add to the rubric's first category:

```
- **[hard] Reinvention** — re-implements something the shared layers already do.
  **Run `scripts/inventory.sh` before judging this.** Name the replacement by
  its real export, not a guess.
```

### C2 Reuse scan before every reviewer

**Rule.** The reviewer's routing step runs `reuse-scan.sh` over the diff and
treats every flag as a finding unless the implementer's `## Reuse` block
names why.

**Audit.** The `review-routing` in force names `reuse-scan`.

**Absent.** The scan's flags land in the gate log and nobody owns them.

**Recipe.** This plugin's `review-routing` has the bullet. A project copy
adds it under "Applying a single-file rubric to a diff".

### C3 Branch-wide duplicate check in the whole-tree review

**Rule.** Before the whole-tree reviewer is dispatched, `jscpd` runs over the
whole branch and its console report is in the reviewer's dispatch. A fresh
implementer per task never sees the previous task's helper; this is the one
check that spans tasks.

**Audit.** The `delivery-pipeline` in force names `jscpd` in its final or
whole-tree review text, and B1 passes.

**Absent.** Two tasks, two copies of the same mapper, one green review each.

**Recipe.** B1 first. Then, in the whole-tree dispatch, paste the output of
`npm run lint:dup` under `## Duplicates` and add the line "every duplicate
block in this report is a finding unless both copies predate the branch".

### C4 A hand-caught finding becomes a rule

**Rule.** Every reinvention, duplication or needless abstraction the human
catches by hand gets written once, as one of: a B2 selector, a line in the
A4 project layer, or a Global Constraints line. Never the same catch twice.

**Audit.** MANUAL. The audit prints the ask: does `docs/review/*.md` have a
"Caught by hand" section, and is its newest line younger than the newest
merged branch.

**Absent.** This item is the reason the human still reads every diff.

**Recipe.** Add to each `docs/review/<rubric>.md`:

```
## Caught by hand
- <date> <what the agent wrote> → <the rule that now stops it: B2 selector / A4 line / constraint>
```

A line here that has no rule next to it after a week is the next tooling
chunk.
