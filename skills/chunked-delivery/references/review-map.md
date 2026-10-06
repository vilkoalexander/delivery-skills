# Review map

A page for the human, built only when they ask for one after a chunk is
reported. A human cannot review a hundred files as one diff. The map says
what to read closely, what to skim, what to trust, in what order, and what
only they can decide.

It is a reading aid. It never replaces the reviewer dispatch or the diff
snapshot, and nothing in the loop waits on it.

## Source of truth

The file rows come from git, never from memory:

```bash
git add -N .
git diff --numstat                                        # every row, with +/-
git apply --numstat --allow-empty "$WORKSPACE/chunk-$N-before.diff"
```

Every row carries the +/- counts from the first list. A path whose counts
match the second list was already there before this chunk and stays off the
map. The number of rows on the page equals the number of rows left; a map
that is one file short is wrong.

Tiers, notes, questions and flows come from the implementer and reviewer
reports and `scripts/risk.sh`, the same sources as the chunk report. The
controller does not open the snapshot for the map either.

## Tiers

Each file gets one tier and a one-line note.

| Tier | What goes in it |
| --- | --- |
| read carefully | A decision lives here: schema, invariants, shared abstractions, anything a stranger must understand to approve the chunk |
| skim | Shape and names only; the lines follow from a careful file |
| trust | Tests, locale copies, generated or moved code, pure renames |

A path `risk.sh` rates high is read carefully whatever the reports say. A
file no report mentions is skim, and its note says so.

Totals per tier, files and changed lines, sit at the top of the page.

## Stops

Five to seven numbered sections in data-flow order: rules and conventions
first, then persistence, then contracts, then shared pieces, then the
feature, then screens changed underneath it, then copy and i18n last. Every
file sits in exactly one stop.

Each stop has:

- a time estimate
- two sentences headed "Why this stop exists"
- a list headed "Only you can answer": product or taste decisions the reader
  must rule on, never a question the code answers
- its file rows: tier, path, +/-, note
- a copyable `git diff -- <careful files>` command for its careful files

## Flows

Mermaid sequence diagrams for the two or three main runtime paths the chunk
introduces: request in, data out, cache invalidation. When the chunk touches
a query layer, add a flowchart of which writes invalidate which cache keys.
The report's `Flow:` line is ASCII because a terminal renders nothing; the
page does render, so here they are real diagrams.

## Manual checklist

Everything no executed test covers, as tick boxes: what has to be tried on a
phone, in a browser, or against a real backend. Say explicitly which
automated flows exist but have not been run.

## Known gaps

Unexecuted tests, defaulted decisions the human never answered, deliberate
scope cuts, flakes seen once. One line each.

## Alternative commit split

A table of three to five commits: a conventional title, which stops each
would hold, and its file count. The human can commit along it, or ask for
the chunk staged that way.

## Interaction

- A tick box per file, persisted in `localStorage` under the path and its
  counts, so a republish keeps the ticks and a file a fix round touched
  comes back unticked.
- A progress meter that counts careful files only.
- Filter chips for the three tiers.
- A "Copy" button on each diff command.
- Light and dark theme through CSS tokens.

One HTML file, no build step, mermaid from a CDN. Write it fresh each time
to `$WORKSPACE/chunk-$N-map.html`, next to the snapshots and outside the
working tree, and publish that file; republishing the same file keeps the
link. The page holds paths, counts and notes. It points at the diff by
command and never embeds it.

## Style

Plain language, no emoji, no praise, no restating what the code does. A note
on a file row says why the file is in that tier, not what it contains.
