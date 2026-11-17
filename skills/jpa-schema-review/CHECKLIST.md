# JPA Schema Review Checklist

Seven categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). Name the
consequence: "this is wrong" without "because X breaks" is not a finding.

Three kinds of file: an entity (`@Entity`, `@MappedSuperclass`,
`@Embeddable`), a Spring Data repository or specification, and a SQL
migration. §1–§3 are for entities, §4 for repositories, §5–§6 for migrations,
§7 for all three. Skip what does not apply and say so in one line.

## Before you start

### Version baseline

```bash
grep -rhoE "(springBootPlugin|org.springframework.boot'? version|hibernate[A-Za-z.-]*|flyway[A-Za-z.-]*|postgresql|hypersistence[A-Za-z0-9.-]*)[^,;]*" \
  build.gradle* gradle.properties pom.xml gradle/libs.versions.toml 2>/dev/null | sort -u
```

| Version | What changes |
| --- | --- |
| Hibernate 5 (Boot 2) | `javax.persistence`, `@TypeDef`, one `hibernate_sequence`. Skip the Hibernate 6 rules. |
| Hibernate 6.0+ (Boot 3) | `jakarta.persistence`. A sequence generator with no name uses `<entity>_seq` with an increment of 50: the migration must create exactly that. `@TypeDef` is gone. `select distinct` is no longer needed with `join fetch`. |
| Hibernate 6.2 | `OffsetDateTime` / `ZonedDateTime` map to `timestamp with time zone`. An optional one-to-one gets a unique constraint. |
| PostgreSQL | The lock rules in §6 are PostgreSQL's. Another engine has others: say so and apply §5 only. |

### Settings

`bash scripts/inventory.sh` prints them. Three change the rules:

- `spring.jpa.open-in-view` — when not set to `false` it is **on**: a lazy
  field read in a controller or during serialization works, and holds the
  connection while it does. When `false`, the same read throws.
- `spring.jpa.hibernate.ddl-auto` — with migrations, only `none` or
  `validate`. `update` or `create` beside Flyway is a 🔴 on the config file.
- Where the migrations live and how they are numbered — follow the directory.

## Severity floor

Always 🔴, regardless of effort:

- a versioned migration that was already merged is edited, renamed or deleted
- a migration that drops or renames a column or table the running version
  still reads, in the same release as the code change
- a query built by string concatenation with a value from a caller
- an entity change with no migration, or a migration the entity does not match
- `CascadeType.REMOVE` or `ALL` on a to-one or many-to-many association

## 1. Associations and fetching

- **[hard] Every `@ManyToOne` and `@OneToOne` says `fetch = FetchType.LAZY`.**
  The default is EAGER: one more select per row for every JPQL or criteria
  query, and no query can turn it off.
- **[hard] No `FetchType.EAGER`** on any association. The query that needs
  the data fetches it: `join fetch`, `@EntityGraph`, a projection.
- **[hard] A bidirectional association is kept in step on both sides.** The
  owning side is the one without `mappedBy`; setting only the inverse side
  saves nothing. A parent has `add…` / `remove…` methods that set both.
- **[hard] `cascade` goes from parent to child only.** `ALL` or `REMOVE` on a
  `@ManyToOne` or `@ManyToMany` deletes a row other rows share. Always 🔴.
- **[hard] `orphanRemoval = true` only where the parent owns the child's
  whole life.** Replacing the collection instance, in place of clearing and
  refilling it, makes Hibernate fail or delete every child.
- **[hard] A collection field is initialised** (`new ArrayList<>()`,
  `new HashSet<>()`) and never replaced by an unmodifiable one
  (`List.of`, `stream.toList()`).
- **[prefer] `@ManyToMany` is a `Set`.** On a `List`, removing one element
  deletes and re-inserts the whole join table.
- **[context] Two `List` collections fetched in one query** fail with
  `MultipleBagFetchException`; turning them into `Set`s gives a Cartesian
  product instead. Fetch one collection per query.
- **[context] A foreign key held as a plain id column** beside, or in place
  of, an association is a project convention: follow the siblings and do not
  mix both styles for one column without `insertable = false, updatable =
  false` on one of them.

## 2. Identity, equality and Lombok

- **[hard] No `@Data`, `@EqualsAndHashCode` or `@Value` on an entity.**
  Equality over every field changes when the id is generated, so the entity
  is lost in a `HashSet`; it also reads lazy associations. `@Getter` and
  `@Setter` only.
- **[hard] `@ToString` excludes associations.** It loads them, throws outside
  a transaction, or recurses on a bidirectional pair.
- **[hard] `equals` and `hashCode`, when written, follow the project's one
  pattern.** The safe one: equal when the ids are equal and not null;
  `hashCode` is a constant per class. Equality on mutable columns or on
  timestamps is a defect: two new rows are equal, one edited row is not equal
  to itself.
- **[hard] The id strategy matches the siblings and the migration.** A
  sequence name and increment in the mapping are the ones the migration
  creates. `GenerationType.AUTO` leaves the choice to the dialect.
- **[context] `@Version`** — an aggregate that two users can edit at once has
  no protection from a lost update without it. Report it when the diff adds
  such an edit path, not on every entity.

## 3. Column mapping

- **[hard] `@Enumerated(EnumType.STRING)` on every enum.** The default stores
  the ordinal: adding or moving a constant changes the meaning of old rows.
- **[hard] An instant is `Instant` or `OffsetDateTime`** on a
  `timestamp with time zone` column. `LocalDateTime` on `timestamp` takes the
  server's zone. A date with no time is `LocalDate`. No `java.util.Date`.
- **[hard] Money and exact quantities are `BigDecimal`** with `precision` and
  `scale`, or integer minor units. Never `double` or `float`.
- **[hard] The mapping matches the column** — name, `nullable`, `length`,
  `unique`, schema — as the migration in the same diff defines it. With
  `ddl-auto: none` nothing checks this until the first query.
- **[prefer] Table, schema and column names come from where the siblings take
  them** (a constants class, a naming strategy), not from a new literal.
- **[prefer] Audit columns use the project's base class or listener**, not a
  hand-set timestamp.
- **[context] `@Column(updatable = false)` / `insertable = false`** on a
  column the service then sets: the write is dropped without an error.

## 4. Repositories and queries

- **[hard] Every value reaches a query as a bound parameter.** No string
  concatenation in `@Query`, `createQuery`, `createNativeQuery`, no
  `JpaSort.unsafe` with caller input. Always 🔴. A `like` pattern from a
  caller is escaped.
- **[hard] A collection fetch is not paged.** `join fetch` or `@EntityGraph`
  of a collection with a `Pageable` makes Hibernate read every row and page
  in memory. Page the ids, then fetch by id.
- **[hard] `@Modifying` says what happens to loaded entities.** A bulk update
  or delete does not touch the persistence context: entities already loaded
  keep the old values. `clearAutomatically = true` drops them — and drops
  unflushed changes with them unless `flushAutomatically = true` is also set.
- **[hard] A writing `@Query` has `@Modifying`**, and runs in a transaction
  from the calling service. A query method declared on a repository gets no
  transaction of its own.
- **[hard] A bulk `@Query` delete skips cascades and entity callbacks.** The
  children stay, or a foreign key fails. A derived `deleteBy…` does the
  opposite: it loads every row and deletes one by one.
- **[hard] A paged native query has a `countQuery`.**
- **[hard] A list method that can grow takes a `Pageable`** or is bounded by
  its `where` clause to one parent. `findAll()` on a table that grows is a
  finding in the caller.
- **[prefer] Select what is read.** A screen that shows three columns uses a
  projection, not the entity graph.
- **[prefer] An existence check is `existsBy…`.**
- **[prefer] JPQL before native SQL.** A native query is not checked against
  the mapping and breaks at run time on a rename; keep it for what JPQL
  cannot say, and qualify it with the schema as the siblings do.
- **[hard] A new query for "what the caller may see" uses the project's
  security specification**, not its own `where`.
- **[context] A specification that fetches** (`root.fetch`) breaks the count
  query of `findAll(spec, pageable)`; guard it on the query's result type.
- **[context] A derived method name** names properties that exist on the
  entity, spelled as the field is. A wrong name fails at startup, not at
  compile time.

## 5. Migrations — history

- **[hard] A versioned migration that is merged is never edited, renamed or
  deleted.** Every environment that applied it fails checksum validation at
  startup. The fix is a new migration. Always 🔴.
- **[hard] The file name follows the directory**: prefix, version format,
  double underscore, description. The version is the next free one; two
  branches that both took it collide.
- **[hard] One migration, one change.** A backfill, an index and a constraint
  in one file run in one transaction and fail together.
- **[hard] The schema change and the entity change are in the same diff and
  agree.** An entity field with no column fails at the first query; a
  `NOT NULL` column with no field fails at the first insert.
- **[hard] `ddl-auto` stays `none` or `validate`.**
- **[prefer] The object is qualified with its schema** as the siblings do.
- **[context] Data in a versioned migration** — a backfill is fine; a fix for
  one environment's rows is not, since it runs on all of them.

## 6. Migrations — locks and compatibility

PostgreSQL. A table that is small today is judged by what it will hold.

- **[hard] A change the running version cannot live with is split over two
  releases.** Old instances run against the new schema during a deploy and
  after a rollback. Dropping or renaming a column, a table or an enum value,
  or adding a `NOT NULL` column the old code does not write, breaks them.
  First release: add, and make the code stop using the old shape. Second:
  remove. Always 🔴 when both land together. Search the base of the diff for
  the name before judging, and say what the search found.
- **[hard] `CREATE INDEX` on an existing table is `CONCURRENTLY`.** Without
  it, writes wait until the build ends. `CONCURRENTLY` cannot run inside a
  transaction, so the statement goes in its own migration, marked the way the
  project marks a non-transactional one. A failed build leaves an invalid
  index to drop.
- **[hard] `ADD COLUMN … NOT NULL` has a `DEFAULT`**, or it fails on a table
  with rows. A constant default is cheap. A volatile one (`gen_random_uuid()`,
  `clock_timestamp()`, `random()`) rewrites the whole table under an
  exclusive lock.
- **[hard] `SET NOT NULL` on an existing column scans the table** under an
  exclusive lock. On a large table, add `CHECK (col IS NOT NULL) NOT VALID`,
  validate it, then set not null.
- **[hard] A foreign key or a check is added `NOT VALID`, then validated** in
  a second statement. Added in one step it reads every row while writes are
  blocked.
- **[hard] `ALTER COLUMN … TYPE` rewrites the table** unless the change is
  binary-compatible. Add a column, backfill, switch.
- **[hard] `UPDATE` / `DELETE` with no `WHERE`, or over a large table, is
  batched** or proven small. One statement holds its locks until the
  migration ends.
- **[prefer] `timestamptz`, not `timestamp`; `text` or a justified
  `varchar(n)`; an identity column, not `serial`; never `money`.**
- **[prefer] A new foreign-key column has an index** when the parent is
  deleted or the column is filtered on.

## 7. Structure, tests and comments

- **[hard] Reinvention** — a second base entity, converter, specification,
  projection or constants entry for something the model module already has.
  **Run `scripts/inventory.sh` before judging this.** Name the existing one.
- **[hard] A new query has a test against the real database** through the
  project's container setup: a native query, a specification, a `@Modifying`
  statement, a constraint. A mocked repository proves nothing about SQL.
- **[hard] A migration is exercised** by the project's migration or schema
  test when it has one.
- **[hard] Comments** — no restating of the mapping, no commented-out
  columns, no ticket or date. One line stays when it says why a mapping is
  not the obvious one: a deliberate EAGER, a native query, a missing foreign
  key.

---

## Do NOT report

- A pre-existing mapping the change did not touch, however wrong.
- Replacing the project's id, audit or equality convention with a better one.
  Follow the majority `scripts/inventory.sh` shows; say once if the majority
  itself is a defect.
- A missing `@Version` on an entity the diff does not make concurrently
  editable.
- A lock rule on a table the diff creates in the same migration.
- Moving to another migration tool, another mapper, records, or a newer
  Hibernate.
- A speculative failure. Name the query or the statement that makes it real.
