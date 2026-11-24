---
name: spring-service-review
description: Use when asked to review a single Java Spring Boot backend file (a *Controller.java, *Service.java / *ServiceImpl.java, configuration, security filter, event listener, scheduled job or their *Test.java), check whether a Spring controller or service is okay, or sanity-check AI-generated Java or Spring code one file at a time. For a whole diff or PR, go through review-routing instead. For an entity, a repository or a Flyway migration, use jpa-schema-review.
---

# Spring Service Review

Structured review of ONE Java Spring backend file. Report and suggest — never
edit the file.

Most Spring projects build with `javac` and nothing else: no Error Prone, no
ArchUnit rules. So the transaction that never starts, the handler that checks
a role but not the object, and the remote call that holds a database
connection reach production unchallenged. That is what this review is for.

[CHECKLIST.md](CHECKLIST.md) is the rubric: version baseline, tooling
coverage, severity floor, the nine categories, and what not to report.
[INVARIANTS.md](INVARIANTS.md) is the generic non-negotiables. A diff review
reaches both through `review-routing` and never loads this file.

## Workflow

1. **Target.** One controller, service, configuration, filter, listener, job
   or test class. None given — ask which.
2. **Project layer.** INVARIANTS.md, then `docs/review/spring-service-review.md`
   if the repository has one: how handlers are authorized, shared primitives,
   reference implementations, ceilings, deferred features. If it is absent,
   derive the same from `CLAUDE.md` / `AGENTS.md` and say so in one line. Then
   the file under review, **its test** if one exists, and one sibling of the
   same kind as the consistency baseline.
3. **`scripts/inventory.sh [root]`** — versions, analyzers, modules,
   shared primitives, authorization expressions in use, test bases.
4. **`scripts/scan.sh <file>`** — mechanical pre-scan. Flags, not a verdict.
5. **Walk CHECKLIST.md** top to bottom.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/spring-service-review/scripts/`. `scan.sh` reads
`AUTHZ` (the annotations that authorize a handler; `""` for a project that
authorizes by URL) and `REMOTE_CALL` (calls that leave the process) from the
environment; the project layer says what to set.

## Effort

Default **medium**: 🔴 and 🟡 only, and **zero findings is a valid outcome**
— say so and stop. **high** adds ⚪ nits, still ranked. A short report of
real defects beats an exhaustive one.

## Output format

```
### <file> review

🔴 <file:line> — <one-sentence defect>
   why: <what breaks, concretely>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. One finding per defect: a line that is wrong for three
reasons is one finding with the worst reason first. Every finding names the
why. Before/after is the two lines that change. A clean category gets one
line.
