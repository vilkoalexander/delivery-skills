# API Contract Review Checklist

Six categories. Walk them in order. Each rule is tagged **[hard]**,
**[prefer]** or **[context]** — see SKILL.md. Every finding names which side
breaks: **new server + old client**, or **old server + new client**.

## 1. Backward compatibility with installed clients

The compatibility matrix, for a response schema:

| Change | New server + old client | Old server + new client |
| --- | --- | --- |
| Add an optional field | fine — old client ignores it | fine if the client treats it as optional |
| Add a required field | fine | **breaks** — server never sends it |
| Remove / rename a field | **breaks** — old client reads `undefined` | fine |
| Widen an enum | **breaks** — old client hits an unknown member | fine |
| Narrow an enum | fine | **breaks** |
| `nullable()` → required | fine | **breaks** |
| required → `nullable()` | **breaks** — old client assumes present | fine |
| Change a type (`string` → `number`) | **breaks** both ways | |

- **[hard] A removed or renamed response field is a 🔴.** Deprecate by keeping
  it and stopping writing to it; delete it a release after the floor build is
  gone.
- **[hard] Widening a response enum is a 🔴 unless every client already has a
  fallback branch.** Check the consumers — a `switch` with a `default`
  survives it; an exhaustive map does not.
- **[hard] A new required request field is a 🔴** — old clients do not send
  it, so every call from an installed build 400s.
- **[prefer] Add optional, backfill, then tighten** — the same expand/contract
  shape as a database migration, across two client releases.
- **[context] "Nobody has that build"** is a real argument, but it has to be
  stated, not assumed. Say which builds are in the field.

## 2. The contract chain

One source of truth, derived outward. The project layer names the packages;
the generic shape is schema → DTO (server validation + docs) → inferred type
(all consumers).

- **[hard] A new schema needs its inferred type** and, if it is a request or
  response shape, its DTO. A schema with no type is invisible to consumers.
- **[hard] Never hand-write an interface that mirrors a schema.** Use
  `z.infer<typeof xSchema>`. A hand-written twin drifts silently the first
  time the schema changes.
- **[hard] Every new export is added to the package's barrel.** The barrel is
  the public surface; an unexported symbol is unreachable.
- **[hard] Response types come from the types package, request DTOs from the
  DTO package.** A controller importing a schema directly bypasses the DTO
  layer that produces the API docs.
- **[prefer] One file per entity**, named consistently across the chain.

## 3. Schema correctness

- **[hard] Request schemas are `.strict()`.** Without it, an unknown key is
  silently dropped and the caller believes it was accepted. Note the
  consequence: a NEW client sending a field an OLD server does not know is a
  400, so a request field must reach production before the client ships it.
- **[hard] Response schemas are NOT `.strict()`** — they are serialization
  contracts, and the serializer already strips unknown keys.
- **[hard] A response schema must accept everything the database can
  produce.** A value the column allows but the schema rejects is a 500 at
  serialization time, not a validation error the client can act on.
- **[prefer] Split create-time and response enums** when the server owns a
  terminal state the client may never set.
- **[hard] Money fields are `z.number().int()` and bounded** by the column's
  ceiling (`PG_INT_MAX` for a Postgres `Int`). An unbounded integer passes zod
  and overflows the column as an unmapped 500.
- **[hard] Currency uses the shared currency schema**, never a copy-pasted
  regex.
- **[prefer] Canonicalise at the input boundary** — `.trim()`,
  `.toLowerCase()` on email, `.toUpperCase()` on a user-typed code. The
  database unique constraint is case-sensitive; the schema is where that is
  fixed.
- **[prefer] A partial-update schema requires at least one field** via
  `.refine(...)`, or an empty PATCH silently succeeds.
- **[context] Do not cap `limit` in the schema** when the service clamps it —
  an old client asking for 200 gets 100 rather than a 400. Check the project
  layer; this is a deliberate decision in many codebases.

## 4. Dependency direction

- **[hard] Packages that reach a client bundle carry nothing backend-only**:
  no `@nestjs/*`, no `@prisma/client`, no `node:` builtins (`fs`, `path`,
  `crypto`, `buffer`). The bundler will fail, or worse, ship a shim that
  misbehaves at runtime.
- **[hard] The DTO package is backend-only** — it depends on the server
  framework. A client app must never import it. Often nothing in lint
  prevents this.
- **[hard] `test-utils` is test-only** and may reach the database client. It
  must never be imported from application code.
- **[hard] One validation-library entry point.** All zod imports from the
  `'zod'` root (or all from `zod/v4` — not both). Mixing splits the type
  system.
- **[prefer] Shared packages stay dependency-light.** A new runtime dependency
  in a client-consumed package is a new dependency in the app bundle; say what
  it costs.

## 5. Database alignment

- **[hard] Every schema enum that mirrors a database enum covers every value
  the database can produce.** These are hand-mirrored — nothing enforces it.
  `scripts/inventory.sh` runs the cross-check when a Prisma schema exists.
- **[hard] A database enum gaining a value is a contract change**: the
  response schema must accept it before any row can carry it, or serialization
  500s.
- **[prefer] Nullability matches the column.** A nullable column maps to
  `.nullable()`, not `.optional()` — the API sends `null`, not absence.
- **[prefer] Timestamps are `z.string().datetime()`** in responses; the
  service maps `Date → toISOString()` at the boundary. A raw `Date` in a
  response type is a serialization bug waiting for a client that parses
  strictly.
- **[context] The schema layer does not enforce tenant rules.** A tenant key
  appears in responses but must never be accepted in a request body — that is
  a service rule, but a request schema that adds it is where it starts.

## 6. Hygiene

- **[hard] No generator stubs.** A scaffolded `export function <lib>(): string
  { return '<lib>'; }` and its `it('should work')` spec are not code. In a
  client-consumed package they also ship.
- **[prefer] Every exported symbol has a why-comment** when its behaviour is
  non-obvious — the currency schema and the integer ceiling each explain the
  failure they prevent.
- **[context] Import extensions match the project's module resolution.** A
  `.js` suffix on a relative import is required under `nodenext` and breaks
  Metro / jest under `bundler`. Check `tsconfig.base.json` before flagging
  either way.
- **[prefer] A shared util is used by 2+ consumers.** A single-consumer helper
  belongs in that app.
- **[hard] Nothing user-facing is hardcoded in English here** — copy belongs
  to the client's i18n layer or the server's messages, not a shared package.

---

## Sources

- [Zod — versioning](https://zod.dev/v4/versioning) and [zod#4371](https://github.com/colinhacks/zod/issues/4371) — Zod 4 ships at the `zod/v4` subpath alongside 3.25
- [Zod — for library authors](https://zod.dev/library-authors) — subpath discipline
- [nestjs-zod MIGRATION.md](https://github.com/BenLorantfy/nestjs-zod/blob/main/MIGRATION.md) — Zod 4 support lands in v5
- [Nx — enforce-module-boundaries](https://nx.dev/nx-api/eslint-plugin/documents/enforce-module-boundaries) — the gate that would make §4 permanent
