# Sources

References behind `CHECKLIST.md`. Not loaded during a review.

- [Vlad Mihalcea — EAGER fetching is a code smell](https://vladmihalcea.com/eager-fetching-is-a-code-smell/) — the to-one default, one select per row
- [Vlad Mihalcea — HHH000104, fetch with pagination](https://vladmihalcea.com/fix-hibernate-hhh000104-entity-fetch-pagination-warning-message/) — paging in memory, the two-query fix
- [Vlad Mihalcea — MultipleBagFetchException](https://vladmihalcea.com/hibernate-multiplebagfetchexception/) — two lists, the Cartesian product with sets
- [Vlad Mihalcea — equals, hashCode and toString](https://vladmihalcea.com/the-best-way-to-implement-equals-hashcode-and-tostring-with-jpa-and-hibernate/) — id equality, constant hash
- [Vlad Mihalcea — synchronize bidirectional associations](https://vladmihalcea.com/jpa-hibernate-synchronize-bidirectional-entity-associations/)
- [Vlad Mihalcea — Open Session in View](https://vladmihalcea.com/the-open-session-in-view-anti-pattern/), [the best Spring Data JpaRepository](https://vladmihalcea.com/best-spring-data-jparepository/), [exists query](https://vladmihalcea.com/spring-data-exists-query/)
- [Thorben Janssen — Lombok and Hibernate](https://thorben-janssen.com/lombok-hibernate-how-to-avoid-common-pitfalls/) — `@Data`, `@ToString`, `@EqualsAndHashCode` on an entity
- [Hibernate 6.0 migration guide](https://docs.hibernate.org/orm/6.0/migration-guide/migration-guide.html) and [6.2 migration guide](https://docs.hibernate.org/orm/6.2/migration-guide/migration-guide.html) — `<entity>_seq`, removed `@TypeDef`, time-zone storage, the one-to-one unique constraint
- [Hibernate 6.2 user guide](https://docs.hibernate.org/orm/6.2/userguide/html_single/Hibernate_User_Guide.html) — enum mapping
- [Spring Data JPA — Query methods](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html) — `@Modifying`, `clearAutomatically`, derived deletes, count queries, sorting
- [Spring Data JPA — Transactionality](https://docs.spring.io/spring-data/jpa/reference/jpa/transactions.html) — a declared query method gets no transaction configuration
- [Spring Boot 3.1 — Data](https://docs.spring.io/spring-boot/docs/3.1.x/reference/html/data.html) and [How-to](https://docs.spring.io/spring-boot/docs/3.1.x/reference/html/howto.html) — open-in-view default, `ddl-auto` defaults, Flyway naming
- [Flyway — Migrations](https://documentation.red-gate.com/fd/migrations-271585107.html) and [Validate](https://documentation.red-gate.com/fd/validate-277578898.html) — one transaction per script, checksums
- [PostgreSQL — CREATE INDEX](https://www.postgresql.org/docs/current/sql-createindex.html) — `CONCURRENTLY`, no transaction block, invalid indexes
- [PostgreSQL — ALTER TABLE](https://www.postgresql.org/docs/current/sql-altertable.html) — lock levels, rewrites, `NOT VALID` and `VALIDATE CONSTRAINT`, `SET NOT NULL` with a check
- [PostgreSQL wiki — Don't Do This](https://wiki.postgresql.org/wiki/Don%27t_Do_This) — `timestamp`, `money`, `serial`, `char(n)`
- [OWASP — Query parameterization](https://cheatsheetseries.owasp.org/cheatsheets/Query_Parameterization_Cheat_Sheet.html)

Not confirmed from a primary page, stated in the checklist on practitioner
consensus: `flushAutomatically`; the cascade rule for to-one and many-to-many;
the count-query failure of a fetching specification; the expand-and-contract
rule for two running versions.
