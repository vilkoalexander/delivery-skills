# Phase 0: from a problem to a plan

Read when the human gives a problem or a feature and there is no approved plan
file.

A run needs an approved plan. If the human did not help to make the plan, the
design questions come in the middle of the run. There, each answer costs a
chunk.

1. **Do not start the run.** Do not run `run.sh start`. Nothing is built in
   this phase.
2. **Get the problem, not the solution.** If the human gave only a solution,
   ask what is wrong today and for whom.
3. **Read the language of the project.** Read `GLOSSARY.md` and `docs/adr/`,
   if they exist. Use their terms in each question.
4. **Grill.** Invoke `mattpocock-skills:grilling` and
   `mattpocock-skills:domain-modeling`. If they are not available, obey the
   rules of section 2 of `references/plan.md` and these rules:
   - If two words name one thing, or one word names two things, stop and get
     the term from the human. Write it in `GLOSSARY.md` immediately.
   - Test a new term with scenarios: write three sentences that a person will
     say about the feature, with each candidate term.
   - If the stack or a known library solves the problem, recommend that
     solution first. Recommend a hand-made solution only when you can say why
     the usual one does not fit.
   - A decision gets an ADR in `docs/adr/` when it is hard to reverse, when it
     surprises a reader who was not here, and when a real alternative lost.
     Ask before you write one.
   - For a question about how something looks or feels, offer a prototype
     with two or three variants (`mattpocock-skills:prototype`). Do not ask
     the human to imagine it.
5. **The human ends the grilling.** It ends when the human says `plan`. Each
   question that is open at that time becomes an `Assumed:` line in the plan.
6. **Write the plan.** Use `superpowers:writing-plans`. The plan uses the
   terms of the glossary. Each task has acceptance criteria that a verifier
   can exercise.
7. **Wait for the approval of the plan file.** Then do the preflight.

The questions of phase 2 stay. After this phase, they are only about what the
plan itself opened: order, cut, limits and error paths.
