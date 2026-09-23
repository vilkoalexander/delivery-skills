# Sources

References behind `CHECKLIST.md`. Not loaded during a review.

- [Prisma — Relations: referential actions](https://www.prisma.io/docs/orm/prisma-schema/data-model/relations/referential-actions) — `onDelete` defaults per provider
- [Prisma — Migrations: customizing migrations](https://www.prisma.io/docs/orm/prisma-migrate/workflows/customizing-migrations) — expand/contract, why applied migrations are immutable
- [PostgreSQL — ALTER TYPE](https://www.postgresql.org/docs/current/sql-altertype.html) — enum values unusable before the adding transaction commits
- [PostgreSQL — ALTER TABLE notes](https://www.postgresql.org/docs/current/sql-altertable.html) — `ADD COLUMN DEFAULT` without rewrite on 11+, `SET NOT NULL` full-table scan
