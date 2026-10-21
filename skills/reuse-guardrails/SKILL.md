---
name: reuse-guardrails
description: Use when agents in a project keep re-implementing helpers the shared layer already has, duplicating code across tasks, adding a wrapper or base class for one caller, or pulling in a dependency the repo already covers, and the human is catching it by reading every diff. Also when asked to audit, set up or add reuse, DRY or KISS guardrails to a repository, or asked which of them a repository is missing.
---

# Reuse Guardrails

Audits a repository for the thirteen guardrails in [CHECKLIST.md](CHECKLIST.md)
and implements the ones the human names. The guardrails stop an agent from
rebuilding what exists: three put the inventory in front of the implementer
before it writes, five make the linter and the gate refuse the line, five
make a reviewer own what got through. Nothing is committed; the human reads
`git diff`.

## Workflow

1. **Root.** The repository to audit. Default: the git root of the cwd. It
   is a different repository from this plugin's; never audit the plugin.
2. **`bash scripts/audit.sh <root>`** — PASS / MISS / MANUAL per id, then a
   `MISS:` list. Read CHECKLIST.md's section for each MISS before reporting;
   the audit reads config, the section says what the gap costs. On a B2 or
   B3 PASS open the config it names: the script sees that a restriction
   exists, not that its message names a replacement; a PASS whose entries
   are all i18n or effect bans is reported as MISS with that reason.
3. **Report** in the format below and **stop**. The cost on each MISS line
   is the section's "Absent" sentence made concrete with this repository's
   names: the helper that would be rebuilt, the package the ban would go
   in, the install command `CLAUDE.md` mandates. Every MISS is a change to
   the project's lint, hooks or skills, and which ones are worth a chunk is
   the human's call. Never implement unasked.
4. **Implement the ids named**, one at a time, in the order A → B → C, each
   by its CHECKLIST.md recipe. The recipe's names (`useDebouncedValue`,
   `@shared/utils`) are examples: replace every one with the project's own
   export, found with the rubric's `scripts/inventory.sh`, never guessed. A
   recipe that needs a package installed uses the project's install command
   from `CLAUDE.md` when it has one.
5. **Verify.** Re-run the audit: each named id now PASS. Run the project's
   lint over the tree once for B1, B2 or B3: a new ban that fails on
   existing code is listed under `Fails today`, not silenced. Nothing is
   committed.
6. **Report** again, same format, with the diff to read.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/reuse-guardrails/scripts/`. `reuse-scan.sh`
is the diff-time half: the static gate and `review-routing` call it; this
workflow never needs to.

## Output format

```
Reuse guardrails — <root>
PASS <n> · MISS <n> · MANUAL <n>

MISS:   <id> <one line from the audit> — <what it costs here, from CHECKLIST.md>
MANUAL: <id> <the question the human answers>

Implemented: <id>: <files changed>           (after step 4; omit before)
Fails today: <rule> — <count> files; <first three>   (a new ban the tree does not yet pass)
Audit now:   MISS <ids left>, or "nothing"

Read it: git diff
Next: name the ids to implement, or "stop"
```

A line with nothing to list is left out.
