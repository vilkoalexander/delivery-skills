# Sources

References behind `CHECKLIST.md`. Not loaded during a review.

- [Prisma — Transactions and batch queries](https://www.prisma.io/docs/orm/prisma-client/queries/transactions) — interactive transaction timeout / maxWait, isolation levels, lock duration
- [Prisma discussion #25922 — transaction deadlocks and timeouts](https://github.com/prisma/prisma/discussions/25922) — the `this.prisma`-inside-`tx` hang
- [NestJS — Testing](https://docs.nestjs.com/fundamentals/testing) — `overrideGuard`, `createTestingModule`
- [Prisma — Unit testing](https://www.prisma.io/docs/orm/prisma-client/testing/unit-testing) — mocking the client by injection
- [typescript-eslint — no-floating-promises](https://typescript-eslint.io/rules/no-floating-promises/) — requires type information (`parserOptions.project`)
