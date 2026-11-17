# Models

Read when the run is long, when you substitute a model, or when cost is a
concern. The role table in `SKILL.md` uses the short names, and the short
names always go to the current generation.

## Substitutions

Apply these in order.

1. **Long run.** If the run has more than six chunks, or the context will
   become larger than Opus holds, put the controller on Fable 5.2. It has a
   1M context and always uses extended thought. A shorter run stays on
   Opus 5.5: the code quality is the same and the price is half.
2. **Effort.** Opus 5.5 and Haiku 5.5 have `medium` effort as the default.
   Sonnet 5.5 and Fable 5.2 have `high`. Effort comes from the agent
   definition, not from the Agent call. For this reason the reviewer seat and
   the high-risk implementer seat have a definition.
3. **Cost.** Lower the effort of a role before you lower its model. In the
   Claude 5 family, a cheaper model at high effort is usually worse than the
   same model at lower effort. Implementers and re-reviews work at low or
   medium effort. Reviewers stay at high.
4. **A new family member.** The short names go to it automatically. Compare
   the role table with the lineup below again.

## Lineup (9 November 2026)

The generation that the role table was written for.

| Family | Current | API ID | Tier |
| --- | --- | --- | --- |
| Fable | Fable 5.2 (Fable 5.1 still served) | `claude-fable-5-2` | most capable; $8/$40; 1M context; thinking always on; default effort `high`; cache reads $0.20/MTok |
| Opus | Opus 5.5 (Opus 5 and 4.8 still served) | `claude-opus-5-5` | one-way doors, final review, high-risk review; default effort `medium`; cache reads $0.20/MTok |
| Sonnet | Sonnet 5.5, released 28 September 2026 (Sonnet 5 still served) | `claude-sonnet-5-5` | default task review; same $2/$10 as Sonnet 5; default effort `high` |
| Haiku | Haiku 5.5 (Haiku 4.5 still served) | `claude-haiku-5-5` | mechanical implementers, scoped re-review; $0.10/$0.50 up to 100K prompt tokens, $0.50/$2.50 beyond; 1M context; default effort `medium` |
