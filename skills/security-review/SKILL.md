---
name: security-review
description: Use when asked to review a single file for security — a controller, handler, guard, auth flow, webhook, upload, or a client file that stores a token or renders HTML — whether outside input can reach SQL, a shell, a path or a page, or whether a caller can do or see what they should not. For a whole diff or PR, go through review-routing instead.
---

# Security Review

Structured review of ONE file for what someone who means harm can do with
it. Report and suggest — never edit the file.

[CHECKLIST.md](CHECKLIST.md) is the rubric: the trust boundary, tooling
coverage, severity floor, the seven categories, and what not to report. A
diff review reaches it through `review-routing` and never loads this file.

The one question every rule serves: **what comes from outside, who is the
caller by the time this runs, and what can it reach?**

It is a second pass. Tenant scoping, role-versus-object checks in a service,
body validation and secrets in logs belong to the service, schema and
observability rubrics; this one does not repeat them.

## Workflow

1. **Target.** One file that receives outside input, decides who may act,
   or handles a secret. None given — ask which.
2. **Project layer.** [INVARIANTS.md](INVARIANTS.md), which says what the
   project layer must supply and which rules are one-way doors. Then
   `docs/review/security-review.md` if the repository has
   one: the global guard and its public marker, the public routes, how the
   caller is identified, the fields a client may never set or see, the hash
   and token helpers, the throttler, the hosts the server may call. If it is
   absent, derive the same from `CLAUDE.md` / `AGENTS.md` and say so in one
   line. Then one sibling file in the same directory as the consistency
   baseline.
3. **`scripts/inventory.sh [root]`** — what security plumbing exists.
4. **`scripts/scan.sh <file>`** — mechanical pre-scan. Flags, not a verdict:
   a flag is a finding only when outside input reaches the line.
5. **Walk CHECKLIST.md** top to bottom, the trust-boundary questions first.
6. **Report** in the format below.

Scripts live next to this file; installed as a plugin, under
`${CLAUDE_PLUGIN_ROOT}/skills/security-review/scripts/`.

## Effort

Default **medium**: 🔴 and 🟡 only, and **zero findings is a valid outcome**
— say so and stop. **high** adds ⚪ nits, still ranked. A short report of
real defects beats an exhaustive one.

## Output format

```
### <file> review

🔴 <file:line> — <one-sentence defect>
   who: <which caller> can <do or see what>, by <the request that does it>
   ```diff
   - <before>
   + <after>
   ```

🟡 <file:line> — ...
⚪ <file:line> — ...

Verdict: <SHIP | FIX FIRST> — <one line>
```

Most-severe first. One finding per defect. Every finding names the caller and the request. A
finding with no path from outside input is not one. A clean category gets
one line.
