# Spring Service Review Checklist

Nine categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). Name the
consequence: "this is wrong" without "because X breaks" is not a finding.

Entities, repositories and migrations have their own rubric,
`jpa-schema-review`. This one covers controllers, services, configuration,
security, listeners, scheduled jobs and their tests.

## Before you start

### Version baseline

Read before applying §2, §4, §5 and §8:

```bash
grep -rhoE "(springBootPlugin|org.springframework.boot'? version|sourceCompatibility|JavaVersion\.VERSION_[0-9]+|java\.version|jjwt|testcontainers)[^,;]*" \
  build.gradle* gradle.properties settings.gradle* pom.xml gradle/libs.versions.toml 2>/dev/null | sort -u
```

The switches. Do not recommend an API the project's version does not have.

| Version | What changes |
| --- | --- |
| Boot 2.x | `javax.*`, `WebSecurityConfigurerAdapter`, `antMatchers` are current. Skip the "wrong platform" rules. |
| Boot 3.0 / 3.1 (Framework 6.0) | `jakarta.*`. A constraint on a `@PathVariable` or `@RequestParam` runs only with class-level `@Validated`. No `@MockitoBean`, no `RestClient`, no `PagedModel`, no `HandlerMethodValidationException`. |
| Boot 3.2+ (Framework 6.1) | Method parameters are validated natively; class-level `@Validated` on a controller is no longer needed. `RestClient` exists. |
| Boot 3.4+ | `@MockBean` is deprecated in favour of `@MockitoBean`. Before 3.4, `@MockBean` is correct. |
| jjwt 0.11 vs 0.12 | `parserBuilder().setSigningKey().parseClaimsJws()` vs `parser().verifyWith().parseSignedClaims()`. Code for one does not compile on the other. |

### Tooling coverage

Do not assume what the build catches. When the dispatch handed you the static
gate's coverage lines, use them and skip the command. Otherwise run once per
review:

```bash
grep -rhoE "errorprone|nullaway|spotbugs|checkstyle|pmd|spotless|archunit|sonarqube|-Xlint[:a-z,]*|-Werror" \
  build.gradle* */build.gradle* pom.xml gradle/libs.versions.toml config/ 2>/dev/null | sort | uniq -c
```

| Configured | Do not hand-report |
| --- | --- |
| Spotless / google-java-format | formatting, import order, unused imports |
| Error Prone | `BigDecimal.equals`, `new BigDecimal(double)`, `Optional` equality, `java.util.Date`, default time zone, empty catch, ignored return value |
| SpotBugs | null dereference, `equals` without `hashCode`, unclosed stream |
| PMD | lost stack trace, generic catch, log format mismatch, test with no assert |
| ArchUnit rules | whatever layer rule the project wrote: read them |
| Sonar with the Spring rules | self-invocation of `@Transactional` / `@Async` |

Nothing in that table sees any of these, so they are this review's job: a
remote call inside a transaction, a checked exception that commits, a handler
with no object-level check, a request mapped onto an entity, an `AFTER_COMMIT`
listener whose write is lost, a test that cannot fail. With no analyzer
configured at all — the common case — the whole table is this review's job
too, and `scripts/scan.sh` covers the mechanical part.

## Severity floor

Always 🔴, regardless of effort:

- a new or changed handler that reaches an object by id with no object-level
  authorization (role check only, or none)
- a request body bound to an entity, or mapped onto one with a mapper that
  copies every matching property
- a remote call (HTTP, object store, bot, mail) inside a `@Transactional` method
- a multi-write operation with no transaction, or with one that does not apply
  (non-public method, self-invocation)
- a secret, token, password or full request body in a log line, an error
  response, or a response class

## 1. Authorization — merge blocker

- **[hard] Every handler states who may call it**, the way its siblings do —
  `@PreAuthorize`, or a URL rule the project layer names. An unannotated method
  is not secured by method security. A new handler without it is 🔴 unless the
  project layer lists the path as public.
- **[hard] A role is not an object check.** `hasRole('X')` on a handler that
  takes an id lets every holder of the role reach every object. The check
  names the object: `hasPermission(#id, 'Type', 'READ')`, an owner or tenant
  predicate in the query, or the project's access evaluator. Always 🔴.
- **[hard] The expression names the right parameter.** `#unitId` on a method
  whose parameter is `id` evaluates to null; a copy-pasted expression that
  checks the parent's id while the body writes the child is the same defect.
- **[hard] List endpoints filter in the query**, with the project's security
  specification or a scoped repository method. `@PostFilter` loads everything
  first. A list with no scope returns other people's rows.
- **[hard] The identity comes from the security context** — the project's
  principal accessor — never from a path variable, a header the client sets,
  or the request body. A `userId` / `orgId` field in a request class that the
  service trusts is the finding.
- **[hard] `@PostAuthorize` is not placed on a method that writes.** The write
  has happened when the check runs.
- **[hard] A missing object answers 404 and a forbidden one 403, the same way
  as the siblings.** A different answer for "exists but not yours" tells the
  caller which ids exist; follow the project layer's rule.
- **[context] Secured methods called from the same class** skip the check:
  see §2, self-invocation.
- **[context] `SecurityContextHolder` inside `@Async`, an executor or a
  listener thread** returns no authentication unless the executor delegates
  the context. Pass the principal as an argument.

## 2. Transactions and proxies

Spring applies `@Transactional`, `@Async`, `@Cacheable` and method security
through a proxy. Code that does not go through the proxy runs without them
and raises no error.

- **[hard] The annotation is on a public method of the bean class.** Private,
  `static` and `final` methods are never intercepted. A protected or
  package-private one is intercepted only on Spring 6 and later, and only by
  a class-based proxy: not when the bean is called through its interface.
- **[hard] No self-invocation.** `this.save()` or a bare `save()` from another
  method of the same class does not start a transaction, does not go async,
  does not hit the cache. It matters when the caller does not already carry
  what the annotation adds: a non-transactional caller, a `readOnly` caller
  calling a writer, a `REQUIRES_NEW` callee. Move the method to another bean.
  The same holds for a call from `@PostConstruct`.
- **[hard] A checked exception commits.** Rollback is for `RuntimeException`
  and `Error` only. A `@Transactional` method that `throws IOException` (or any
  checked type) needs `rollbackFor`, or must wrap it in an unchecked exception.
  `@SneakyThrows` hides the same defect.
- **[hard] No remote call inside the transaction** — HTTP, object store, bot,
  mail, another service. The connection is held for the round trip and the
  timeout, and the remote effect stays when the commit fails. Call first and
  then open the transaction, or commit first and call from an `AFTER_COMMIT`
  listener. Always 🔴.
- **[hard] A multi-write operation is one transaction** on the service method.
  With no boundary each repository call commits on its own and a failure
  leaves half the work.
- **[hard] The boundary is on the service**, not on a controller (it then
  spans serialization) and not left to each repository call.
- **[prefer] Reads are `@Transactional(readOnly = true)`**, as the siblings do.
- **[hard] A caught exception from an inner transactional call does not save
  the transaction.** The inner scope marked it rollback-only; the outer commit
  throws `UnexpectedRollbackException`. Let it propagate, or isolate the inner
  call on purpose.
- **[context] `REQUIRES_NEW`** holds a second connection while the outer one
  waits. In a loop, or under load, that exhausts the pool. Report it when the
  file gives no reason for it.
- **[hard] Events published inside a transaction.** A plain `@EventListener`
  runs at once, before the commit, in the same transaction: a listener that
  sends a notification sends it for work that may still roll back. A side
  effect belongs in `@TransactionalEventListener` (default `AFTER_COMMIT`).
- **[hard] An `AFTER_COMMIT` listener that writes needs its own transaction**
  (`REQUIRES_NEW`). Without it the write joins the finished transaction and is
  never committed, with no error. The listener is not called at all when the
  publisher had no transaction, unless `fallbackExecution = true`.
- **[hard] `@Async` receives ids, not entities.** The new thread has no
  persistence context: a lazy field throws. An exception from a `void` async
  method is only logged.
- **[context] `@Cacheable`** caches a detached entity that goes stale, and a
  write path with no `@CacheEvict` serves the old value. **`@Scheduled`** runs
  on every instance of a multi-node deployment.

## 3. Controller and contract shape

- **[hard] Controllers are thin.** Bind, authorize, delegate, return. No
  repository, no entity, no branching on business state.
- **[hard] `@RequestBody` carries `@Valid`** (or `@Validated`). Without it no
  constraint on the request class runs. A nested object or a collection
  element needs its own `@Valid` on the field.
- **[hard] The request type is a request class, never an entity.** Binding an
  entity lets the client set its id, version, owner and status. Always 🔴.
- **[hard] Mapping a request onto an entity copies only what the client may
  set.** A mapper that matches properties by name copies `id`, `status`,
  `ownerId`, `role` when the request class happens to have them, and a field
  added to the request later becomes writable with no code change. Server-owned
  fields are set explicitly after the mapping; the request class has no field
  for them. Always 🔴 when a server-owned field is reachable.
- **[hard] The response type is a response class.** An entity in a response
  leaks columns, triggers lazy loads during serialization, and ties the JSON
  to the schema.
- **[hard] A primitive field in a request class hides "missing".** `boolean` /
  `int` default to `false` / `0` and `@NotNull` cannot fire. Use the wrapper.
- **[context] A constraint on a `@PathVariable` / `@RequestParam`** — on
  Framework 6.0 it runs only when the class has `@Validated`, and fails with
  `ConstraintViolationException`, which needs a handler. See the baseline.
- **[hard] Status codes match the siblings** — 201 for a create, 204 for an
  empty answer, 404 for a miss. A failure never answers 200.
- **[hard] Errors go through the project's exception type and handler.** No
  ad-hoc error body, no exception message or stack trace returned to the
  client, no second `@ControllerAdvice` beside the existing one.
- **[context] A POST a client may retry** (payment, registration, message
  send) needs a duplicate guard: a unique constraint or an idempotency key.

## 4. Lists, paging and data access from a service

- **[hard] Every list endpoint is paged** with the project's convention. A
  `findAll()` with no page or specification is an unbounded read.
- **[hard] A client-supplied sort is restricted to known properties.** Sort
  orders from the request are not checked against the model: an unknown
  property is a 500, and `JpaSort.unsafe` or a concatenated order clause is an
  injection.
- **[hard] A page needs a unique sort.** Sorting on a non-unique column alone
  skips or repeats rows between pages. Add the id as the last order.
- **[hard] A lazy association is not walked in a loop, a stream or a mapper.**
  One query per row. Fetch it in the query (`join fetch`, `@EntityGraph`) or
  select a projection. With `open-in-view` off, the same code outside the
  transaction throws `LazyInitializationException`; with it on, it works and
  holds the connection during rendering.
- **[hard] A miss is the project's not-found error.** `Optional.get()` and a
  bare `orElseThrow()` throw `NoSuchElementException`, which answers 500.
- **[prefer] An existence check uses `existsBy…`**, not `findBy…().isPresent()`
  or `count… > 0`.
- **[prefer] No `save()` on an entity loaded in the same transaction.** Dirty
  checking writes it; the call is a redundant merge.
- **[context] Filtering, sorting or counting in memory** what the database can
  do — `findAll().stream().filter(...)` — when the table grows.

## 5. Beans and configuration

- **[hard] Constructor injection.** `final` fields and the project's
  constructor convention. With `@RequiredArgsConstructor`, a dependency field
  that is not `final` is skipped without an error and is null at first use.
- **[hard] No mutable instance state in a singleton bean** — a counter, a
  `HashMap`, a "current" object, a `SimpleDateFormat`. Every request thread
  shares it.
- **[hard] Configuration is injected**, as the siblings do it:
  `@ConfigurationProperties` over scattered `@Value`, never `System.getenv`.
- **[hard] No secret in source or in a committed `application*.yml`.**
- **[hard] The current Security DSL.** On Boot 3: a `SecurityFilterChain` bean,
  `authorizeHttpRequests`, `requestMatchers`, lambda style, the specific
  matcher before the broad one, `anyRequest()` last.
- **[hard] `csrf.disable()` is correct only for a token in a header.** With
  the token in a cookie, or Basic auth, the application is still exposed.
- **[hard] JWT handling.** The signature is verified with a method that
  rejects unsigned tokens; expiry is checked; a `JwtException` rejects the
  request and never falls through as authenticated; the key is not
  `secret.getBytes()` of a short string.
- **[hard] No `new ObjectMapper()`** in application code: it lacks the modules
  and settings of the configured one (dates). Inject it.

## 6. Errors, logging and core Java

- **[hard] A catch block either handles the error or rethrows it with the
  cause.** `catch (Exception e)` that logs a message and returns null or a
  default hides the failure from the caller and from the transaction.
- **[hard] The exception is the last argument of the log call**, not
  `e.getMessage()`: the message alone has no stack trace.
- **[hard] No token, password, credential, or full request body in a log
  line**; personal data follows the project layer's rule.
- **[prefer] `{}` placeholders**, not string concatenation, in a log call.
- **[hard] `InterruptedException` is not swallowed** — restore the flag with
  `Thread.currentThread().interrupt()` or rethrow.
- **[hard] A closeable is closed.** try-with-resources on streams,
  `Files.lines`, and an HTTP client response; an unclosed response leaks the
  connection.
- **[hard] Money is `BigDecimal` or integer minor units**, never `double` or
  `float`. `BigDecimal` is compared with `compareTo` (`equals` also compares
  scale: `2.0` is not `2.00`) and built from a `String` or `valueOf`.
- **[hard] Time is `java.time`.** An instant is `Instant` or `OffsetDateTime`,
  not `LocalDateTime`. `now()` takes the project's `Clock` when it has one.
- **[hard] `==` on a `String` or a boxed value** compares references.
- **[context] `stream.toList()` is unmodifiable.** A later `add` / `sort`
  throws, and an entity collection must stay mutable.
- **[context] A null check on a value that cannot be null** — a validated
  field, a repository result already in an `Optional` — is noise that hides
  the real contract.

## 7. Tests

Every new controller and service has a test.

- **[hard] The test covers the invariant, not just the happy path** — the
  forbidden caller, the object of another owner, the invalid body, the miss,
  the rollback. A test that only proves "the mock was called" proves nothing.
- **[hard] The test can fail.** It has an assertion on the result; a
  `verify(mock)` alone, or an assert inside a `try` whose failure is caught,
  is not one.
- **[hard] It uses the project's test base and fixtures** — the shared
  container, the shared context — in place of a new `@SpringBootTest`
  configuration. Each distinct `@MockBean` set, profile or property source
  builds another Spring context; `@DirtiesContext` rebuilds it.
- **[hard] The database in a test is the real engine** through the project's
  Testcontainers setup, never H2.
- **[context] `@Transactional` on a test** hides what production does: nothing
  is flushed unless the test flushes, constraints never fire, lazy loading
  always works. Flush and clear before asserting, or do not wrap the test.
- **[prefer] Deterministic data** — a fixed seed for generated objects, a
  fixed `Clock`, no dependence on test order.
- **[context] Missing test class** — `scripts/scan.sh` reports it. Report it
  for the file under review only; do not turn the review into a backlog.

## 8. Structure and consistency

- **[hard] Reinvention** — re-implements a mapper, a validator, an error
  definition, a specification, a constant, a date or string helper that a
  shared module or a sibling already has, or that the JDK, Spring or a
  library on the classpath provides. **Run `scripts/inventory.sh` before
  judging this.** Name the replacement by its real class and path.
- **[hard] Module boundaries** — a module reaches another through its service,
  and dependencies point the way `settings.gradle` and the build files
  declare. A new edge between modules is a design change, not a detail.
- **[hard] Layering matches the siblings** — where the interface lives, where
  the implementation lives, where requests, responses and entities live. A
  new unit follows the layout; it does not add a second one.
- **[context] An interface with one implementation, a new abstract base, a
  factory or a wrapper** is a finding only when the siblings do not have it
  and nothing in the diff needs it.
- **[hard] No API newer or older than the stack** — see the baseline. A method
  that does not exist on a repository, a derived query whose property name is
  not on the entity, an import from the wrong namespace.
- **[prefer] Lombok as the siblings use it.** `@Builder` with a field
  initializer needs `@Builder.Default`, or the built object has null there.
  `@AllArgsConstructor` arguments follow field order: reordering two fields of
  one type swaps them at every call site.

## 9. Comment quality

<!-- comment-rules:start — the short form of comment-cleanup/RULES.md, the same text in each checklist -->
The default is no comment; a rename, an extracted function or a type comes
first.

- **[hard] Delete comments that restate the code or describe the change** —
  "now uses", "added", "fixed", a banner, a step number, a doc comment that
  repeats the signature or the types.
- **[hard] Delete commented-out code** — git remembers it.
- **[hard] No ticket, PR, SHA, date or link in a comment** — the code does
  not know the outside world; those live in commit messages and PR bodies.
- **[prefer] A comment that stays is one line and one of four kinds** — why
  this and not the obvious alternative, an outside constraint, a warning
  about what breaks if edited, a workaround with its removal condition. On a
  constant or a field: only units, where a number comes from, a domain term,
  or what null means, and only when a rename cannot say it.
- **[context] A missing comment** is a finding only for one of those four
  kinds, with the consequence named.
- **[context] A comment the diff removed** that was still true and one of the
  four kinds — restore it.
- **[hard] A lint, type or check suppression states its reason.**
<!-- comment-rules:end -->

In this stack:

- A restated line reads like `// save the entity` or `// loop over members`,
  or is Javadoc that repeats the signature.
- A query that skips the security specification on purpose and a call that
  must stay outside the transaction each need a comment of one of the four
  kinds.
- The suppression is a `@SuppressWarnings` or a disabled check.

---

## Do NOT report

- Anything a configured analyzer already fails the build on (see Tooling
  coverage).
- Restating the project's instructions file as if it were a finding.
- A violation in code the change did not touch.
- A migration to another library or a newer framework version — a different
  mapper, a different test tool, records in place of the project's DTO style.
- Style a formatter owns: import order, wrapping, `final` on parameters.
- Features and ceilings the project layer lists as deferred or known.
- Missing end-to-end tests. This rubric reviews one unit.
- A speculative failure. If the finding needs "might" or "could, if", find the
  line that makes it real or drop it.
