# Spring service review — project layer

Loaded by `spring-service-review` at step 2. Also the source for the scan
env: `AUTHZ='<@PreAuthorize|@Secured>'` `REMOTE_CALL='<restTemplate|minioClient|telegram>'`.
Everything in `<angle brackets>` is a placeholder — replace it or delete the row.

## Stack

`<Spring Boot 3.1 / Java 17 / Gradle multi-module>`. Analyzers in the build: `<none | checkstyle, errorprone>`.

## Authorization

- A handler is authorized by: `<@PreAuthorize on every handler | URL rules in SecurityConfig>`.
- Object-level check: `<hasPermission(#id, 'Unit', 'READ') through AclPermissionEvaluator | @orgAccess.hasRelation(#orgId)>`.
- Lists are scoped by: `<SecuritySpecification.applySecurity(...)>`.
- Identity is read with: `<SecurityUtils.currentUser() | @AuthenticationPrincipal AuthUser>`. Never from `<the X-Org-Id header without @orgAccess>`.
- An object the caller may not see answers: `<403 | 404>`.
- Public on purpose: `</auth/**, /registration/**, /actuator/health>`.

## Layout

| Kind | Lives in |
| --- | --- |
| Controller | `<module>/controller/<X>Controller.java` |
| Service interface / implementation | `<module>/service/<X>Service.java` / `<module>/service/impl/<X>ServiceImpl.java` |
| Request, response | `<model/dto/<area>/<X>Request.java, <X>.java>` |
| Module dependencies | `<controller module → service module → model; never the other way>` |

## Reference implementations

| Concern | Read |
| --- | --- |
| Controller shape, authorization, status codes | `<user/.../controller/UnitController.java>` |
| Service shape, transactions, not-found | `<user/.../service/impl/UnitGroupServiceImpl.java>` |
| Event after commit | `<...Listener.java>` |
| Remote call kept outside the transaction | `<...ServiceImpl.java>` |
| Controller test | `<application/.../UnitControllerTest.java>` |
| Access-rule test | `<application/.../ServiceAccessFlowTest.java>` |

## Shared primitives — do not rebuild

| The file hand-rolls… | Use |
| --- | --- |
| A `RuntimeException` with a message | `<ApiException.of(ModuleErrorDefinition.X)>` |
| An error body or a second advice | `<GlobalExceptionHandler>` |
| Field-by-field mapping | `<the ModelMapper bean, DefaultModelMapper>` |
| A format check in the service | `<@NameConstraint, @ValidDateOfBirth>` |
| A table, schema or header literal | `<Constants>` |
| A container, a login, a token in a test | `<CoreTestTemplate, BaseControllerTest>` |

## Mapping requests onto entities

`<ModelMapper, STANDARD matching>`. Server-owned fields a request must never set: `<id, status, orgId, createdBy>`.

## Transactions and remote calls

- Boundary: `<@Transactional on ServiceImpl methods; readOnly = true on reads>`.
- Remote clients: `<RestTemplate (SMS), MinioClient (files), Telegram bot>` — `<called after commit from @TransactionalEventListener | called before the transaction opens>`.
- Events: `<published from the controller after the service returns | from the service>`.

## Personal data

Never in a log line: `<phone, email, date of birth, token>`.

## Known ceilings

- `<the authentication filter's own lookup is unscoped by design>`
- `<one ceiling per line, stated as a rule a reviewer can check>`

## Deferred — never propose as gaps

`<feature, feature, …>`
