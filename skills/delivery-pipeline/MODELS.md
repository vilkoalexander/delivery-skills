# Model lineup

The generation the role table in `SKILL.md` was written against. Read this
only when substituting a model or when a new family member ships; the short
dispatch names in the table resolve to the current generation on their own.

## Lineup (9 November 2026)

| Family | Current | API ID | Tier |
| --- | --- | --- | --- |
| Fable | Fable 5.2 (Fable 5.1 still served) | `claude-fable-5-2` | most capable; $8/$40; 1M context; thinking always on; default effort `high`; cache reads $0.20/MTok |
| Opus | Opus 5.5 (Opus 5 and 4.8 still served) | `claude-opus-5-5` | one-way doors, final review, high-risk review; default effort `medium`; cache reads $0.20/MTok |
| Sonnet | Sonnet 5.5, released 28 September 2026 (Sonnet 5 still served) | `claude-sonnet-5-5` | default task review; same $2/$10 as Sonnet 5; default effort `high` |
| Haiku | Haiku 5.5 (Haiku 4.5 still served) | `claude-haiku-5-5` | mechanical implementers, scoped re-review; $0.10/$0.50 up to 100K prompt tokens, $0.50/$2.50 beyond; 1M context; default effort `medium` |
