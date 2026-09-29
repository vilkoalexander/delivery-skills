---
name: react-screen-authoring
description: Read BEFORE generating a new screen, page, sheet, form or picker in a React or React Native app. Triggers on "add a screen", "new screen", "build the X page", "add a sheet / form / picker". Puts the container / view / builder split and the platform checklist in context before generation, because lint only catches the wrong shape after the file exists.
---

# React Screen Authoring

Lint runs after a file is written. By the time a line cap or an import ban
fails, the wrong shape is on disk and has to be undone. This skill is read
before the first line of a new screen, so the shape comes out right the first
time. It is the authoring side of `react-review`: that rubric judges a
finished component against the same split, this one produces it.

[CHECKLIST.md](CHECKLIST.md) is the contract: the roles, what each may and
may not import, the contracts a builder and a view keep, the file set a
screen creates, the platform checklist, and the lint that enforces all of it.

## Workflow

1. **Project layer.** `docs/review/react-screen-authoring.md` if the
   repository has one: the architecture doc, the path alias, the reference
   builder and spec, the test-id convention, the E2E runner, the lint and
   test commands. If it is absent, derive the same from `CLAUDE.md` /
   `AGENTS.md` and say so in one line.
2. **Inventory.** Run `../react-review/scripts/inventory.sh [src-dir]` and
   read `../react-review/INVENTORY.md` before writing any UI. Reinvention of
   a primitive, hook or util that already ships is the most common miss in
   generated screens.
3. **Route first.** Add the param-list entry to the navigation types before
   anything navigates to the screen.
4. **Builder + spec.** The derivations, as pure functions in `lib/`, with the
   spec beside them. Before any JSX.
5. **Form state**, only for a coupled form (one field's change affects
   another, or hydration must not overwrite a dirty draft): a pure reducer in
   `lib/` with its spec.
6. **View.** Props in, semantic callbacks out.
7. **Container.** Query hooks, screen-local state, the builders, the view.
8. **E2E flow** in the project's flow runner. Screens are not unit-tested;
   the flow is their coverage.
9. **Lint and tests green** with the project's commands before the screen is
   called done.

Scripts are shared with `react-review`; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/react-review/scripts/`.

## Exceptions

An effect that must stay in a screen or a feature component (a sheet's
reseed, a genuine external resync) takes a file-level `eslint-disable` with a
one-line why. Exceptions are counted, not forbidden. Do not contort a
component to avoid one when the honest shape needs an effect.

## Sibling

`react-review` reviews a finished component against the same table. A rule
that changes in one changes in the other in the same change set; the two
must never describe different shapes.
