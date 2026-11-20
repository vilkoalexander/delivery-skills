# Verify recipe

How an agent starts this app, drives it and shows what happened. Read by the
verifier of a delivery run; written and kept true by `verify-recipe`.
Everything in `<angle brackets>` is a placeholder — replace it or delete the line.

Surface: `<web app at http://localhost:4200>` · also: `<API at :3000, not driven here>`

## Launch

```bash
<docker compose -p verify up -d db && npm run db:reset && npm run dev>
```

- Ready when: `<GET http://localhost:3000/health answers 200 and the log prints "Nest application successfully started">`
- Needs: `<.env copied from .env.example; DATABASE_URL points at the compose db>`
- Sign in as: `<demo@example.test / the password in .env.example>`
- A second instance: `<not possible, the port is fixed — do not start one while another answers>`

## Doctor

```bash
<curl -fsS http://localhost:3000/health && lsof -ti :4200>
```

Run it first, and again when anything looks off. `<What a healthy answer looks like.>`

## Drive

- Harness: `<the browser tool | Playwright through npx playwright test e2e/<spec> | plain HTTP>`
- Handles: `<data-testid on every interactive element; find one with getByTestId>`
- A request: `<curl -fsS -H "Authorization: Bearer $(npm run -s token:demo)" http://localhost:3000/orders>`
- The feature map in `docs/review/features/` says how to reach and drive each feature.

## Evidence

- Goes to: `<$TMPDIR/verify-<app>/>`, never the working tree.
- A proof is: `<a screenshot before and after the action, the response body, the row the action wrote>`
- Read a row with: `<npm run -s db:query -- "select …">`

## Cleanup

```bash
<docker compose -p verify down && kill "$(cat "$TMPDIR/verify-<app>/dev.pid")">
```

Stops what Launch started and leaves the evidence where it is.
