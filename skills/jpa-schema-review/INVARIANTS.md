# Persistence Invariants

The generic non-negotiables. `scripts/inventory.sh` is authoritative for what
currently exists; the project layer (`docs/review/jpa-schema-review.md`) names
the project's own conventions, reference files and ceilings.
`templates/jpa-schema-review.md` in this repository is a starting point.

## The schema has one owner

The migrations own the schema. The entities describe it; they never create
it. So every change is two edits that must agree: a new migration and the
mapping. `ddl-auto` is `none` or `validate`. A migration that was merged is
history: it is corrected by the next one, never by an edit.

## Two versions run at once

During a deploy, and after a rollback, the previous version of the code runs
against the new schema. A migration is safe when the previous version still
works after it.

| Change | Safe in one release |
| --- | --- |
| Add a table, a nullable column, a column with a constant default | yes |
| Add an index concurrently, a constraint `NOT VALID` | yes |
| Add a `NOT NULL` column the old code does not write | no — add nullable or with a default first |
| Rename a column or table | no — add, write both, switch reads, drop |
| Drop a column or table the old code reads | no — stop using it first, drop next release |
| Narrow a type, add a check the old code can violate | no |

## What the persistence context does

- An entity loaded in a transaction is written at commit without a `save()`.
- A bulk `@Query` update or delete goes straight to the database. Loaded
  entities do not see it, cascades and callbacks do not run.
- Outside the transaction an entity is detached: a lazy field throws unless
  open-in-view keeps the session, and then the connection stays held.
- A to-one association is EAGER unless the mapping says LAZY.

## What the project layer must say

| Question | Why the review needs it |
| --- | --- |
| Where migrations live, the version format, how a non-transactional one is marked | So §5 can check a name and §6 can accept a concurrent index |
| The deploy model: rolling, or stop-and-start | Decides how strict the two-release rule is |
| Base entity, audit columns, id strategy, equality pattern | The conventions a new entity follows |
| Association style: object reference, plain id column, or both | Otherwise one of them is reported on every entity |
| Schemas and where their names come from | So a literal can be named a finding |
| The security specification and other shared specifications | "Do not rebuild" needs real names |
| Tables that are large or hot | Where the lock rules are 🔴 and not 🟡 |
| The schema or migration test | So §7 can require it |
| Known ceilings and deferred changes | So the review never recommends past them |

## Shared primitives — the generic shapes

| The file hand-rolls… | Expect the project to have |
| --- | --- |
| `created` / `updated` columns | a base entity or an auditing listener |
| A `where` for "rows the caller may see" | a security specification |
| A table or schema name as a literal | a constants class |
| A JSON or array column mapping | a registered type or converter |
| A projection interface for a list | an existing projection or DTO constructor query |
| A container and a schema in a repository test | a test base class |

If the project has none of these, the finding is "this should be the first
one" — once. Not on every file.

## Known ceilings — do not recommend past these

- **A collection fetch cannot be paged in the database.** Two queries, or a
  projection. A larger page is not a fix.
- **`CREATE INDEX CONCURRENTLY` cannot share a transaction** with anything.
  It is its own migration.
- **A bulk statement cannot keep loaded entities in step.** Clear the
  context, or do not load them first.
- **Checksum validation cannot be argued with.** An edited migration fails on
  every environment that ran the old text; `repair` hides the difference, it
  does not apply it.
- **Equality on a generated id is unstable before the row is saved.** The
  constant `hashCode` is the price of a correct `equals`.
