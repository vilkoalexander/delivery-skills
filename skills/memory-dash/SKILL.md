---
name: memory-dash
description: Use when asked to audit, clean, review or visualise Claude Code auto-memory (the ~/.claude/projects/*/memory directories and MEMORY.md), when memory seems to repeat itself or contradict itself, or when the user says memory dash, memory audit, memory health or "what do you remember about this project".
---

# Memory Dash

Opens a dashboard of memory health across every project on the machine,
audits the current project's memory in depth, and leaves a numbered list of
cleanup actions in chat. Nothing is applied until the user names an action.
The page is a local file with every memory inlined. Its charts load Chart.js
from cdnjs; offline the charts are absent and the rest works.
Memory dirs are not under git. `apply.py` prints old and new content before it
writes and copies the old files to `$OUT/backup/<time>/`; that copy is the
undo.

[RUBRIC.md](RUBRIC.md) defines duplicate, conflict, superseded, stale,
task-like, the quality scale and the score.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/memory-dash/scripts/`. Python 3.9, stdlib only.

## Paths

```
SLUG   = $(python3 scripts/collect.py --slug)       (-Users-me-Projects-app)
MEMDIR = ~/.claude/projects/$SLUG/memory
OUT    = ~/.claude/memory-dash/$SLUG
```

Do not build the slug by hand. Claude Code replaces every character that is
not a letter or a digit, and keys the directory on the project root, not on a
subdirectory; `--slug` finds it.

No `MEMDIR` means this project has no memory yet: say so, run `stats` mode.

## Modes

| Argument | Scan | Audit | Then |
| --- | --- | --- | --- |
| none | all projects | current project | open dashboard, report |
| `stats` | all projects | none | open dashboard, report |
| `all` | all projects | every project with files, one at a time, each with its own `SLUG`, `MEMDIR` and `OUT` | open each dashboard, report |
| `apply <n,m \| all>` | | | apply those actions, rescan, re-render, report |
| `why <n>` | | | print both files behind action n |
| `skip <n>` | | | drop action n from the list for this session |

## Workflow

1. **Scan.** `python3 scripts/collect.py --current=$SLUG --out $OUT/inventory.json`.
   Prints project and file counts. Read `inventory.json` for the current
   project only: its `memories` (file, name, description, type, flags),
   `not_indexed`, `dangling_index`.
2. **Audit** (skip in `stats`). Read **every** memory file in `MEMDIR` in
   full plus `MEMORY.md`, with the Read tool, and judge against RUBRIC.md. Start with the `dup_candidate:` flags,
   then read the rest for conflicts and superseded pairs; those are rarely
   flagged mechanically. Write `$OUT/audit.json` in the schema below; it
   replaces the audit of the run before.
   `files_read` is the count actually read; it must equal `files` in the
   inventory.
3. **Render.** `python3 scripts/render.py --dir $OUT`; in `stats` mode add
   `--no-audit`. Opens the browser. Prints the score. The script keeps the
   score of the run before for the delta; move no file yourself.
4. **Report** in the format below. Stop and wait.
5. **Apply.** On `apply 1,3`: for each n run
   `python3 scripts/apply.py --audit $OUT/audit.json --memdir $MEMDIR --n 1`
   (dry run, prints before and after), show the user nothing extra, then run
   it again with `--yes`. Exit 2 means a `resolve` action: ask the one
   question it prints, turn the answer into a `rewrite` or `delete` entry
   appended to `audit.json`, apply that. Exit 1 means the action names a file
   that is not a plain `*.md` name in `MEMDIR`: report it, do not work around
   it. `--yes` marks the action applied in `audit.json` and removes the
   findings about the files it touched, so the next score does not count
   them. After the batch, rerun steps 1 and 3 and report the new score.
   Re-audit only the files that were touched.

## audit.json

```json
{
  "slug": "-Users-me-Projects-app", "audited": "2026-10-12T21:45:00", "files_read": 18,
  "duplicates":  [{"keep": "a.md", "drop": "b.md", "confidence": "confirmed|plausible", "why": "…"}],
  "conflicts":   [{"files": ["a.md", "b.md"], "fact": "…", "a_says": "…", "b_says": "…", "resolution": "a.md|b.md|unknown"}],
  "superseded":  [{"newer": "a.md", "older": "b.md", "why": "…"}],
  "stale":       [{"file": "a.md", "why": "…"}],
  "task_like":   [{"file": "a.md", "why": "…"}],
  "quality":     {"a.md": 4},
  "next_actions": [{"n": 1, "kind": "resolve|merge|delete|rewrite|reindex", "files": ["…"],
                    "text": "one line, imperative", "edit": "full resulting file content, or null"}]
}
```

`files` order matters: for `merge` it is `[keep, drop, …]`. `edit` is the
whole file, frontmatter included, for `merge` and `rewrite`; `null` otherwise.
At most 7 actions, ordered conflicts, confirmed duplicates, superseded,
reindex, stale, rewrite. Plausible duplicates and unknown conflicts are
`resolve`, never `delete`.

## Report format

```
memory-dash — <display path>   score <n> (<+d|−d|first run>)   <files> files, <files_read> read
1. [resolve]  a.md ↔ b.md — <fact>: "<a says>" vs "<b says>"
2. [merge]    keep a.md, drop b.md — <why>
3. [reindex]  c.md, d.md — not in MEMORY.md
…
apply <n,m|all> · why <n> · skip <n>
<path to index.html>
```

One line per action. No section for findings that got no action; they are on
the dashboard.

## What goes wrong

- Auditing from `inventory.json` descriptions instead of reading the files.
  Then `files_read` is a lie and the dashboard shows it.
- Deleting a plausible duplicate. Plausible means each file has something the
  other lacks; the action is `merge` with the combined `edit`, or `resolve`.
- Picking a conflict winner by mtime. The newer file can be the wrong one.
- Writing `edit` without frontmatter. `apply.py` rebuilds the index line from
  it when the name or the description changed; a missing `name` produces an
  index line with the file name in both places.
- A path in `files`. An entry is a file name in `MEMDIR`, never `../x`, a
  subdirectory or an absolute path. `apply.py` refuses the action.
- Running `all` with subagents. The user wants to see each judgment; audit the
  projects in sequence in this session.
