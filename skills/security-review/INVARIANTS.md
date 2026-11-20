# Security Invariants

The one-way doors and what the project layer must supply. `CHECKLIST.md`
applies these to one file; this says why they are absolute and what the
rubric cannot know on its own.

## Invariants

1. **Outside input is data, never code.** It reaches SQL as a parameter, a
   process as an argument, a page as escaped text, a path only after it is
   pinned to its directory. There is no "trusted" request field.
2. **Identity is proven, not read.** A token is verified with a key and a
   pinned algorithm before any claim in it is used. A header that says who
   the caller is, from a caller, says nothing.
3. **Every action is checked on the server, for this caller and this
   object.** A role answers "may this kind of user do this kind of thing".
   It does not answer "is this row theirs".
4. **The server decides what the caller may set and may see.** Fields that
   grant something — role, owner, tenant, price, status — never come from
   the body; fields that reveal something — hash, token, another user's
   data — never go in the response.
5. **A secret is unguessable, slow to test and never in the client.** Made
   by a cryptographic generator, stored hashed where it can be, compared in
   constant time, limited in guesses, and absent from every bundle and URL.
6. **A control that is on stays on.** Turning off CSRF, throttling,
   validation, a cookie flag or TLS verification is a decision of the plan,
   never a way to make a change pass.

A change that breaks one of these in production cannot be taken back by the
next deploy: data that left has left.

## What the project layer must supply

`docs/review/security-review.md` (template in
`templates/security-review.md`). Without it the rubric derives what it can
from `CLAUDE.md` and `scripts/inventory.sh` and says so.

| The rubric needs to know | Because |
| --- | --- |
| Whether a global guard exists, and the marker that opens a route | §3 — a bare handler is the floor only when nothing global covers it |
| The list of routes that are public on purpose | §3, Do NOT report — everything else open is a finding |
| How the caller is identified in a handler (`@CurrentUser()`, `req.user`, `SecurityContext`) and which field is the owner key | §3 — to name the ownership check in the project's own shape |
| The fields a client may never set, per entity | §3 — mass assignment is judged against this list |
| The fields that never leave the server | §5 — what "the entity returned whole" leaks here |
| The password hash helper, the token helper, the random helper | §2 — to name the project's call, not a library |
| The session shape: cookie or bearer, where a client stores it | §2, §3 — CSRF applies to a cookie session only |
| The throttler and what it already covers | §6 — "no limit" is a finding only if a limit is possible |
| Hosts the server may call, and how an outbound URL is checked | §4 |
| Webhook providers and the helper that verifies each | §4 |
| Data the project treats as sensitive (personal, payment, health) | §5, severity |
| Whether account enumeration matters for this product | §2 |
