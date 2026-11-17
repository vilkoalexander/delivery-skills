# Spring Backend Invariants

The generic non-negotiables. `scripts/inventory.sh` is authoritative for what
currently exists; the project layer (`docs/review/spring-service-review.md`)
names the project's own primitives, reference files and ceilings.
`templates/spring-service-review.md` in this repository is a starting point.

## The three layers of authorization

1. **Authentication → principal.** A filter resolves the caller from the
   token. Nothing else may source identity: not a path variable, not a body
   field, not a header the client sets freely.
2. **Method security.** Every handler states who may call it, and a handler
   that takes an id names the object in the expression. A role alone is the
   first layer again, not the second.
3. **Query scope.** A list is filtered in the query by what the caller may
   see. Method security cannot do this for a list without loading every row.

Layer 2 existing does not excuse omitting layer 3 on a list, and layer 3 does
not replace layer 2 on a write.

## Where a proxy applies

| Call | Annotation applies |
| --- | --- |
| Another bean calls a public method | yes |
| The same class calls its own method (`this.x()`, bare `x()`) | no |
| A private, `static` or `final` method | no |
| A call from `@PostConstruct` | no |
| A protected or package-private method, bean used through its interface | no |

The table is the same for `@Transactional`, `@Async`, `@Cacheable`,
`@PreAuthorize` and `@Retryable`.

## What the project layer must say

| Question | Why the review needs it |
| --- | --- |
| How a handler is authorized, and the paths that are public on purpose | Otherwise every unannotated handler is a false 🔴, or a real one is missed |
| The object-level check: permission evaluator, access bean, security specification | So §1 can name the right one |
| Where identity is read from | So §1 can check the source |
| The 403 / 404 rule for an object the caller may not see | So §1 judges it the same way every time |
| Mapper, and which fields are server-owned | Decides how strict §3's mapping rule is here |
| Error type, error definitions, the exception handler | "Do not rebuild these" needs real names |
| Reference implementations — one controller, one service, one test, one event listener | The consistency baseline per pattern |
| Test base class and fixtures | So §7 can require them |
| Remote clients in the codebase | Sets `REMOTE_CALL` for the scan |
| Known ceilings and deferred features | So the review never recommends past them |

## Shared primitives — the generic shapes

| The file hand-rolls… | Expect the project to have |
| --- | --- |
| A `RuntimeException` with a message | an API exception and an error-definition enum |
| A try/catch that builds an error body | one `@RestControllerAdvice` |
| A permission check in the service body | a permission evaluator or access bean used from `@PreAuthorize` |
| A `where` clause for "what the caller may see" | a security specification |
| Field-by-field copying between request, entity and response | a configured mapper |
| A regex or an `if` for a field format | a constraint annotation and validator |
| A table, schema or header name as a literal | a constants class |
| A container, a context and a login in a test | a test base class and fixtures |
| `LocalDate.now()` | a `Clock` bean |

If the project has none of these, the finding is "this should be the first
one" — once. Not on every file.

## Known ceilings — do not recommend past these

- **A filter runs before method security.** An authentication filter's own
  lookup is unscoped by design. Do not flag it; do not copy it into a service.
- **A transaction cannot span a remote call** without holding a connection for
  the round trip. There is no annotation that fixes this; the order of the
  work does.
- **Rollback does not undo a remote effect.** A message sent, a file stored or
  a payment taken stays. Compensation is code, not configuration.
- **Self-injection is not a fix for self-invocation.** It creates a dependency
  cycle. The method moves to another bean.
- **Pagination plus a fetched collection pages in memory.** The fix is two
  queries, not a larger page.
