---
name: comment-cleanup
description: Use when asked to clean up, shrink, strip, prune or audit the code comments in a codebase, a directory or a set of files, or when existing code is over-commented or reads as generated. For comments inside a diff under review, the domain rubrics already cover it.
---

# Comment Cleanup

Deletes or shrinks the comments a reader does not need. Comment lines are the
only thing that changes: no code, no rename, no reformat. Nothing is
committed; the human reads `git diff`.

[RULES.md](RULES.md) is the rule: the four kinds of comment that stay, what
goes, and what is never touched.

## Workflow

1. **Scope.** A file, a directory or a glob. None given — every tracked
   source file.
2. **Clean tree.** `git status --porcelain -- <scope>` prints nothing, or stop
   and say so. The diff this leaves has to show comment changes and nothing
   else.
3. **`bash scripts/scan.sh <scope>`** — comment lines per file, densest first,
   then the mechanical flags as `file:line`. Flags, not a verdict.
4. **Project layer**, when the project has one. `CLAUDE.md` / `AGENTS.md` and
   the lint config, for the comment shapes this project mandates: a licence
   header, a TODO marker, TSDoc on public API. Those stay.
5. **Judge every comment in scope** against RULES.md, file by file: delete,
   shrink to one line, or keep. The scan's flags are where to start, not the
   whole list. A comment you cannot classify because you do not understand
   the code around it stays, and goes in the report under `Unsure`.
6. **Edit comments only.** A comment on its own line goes with its line, and
   with the blank line it would leave doubled. A trailing comment goes and
   the code before it stays byte for byte. A comment that a rename would
   replace is not renamed here: leave it and list it under `Rename instead`.
7. **`bash scripts/verify.sh <scope>`** — exits non-zero when a changed line
   is not a comment. Then the project's lint and typecheck. Either failing
   means a code line moved: restore it, do not explain it.
8. **Report** in the format below.

More than forty files with comments: work one directory at a time, densest
first, and report after each. A directory may go to a subagent on
`model: sonnet`; it gets RULES.md, its paths and its slice of the scan output,
and runs `verify.sh` itself.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/comment-cleanup/scripts/`. They read the
JavaScript and TypeScript family by default; `COMMENT_EXT` widens the scan,
and other languages are judged by hand.

## Output format

```
Comment cleanup — <scope>
<files> files changed, <before> → <after> comment lines

Unsure:         <file:line> — <what could not be judged>
Rename instead: <file:line> — <name> → <name that needs no comment>
No reason:      <file:line> — suppression with no reason given
TODO:           <file:line> — <its text>
Verify:  <the last line of verify.sh> · <lint and typecheck result, or "none set up">

Read it: git diff
```

A line with nothing to list is left out. `<before>` and `<after>` are the
"to judge" number `scan.sh` prints, run before and after.
