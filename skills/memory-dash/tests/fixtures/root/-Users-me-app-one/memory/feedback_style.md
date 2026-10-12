---
name: feedback-style
description: User wants short commit subjects under fifty characters and no body
type: feedback
---

Commit subjects stay under 50 characters. Add a body only when the diff does not explain the reason.

**Why:** the user reads `git log --oneline` daily.
**How to apply:** draft the subject first, cut words until it fits.
