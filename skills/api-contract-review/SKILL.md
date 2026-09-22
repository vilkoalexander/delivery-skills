---
name: api-contract-review
description: Use when a shared contract package changes — a zod or other validation schema, a DTO, a shared TypeScript type, a field added to an API response — or when someone asks "will this break the app" or "is this backward compatible". For backend logic use nestjs-service-review, for the database use prisma-schema-review.
---

# API Contract Review

Structured review of ONE change to a shared contract package — the schemas,
DTOs and types that more than one app consumes. Report + suggest — never
edits the file.

The thing that makes this different from any other review: **a client on a
separate release train.** A backend deploy reaches users in minutes; a mobile
or desktop app reaches them when they take the update, which may be never. A
web SPA sits in between — cached bundles outlive the deploy by hours. Every
contract change is therefore evaluated twice — **new server + old client**,
and **old server + new client**.

## Workflow

1. **Identify the target.** A file under the shared contract package, or a
   diff of one. If none was given, ask which.
2. **Load the project layer** (do not skip):
   - [INVARIANTS.md](INVARIANTS.md) — the compatibility matrix and the
     generic chain.
   - `docs/review/api-contract-review.md` if the repository has one — the
     project's contract chain, which packages reach which bundle, the release
     trains, shared primitives and ceilings. If absent, derive the same from
     `CLAUDE.md` / `AGENTS.md` and the package graph, and say so in one line.
   - The file under review **and its whole chain**: a schema change implies
     the inferred type and, for a request/response shape, the DTO.
   - The consumers. `grep` for the exported symbol across every app before
     judging anything — a type with no consumer and a type with 40 are
     different changes.
3. **Run `scripts/inventory.sh [contract-dir]`** — the chain per entity, which
   apps consume which package, barrel gaps, and a Prisma ↔ schema enum drift
   check when a Prisma schema is present.
4. **Run `scripts/scan.sh <file-or-dir>`** — mechanical pre-scan.
5. **Walk [CHECKLIST.md](CHECKLIST.md)** — all 6 categories, in order.
6. **Emit the report** (format below).

Scripts live next to this file. Installed as a plugin, that is
`${CLAUDE_PLUGIN_ROOT}/skills/api-contract-review/scripts/`. `scan.sh` reads
`CLIENT_LIBS` (a `|`-separated list of package dir names that reach a client
bundle, default `schemas|types|utils`) from the environment.

## Effort scaling

Default **medium**. The user may say low / medium / high.

- **low / medium** — 🔴 and 🟡 only; roughly 7 findings. **Zero findings is a
  valid outcome.**
- **high** — add ⚪ nits, still ranked.

## Rule confidence

- **[hard]** — never correct. Always report.
- **[prefer]** — the right default. Report unless the file gives a reason.
- **[context]** — depends. Report only with a concrete consequence.

## Severity floor

Always 🔴, regardless of effort:

- a response field removed, renamed, or narrowed (nullable → required, wider
  enum → narrower) — installed clients parse it
- a request field made required, or a new required request field
- an import that pulls a backend-only dependency into a client-consumed
  package
- a response enum that no longer covers a value the database can produce

## Do NOT report

- Restating the project's instructions file as if it were a finding.
- Proposing API versioning (`/v2`, `Accept-Version`) when the project has
  not built it. Say "this is breaking" and let the human choose.
- Proposing a codegen pipeline when the chain is hand-written on purpose.
- Proposing a validation-library major upgrade the project has pinned
  against — check the project layer.
- Duplicating nestjs-service-review (tenant scoping, ledger rules) or
  prisma-schema-review (columns). This skill only owns the shared boundary.

## Tooling coverage

Do not assume. Check two things:

```bash
# 1. Does anything stop a client app importing a backend-only package?
grep -rn 'depConstraints\|enforce-module-boundaries' eslint.config.* .eslintrc* nx.json 2>/dev/null
# 2. Which client apps import which shared package?
grep -rhoE "@[a-z0-9-]+/(schemas|types|dto|utils|contracts|shared)[a-z/-]*" apps/*/src 2>/dev/null | sort | uniq -c
```

`tsc` catches a type that stops compiling. It cannot see that a field became
optional, that an enum lost a member, or that an installed client is parsing
the old shape. If nothing enforces the dependency direction, say so once and
name the gate that would (Nx project tags + `depConstraints`, or an ESLint
`no-restricted-imports` rule).

## Output format

Findings ranked most-severe first. Every finding names the WHY, and for a
contract the WHY names **which side breaks**.

```
### <file> review

🔴 <file:line> — <one-sentence defect>
   why: <which combination breaks and what the user sees>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

If a checklist category is clean, say so in one line.

## Version baseline

```bash
node -e 'const p=require("./package.json");for(const k of ["zod","nestjs-zod","class-validator","class-transformer","typescript","valibot","@sinclair/typebox"])console.log(k,(p.dependencies||{})[k]||(p.devDependencies||{})[k]||"-")'
```

The checklist is written for zod. With `class-validator`, §3's `.strict()`
rule becomes `forbidNonWhitelisted: true` on the `ValidationPipe`, and the
"hand-written twin" rule inverts — the DTO class *is* the schema. Note zod 3.25+
ships Zod 4 at the `zod/v4` subpath; mixing subpaths splits the type system,
and `nestjs-zod` supports Zod 4 only from v5.
