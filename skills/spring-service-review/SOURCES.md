# Sources

References behind `CHECKLIST.md`. Not loaded during a review.

- [Spring Framework — Using @Transactional](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html) — proxy mode, method visibility, self-invocation
- [Spring Framework — Rolling back a declarative transaction](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/rolling-back.html) — a checked exception does not roll back
- [Spring Framework — Transaction propagation](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html) — rollback-only and `UnexpectedRollbackException`, the `REQUIRES_NEW` pool warning
- [Spring Framework — Transaction-bound events](https://docs.spring.io/spring-framework/reference/data-access/transaction/event.html) and the [TransactionalEventListener Javadoc](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/event/TransactionalEventListener.html) — phases, `fallbackExecution`, a write in `AFTER_COMMIT` is not committed
- [Spring Framework — Task execution and scheduling](https://docs.spring.io/spring-framework/reference/integration/scheduling.html) — `@Async`, `@Scheduled`
- [Spring Framework — Cache annotations](https://docs.spring.io/spring-framework/reference/integration/cache/annotations.html) — self-invocation, default key
- [Spring Framework — Dependency injection](https://docs.spring.io/spring-framework/reference/core/beans/dependencies/factory-collaborators.html) — constructor injection, cycles
- [Spring MVC — Validation](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-validation.html) — `@Valid`, method validation from Framework 6.1
- [Spring MVC — Error responses](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-ann-rest-exceptions.html) — `ProblemDetail`, `ResponseEntityExceptionHandler`
- [Spring Security — Method security](https://docs.spring.io/spring-security/reference/servlet/authorization/method-security.html) — an unannotated method is not secured, `@PostAuthorize`, parameter names
- [Spring Security — Authorize HttpServletRequests](https://docs.spring.io/spring-security/reference/servlet/authorization/authorize-http-requests.html) — first match wins, `anyRequest` last
- [Spring Security — CSRF](https://docs.spring.io/spring-security/reference/features/exploits/csrf.html) and [Concurrency](https://docs.spring.io/spring-security/reference/features/integrations/concurrency.html) — when disabling is safe; the context on another thread
- [Spring Data — Web support](https://docs.spring.io/spring-data/jpa/reference/repositories/core-extensions.html) — `Pageable` defaults, sort is not validated
- [Spring Boot 3.1 release notes](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.1-Release-Notes) and [3.4 release notes](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.4-Release-Notes) — Framework 6.0 under Boot 3.1, the `@MockBean` deprecation
- [Spring TestContext — Context caching](https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/ctx-management/caching.html) and [Transaction management](https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/tx.html) — cache keys, false positives in a transactional test
- [Vlad Mihalcea — Spring transaction best practices](https://vladmihalcea.com/spring-transaction-best-practices/), [Open Session in View](https://vladmihalcea.com/the-open-session-in-view-anti-pattern/), [findById](https://vladmihalcea.com/spring-data-jpa-findbyid/), [exists query](https://vladmihalcea.com/spring-data-exists-query/)
- [OWASP — Authorization](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html), [Mass assignment](https://cheatsheetseries.owasp.org/cheatsheets/Mass_Assignment_Cheat_Sheet.html), [REST security](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html), [Logging](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
- [jjwt README](https://github.com/jwtk/jjwt) — key sizes, `getBytes`, the 0.12 parser names
- [Lombok — @Builder](https://projectlombok.org/features/Builder), [constructors](https://projectlombok.org/features/constructor), [@SneakyThrows](https://projectlombok.org/features/SneakyThrows)
- [ModelMapper — Configuration](https://modelmapper.org/user-manual/configuration/) and [Validation](https://modelmapper.org/user-manual/validation/) — matching strategies, `validate()`
- [Error Prone bug patterns](https://errorprone.info/bugpatterns), [PMD Java rules](https://pmd.github.io/pmd/pmd_rules_java.html), [SpotBugs](https://spotbugs.readthedocs.io/en/stable/bugDescriptions.html), [ArchUnit](https://www.archunit.org/userguide/html/000_Index.html) — the Tooling coverage table
- [Stream](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/stream/Stream.html), [Optional](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/Optional.html), [BigDecimal](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/math/BigDecimal.html) Javadoc 17 — `toList()` is unmodifiable, `equals` compares scale
- [Sabra et al. — Quality and security of AI-generated code](https://arxiv.org/abs/2508.14727), [Mousavi et al. — Misuse of Java security APIs by LLMs](https://arxiv.org/abs/2404.03823) — why §5 and §8 check generated code for secrets and wrong-version APIs

Not confirmed from a primary page, stated in the checklist on practitioner
consensus: an unclosed OkHttp response leaks the connection; the Security 6
removal of `WebSecurityConfigurerAdapter` and `antMatchers`;
`ConstraintViolationException` for a parameter constraint on Framework 6.0.
