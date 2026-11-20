# Security Review Checklist

Seven categories. Walk them in order. Each rule is tagged **[hard]** (always
report), **[prefer]** (report unless the file gives a reason not to) or
**[context]** (report only with a concrete consequence in this file). For
each finding, name who can do what: "validate this" without "otherwise any
signed-in user reads another user's invoice by changing the id" is not a
finding.

This is a second pass. Tenant scoping, role-versus-object checks on a
service method, `@Valid` on a body and secrets in log lines belong to
`nestjs-service-review`, `spring-service-review`, `prisma-schema-review` and
`observability-review`. Do not repeat their findings; add what they do not
look for.

## Before you start

### Where the trust boundary is

Before any rule, answer three questions about the file, from the code and
the project layer:

1. **What comes from outside?** Request body, query, params, headers,
   cookies, an uploaded file, a webhook payload, a message from a queue
   another system writes to, a deep link, a value read back from the
   database that a user once typed.
2. **Who is the caller by the time this code runs?** Nobody, any signed-in
   user, a user with a role, another service. A global guard changes the
   answer for every handler; `scripts/inventory.sh` shows whether one exists.
3. **What can this code reach?** The database, the file system, a shell,
   another host, another user's data, money.

A rule applies only where outside input meets something from question 3. A
raw query over a constant is not a finding.

### Tooling coverage

Do not assume what lint catches. Run once per review:

```bash
npx eslint --print-config <file> | grep -E '"(no-eval|no-implied-eval|security/|no-unsanitized/|react/no-danger)'
```

A rule at `"error"` is the build's job: skip it. `secret-scan.sh` already
fails the gate on a credential in an added line, and `dep-vet.sh` vets each
new dependency: neither is repeated here. When the dispatch handed you a
coverage table from the static gate, use that and skip the command.

## Severity floor

Always 🔴, regardless of effort:

- outside input in a SQL string, a shell command, `eval`, a file path or a
  template that is not escaped
- a token whose signature is not verified, or verified with an algorithm the
  token names itself
- a handler that reads or changes data and that nobody is stopped from
  calling, unless the project layer lists it as public
- an object fetched or changed by an id from the request with no check that
  the caller owns it
- a password stored reversibly or with a fast hash
- a webhook that acts before its signature is checked
- TLS or certificate verification turned off outside a test

## 1. Input that reaches an interpreter

- **[hard] SQL is parameterized** — the tagged template (`` $queryRaw`…${id}` ``),
  bound parameters, the query builder. `$queryRawUnsafe`, `Prisma.raw`, and
  a string built with `+` or `${}` and handed to `.query()`,
  `createNativeQuery` or `jdbcTemplate` are injection when any part is
  outside input. A column or sort name from the request is checked against
  a fixed list; it cannot be a parameter.
- **[hard] No shell with outside input** — `exec` with an interpolated
  string runs whatever the string says. `execFile` or `spawn` with an
  argument array, and the value still checked against what it may be.
- **[hard] A path from outside stays inside its directory** — resolve it,
  then confirm it starts with the base directory. `path.join(base, name)`
  alone accepts `../../etc/passwd`.
- **[hard] HTML is escaped by the framework** — `dangerouslySetInnerHTML`,
  `innerHTML`, `bypassSecurityTrustHtml`, `v-html` with a value a user can
  influence is stored XSS. A sanitizer the project already uses, on the way
  in to that sink, is the only exception.
- **[hard] No `eval`, `new Function`, or deserializer of native objects** on
  outside data: `ObjectInputStream`, `yaml.load`, Jackson default typing.
- **[prefer] A regular expression built from input** is escaped, or the
  pattern is fixed: a crafted pattern or string holds the event loop.
- **[context] Second-order input** — a value a user typed once and the code
  now reads from the database is still outside input when it reaches a
  sink.

## 2. Who is asking

- **[hard] A token is verified, not decoded** — `jwt.verify` with the key
  and a pinned `algorithms` list; `jwt.decode` proves nothing. Expiry is
  checked (`ignoreExpiration` is off). The key comes from configuration.
- **[hard] Passwords use the project's slow hash** — argon2, bcrypt or
  scrypt through the helper the inventory shows. Never MD5, SHA-1, plain
  SHA-256, or a reversible cipher.
- **[hard] A secret is made by a cryptographic generator** — a reset token,
  an invite code, an OTP, a session id from `crypto.randomBytes`,
  `randomUUID` or `SecureRandom`. `Math.random()` and `new Random()` are
  predictable.
- **[prefer] A secret is compared in constant time** — a signature, an HMAC,
  an API key with `timingSafeEqual` or `MessageDigest.isEqual`, not `===`.
- **[prefer] A one-time secret is one-time** — a reset or verify token has
  an expiry, is stored hashed, and is spent on first use.
- **[prefer] A session cookie is `httpOnly`, `secure`, `sameSite`** as the
  siblings set it; a token for a browser does not go in `localStorage`, and
  on a phone it goes in the secure store the project uses.
- **[context] The answer does not tell who exists** — sign-in, reset and
  sign-up give the same response and the same timing for a known and an
  unknown account, when the project layer says enumeration matters.

## 3. Who may act

- **[hard] Every new handler is behind the guard, or public on purpose** —
  with a global guard, a new route is covered and only `@Public()` /
  `permitAll` needs a reason. With none, each handler names its guard. A
  handler added next to guarded siblings and left bare is the floor.
- **[hard] The caller owns the object** — an id from the request is looked
  up together with the caller: `where: { id, userId }`, not `where: { id }`
  followed by nothing. The tenant half of this is the service rubric's; the
  user half inside one tenant is here.
- **[hard] The body cannot set what the caller may not** — `data: dto`,
  `...req.body`, `BeanUtils.copyProperties` write every field the client
  sends. `role`, `isAdmin`, `ownerId`, `tenantId`, `emailVerified`, `price`
  and `status` are set by the server, from the session or the domain rule.
- **[prefer] The check is on the server for the action, not on the screen**
  — a hidden button is not authorization; the handler behind it checks.
- **[prefer] A new role or permission follows the existing decision point**
  — the guard, the policy class, the CASL ability the inventory shows; not
  an `if (user.role === …)` inside the handler.
- **[context] A state change by GET**, or a state change reachable by a
  cross-site form when the session is a cookie and the project has no CSRF
  defence.

## 4. Where it sends, and what it lets in

- **[hard] A URL from outside is not fetched as it comes** — the host is
  checked against a list, or the request cannot reach internal addresses
  (metadata endpoint, localhost, private ranges). Otherwise the server
  fetches what the attacker cannot.
- **[hard] A redirect target from outside is a path or a listed host** —
  `res.redirect(query.next)` sends a signed-in user to a look-alike.
- **[hard] A webhook checks its signature first**, on the raw body, with
  the provider's helper, before parsing or acting; and ignores an event id
  it has already handled.
- **[hard] TLS verification stays on** — `rejectUnauthorized: false`, a
  trust-all manager or a disabled hostname verifier belongs only in a test.
- **[prefer] CORS names its origins** — `origin: true` or `*` together with
  credentials lets any site act as the signed-in user.
- **[prefer] An upload is limited** — size and count at the interceptor,
  type decided from the content, the stored name generated by the server,
  the file served from a place that does not execute it.
- **[context] A new outbound call sends a credential** — only to the host it
  belongs to, over TLS, and not in a URL that gets logged.

## 5. What leaves

- **[hard] A response carries the fields the caller may see** — a DTO or a
  `select`, not the entity. A user row returned whole carries the password
  hash, the reset token and the other tenant's ids.
- **[hard] An error does not carry internals** — no stack, SQL, file path
  or upstream response body to the client. The project's filter decides
  the shape.
- **[hard] Nothing secret is compiled into a client** — a `NEXT_PUBLIC_`,
  `EXPO_PUBLIC_` or `VITE_` variable ships to every user. A key that must
  stay secret is used from the server.
- **[prefer] A list endpoint cannot be walked by id** — sequential ids plus
  a missing ownership check is every row; the fix is the ownership check.
- **[context] Personal data in a URL, a cache key or an analytics event** —
  report when the project layer names the data as sensitive.

## 6. Abuse

- **[hard] A guessable secret has a limit on guesses** — sign-in, OTP,
  reset, invite and coupon endpoints sit behind the project's throttler,
  per account and per address, when the inventory shows one.
- **[prefer] An expensive or outbound action has a limit** — sending mail
  or SMS, generating a file, calling a paid API, on behalf of an
  unauthenticated or freshly created caller.
- **[prefer] A body, a page size and an array have a maximum** — the
  validation schema states it; "the client never sends more" is not one.
- **[context] An action that must happen once** — a payment, a redemption,
  a transfer: two requests at the same time are both checked before either
  writes. Report with the interleaving named.

## 7. Configuration

- **[hard] A control that was on stays on** — `csrf().disable()`,
  `@SkipThrottle`, `whitelist: false`, `helmet` removed, a cookie flag set
  to `false`, a route moved under `permitAll`. Each needs the reason in the
  plan task, not in a comment.
- **[prefer] A debug, admin or seed route is not reachable in production**
  — behind the guard and an environment check, or not registered at all.
- **[prefer] A default that is safe** — a new feature flag, role or sharing
  setting starts closed.
- **[context] A new secret has a home** — it is read from configuration
  under a name the project layer's list can take, and the example env file
  gets the name without the value.

## Do NOT report

- A tenant filter missing from a query, a role used where an object check
  is needed in a service, a body with no validation decorator, a secret in
  a log line: the service, schema and observability rubrics report these.
- A credential in the diff, or a risky new dependency: the gate's secret
  scan and `dep-vet.sh` own them.
- A sink with no path from outside input. Say what the input is, or do not
  report.
- Replacing the project's auth library, hash, validator or throttler with
  another.
- Headers, WAF rules, network policy, key rotation: infrastructure, not
  this file.
- A theoretical weakness with no caller: "could be vulnerable if someone
  later passes user input" on a private helper with constant arguments.
- Anything the linter already **errors** on (see Tooling coverage).
- A handler the project layer lists as public.
- Hardening untouched sibling code. Review the file in front of you.
