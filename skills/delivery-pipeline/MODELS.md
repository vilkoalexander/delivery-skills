# Model lineup

The generation the role table in `SKILL.md` was written against. Read this
only when substituting a model or when a new family member ships; the short
dispatch names in the table resolve to the current generation on their own.

## Lineup (28 September 2026)

| Family | Current | API ID | Tier |
| --- | --- | --- | --- |
| Fable | Fable 5.1 | `claude-fable-5-1` | most capable; 1M context; thinking always on; cache reads $0.25/MTok |
| Opus | Opus 5.5 (Opus 5 and 4.8 still served) | `claude-opus-5-5` | one-way doors, final review, high-risk review; default effort `medium`; cache reads $0.20/MTok |
| Sonnet | Sonnet 5.5, released 28 September 2026 (Sonnet 5 still served) | `claude-sonnet-5-5` | default task review; same $2/$10 as Sonnet 5; default effort `high` |
| Haiku | Haiku 4.5 | `claude-haiku-4-5` | mechanical implementers, scoped re-review; 200K context; no `effort`; retirement not before 15 October 2026 — re-check the `haiku` alias when a successor ships |
