# <Feature, in the words a user says>

<One line: what the user gets from it.> Code: `<src/features/orders/OrdersScreen.tsx>`, `<apps/api/src/orders/orders.controller.ts>`

## Reach

<From a fresh sign-in: the menu item, tab or URL. `/orders` — "Orders" in the side menu.>

## Drive

- <List: open `/orders`; the table is `data-testid="orders-table"`.>
- <Create: `orders-new` button, fill `order-customer` and `order-total`, press `order-save`.>
- <The request behind it: `POST /orders` with `{ customerId, total }`.>

## Proves it

- <The new row is first in the table with the total as entered.>
- <`GET /orders/<id>` answers 200 with status `draft`.>
- <One row in `orders` with the tenant of the signed-in user.>

## Gotchas

- <The demo tenant has no customers after a reset: run `npm run db:seed -- customers` first.>
