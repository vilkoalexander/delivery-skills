# JPA schema review — project layer

Loaded by `jpa-schema-review` at step 2. Also the source for the scan env:
`MIGRATION_BASE=<develop>` `MIGRATION_NAME='<leave unset for Flyway names>'`.
Everything in `<angle brackets>` is a placeholder — replace it or delete the row.

## Database and migrations

- Engine: `<PostgreSQL 17>`. Schemas: `<public, users, crm, security>`, named in `<Constants>`.
- Migrations: `<application/src/main/resources/db/migration>`, named `<V1.NNN__snake_case.sql>`, next number = last + 1.
- A non-transactional migration (concurrent index) is marked by: `<a V1.NNN__x.sql.conf beside it with executeInTransaction=false>`.
- `ddl-auto`: `<none>`. `open-in-view`: `<false>`.
- Deploy: `<rolling — two versions run at once | stop and start — one version at a time>`.
- A merged migration is one on: `<develop | master>`.

## Entity conventions

- Base class: `<BaseEntity (created, updated)>`. Audit: `<@CreationTimestamp, @UpdateTimestamp, @CreatedBy>`.
- Id: `<UUID with @GeneratedValue | identity for <tables>>`.
- Lombok: `<@Getter @Setter only>`. Equality: `<id-based, see <Entity>.java | not overridden>`.
- Associations: `<object reference, LAZY | plain id column plus a read-only reference>`.
- Enums: `<@Enumerated(EnumType.STRING), a PostgreSQL enum type for <columns>>`.
- Time: `<Instant on timestamptz; LocalDate for a date>`.
- JSON and array columns: `<hypersistence JsonType>`.

## Reference implementations

| Concern | Read |
| --- | --- |
| Entity with a parent and children | `<model/.../UnitEntity.java>` |
| Repository with a fetch plan | `<model/.../UnitGroupRepository.java>` |
| Bulk update | `<model/.../XRepository.java>` |
| Specification | `<model/.../spec/UnitGroupSpecification.java>` |
| Migration that adds a table | `<db/migration/V1.057__services.sql>` |
| Backfill migration | `<db/migration/V1.054__backfill_x.sql>` |
| Schema test | `<application/.../ServiceSchemaTest.java>` |

## Shared primitives — do not rebuild

| The file hand-rolls… | Use |
| --- | --- |
| "Rows the caller may see" | `<SecuritySpecification.applySecurity(...)>` |
| A filter predicate | `<AbstractSpecification helpers>` |
| A table or schema literal | `<Constants.TABLE_X, SCHEMA_X>` |
| A list projection | `<XProjection>` |

## Large or hot tables

`<users.unit_member, users.enrollment>` — a lock rule on these is 🔴.

## Known ceilings — do not recommend past these

- `<ACL views are read-only entities with no migration of their own>`
- `<one ceiling per line, stated as a rule a reviewer can check>`

## Deferred — never propose as gaps

`<@Version on every aggregate, moving to MapStruct, …>`
