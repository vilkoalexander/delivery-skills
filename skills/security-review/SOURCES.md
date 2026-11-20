# Sources

References behind `CHECKLIST.md`. Not loaded during a review.

- [OWASP Application Security Verification Standard](https://owasp.org/www-project-application-security-verification-standard/) — the shape of the seven categories; severity floor
- [OWASP Top 10](https://owasp.org/www-project-top-ten/) — broken access control first, then injection: the order of the floor
- [OWASP — SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html) and [Prisma — Raw queries](https://www.prisma.io/docs/orm/prisma-client/using-raw-sql/raw-queries) — §1 tagged template versus `Unsafe`
- [OWASP — OS Command Injection Defense Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/OS_Command_Injection_Defense_Cheat_Sheet.html) — §1
- [OWASP — Cross Site Scripting Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html) — §1
- [OWASP — JSON Web Token Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/JSON_Web_Token_for_Java_Cheat_Sheet.html) and [RFC 8725 — JWT Best Current Practices](https://www.rfc-editor.org/rfc/rfc8725) — §2 verify, pinned algorithms
- [OWASP — Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) — §2
- [OWASP — Forgot Password](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html) and [Authentication](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html) Cheat Sheets — §2 one-time secrets, enumeration; §6
- [OWASP — Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html) and [Insecure Direct Object Reference Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Insecure_Direct_Object_Reference_Prevention_Cheat_Sheet.html) — §3
- [OWASP — Mass Assignment Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Mass_Assignment_Cheat_Sheet.html) — §3
- [OWASP — Server Side Request Forgery Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html) and [Unvalidated Redirects](https://cheatsheetseries.owasp.org/cheatsheets/Unvalidated_Redirects_and_Forwards_Cheat_Sheet.html) — §4
- [OWASP — File Upload Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html) — §4
- [NestJS — Security](https://docs.nestjs.com/security/authentication): authentication, authorization, rate limiting, helmet, CORS, CSRF — §2, §3, §6, §7
- [Spring Security — Reference](https://docs.spring.io/spring-security/reference/) — §3 URL rules versus method security, §7 CSRF
- [OWASP Mobile Application Security — Data storage](https://mas.owasp.org/MASTG/) — §2 where a phone keeps a token
