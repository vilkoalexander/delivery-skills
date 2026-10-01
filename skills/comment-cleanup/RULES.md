# Comment rules

The one rule this plugin holds for code comments. `comment-cleanup` applies it
to code that already exists. The Global Constraints block in
`delivery-pipeline` and the comment section of the review checklists carry the
same rule in their own form; a rule that changes here changes there in the
same change set.

The default is no comment. A rename, an extracted function or a type comes
first; a comment is what is left when none of those can say it.

The test: delete it in your head. If the next editor would neither break
something nor lose an hour, it goes.

## A comment that stays

One line, and one of four kinds.

| Kind | Reads like |
| --- | --- |
| Why this and not the obvious alternative | `// sorted here: the API returns insertion order, not date order` |
| A constraint from outside the code | `// the provider rejects batches over 500` |
| A warning about what breaks if edited | `// must run before hydrate(), which reads this ref` |
| A workaround, with its removal condition | `// Android drops the first focus event; remove once the picker is native` |

## Declarations

A constant or an interface field carries a comment only for what its name and
type cannot say: units, where a number comes from, a domain term, what null or
empty means, an invariant between fields. `timeoutMs` needs no comment;
`timeout // ms` needs a rename.

## Boundaries

An exported function in a shared package says what its caller cannot see in
the signature: side effects, what it throws, ordering, idempotency. This holds
in a project that already documents its exports; it does not start one.

## A comment that goes

- Restates the code, the name or the type.
- Describes the change instead of the code: "now uses", "added", "fixed",
  "no longer", "previously".
- Names the outside world: a ticket, PR, SHA, date, author or link. The code
  does not know them; they live in commit messages.
- Talks to a plan or a reviewer: "as requested", "per task 3".
- A banner, a divider, a step number.
- Commented-out code. Git remembers it.
- JSDoc that repeats the TypeScript types or the parameter names.

## Never touched

A comment a tool reads is code, and a cleanup leaves it alone:

- Suppressions and directives: `eslint-disable*`, `@ts-expect-error`,
  `@ts-ignore`, `@ts-nocheck`, `prettier-ignore`, coverage `ignore` markers,
  bundler magic comments, `/// <reference`, test-environment pragmas, a
  shebang. A suppression states its reason; one that does not is reported,
  never guessed at.
- Licence and copyright headers.
- JSDoc tags tooling acts on: `@deprecated`, `@internal`, `@public`, and
  `@type` / `@param {…}` in a `.js` file under `checkJs`.
- Prisma `///` comments, which are generated into the client.
- `TODO` / `FIXME`. They track work; they are listed, not judged.
- Generated, vendored and snapshot files.

When writing new code, an existing comment the change did not need to touch
stays as it is. One the change made false is fixed in the same change.
