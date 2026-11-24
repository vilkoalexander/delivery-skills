#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

mkdir -p "$tmp/app" && cd "$tmp/app"

echo "# a service"
cat > orders.service.ts <<'TS'
export class OrdersService {
  async onModuleInit() {}
  async place(dto: any, amount: number, amountMinor: number) {
    await this.prisma.$transaction(async (tx) => {
      await this.prisma.order.create({ data: dto });
      await fetch('https://pay.example.com');
    });
    const all = await this.prisma.order.findMany({ where: { status: 'open' } });
    const one = await this.prisma.order.findUnique({ where: { id: dto.id } });
    this.prisma.audit.create({ data: {} });
    const total = parseFloat(dto.total);
    if (!one) throw new NotFoundException('Order not found');
    if (e.code === 'P2002') throw new ForbiddenException(MESSAGES.taken);
    console.log(process.env.STRIPE_KEY, one!.id);
    this.prisma.$use(mw);
  }
}
TS
out=$(bash "$scan" orders.service.ts)
eq "exits 0" "$?" 0
flags "Inside a \\\$transaction callback"
sees  "outer client inside the callback"  '^5: .*<- outer client inside tx$' "$(under 'Inside a')"
sees  "network call inside the callback"  '^6: .*<- network/queue call inside tx$' "$(under 'Inside a')"
flags "Prisma call with no tenantId within 15 lines"
flags "findUnique with no tenantId"
flags "findMany with no take within 15 lines"
flags "Prisma call that is neither awaited, returned, nor assigned"
eq    "the floating call is located" "$(under 'Prisma call that is neither' | cut -d: -f1)" 10
flags "async onModuleInit / onApplicationBootstrap"
misses "the label names no Angular hook"  'ngOnInit' "$out"
flags "Float arithmetic near money"
flags "A money-ish field typed as plain number without a minor-unit suffix"
eq    "one hit per line"             "$(under 'A money-ish field' | wc -l | tr -d ' ')" 1
flags "Exception thrown with a literal string"
flags "Prisma error code literal"
flags "console.\*"
flags "process.env read"
flags "any / as any"
flags "Non-null assertion"
flags "\\\$use"
flags "ForbiddenException in a service"
flags "No spec for this unit"
unflags "Prisma access in a controller"

echo "# tenant settings"
has   "another tenant key"       0 '^## Prisma call with no orgId within 15 lines' env TENANT_FIELD=orgId bash "$scan" orders.service.ts
lacks "an empty key skips scoping" '^## (Prisma call with no|findUnique with no)'  env TENANT_FIELD= bash "$scan" orders.service.ts
lacks "exempt models are skipped"  '^## (Prisma call with no|findUnique with no)'  env EXEMPT_MODELS='order' bash "$scan" orders.service.ts

echo "# a scoped, bounded, tested service"
cat > tidy.service.ts <<'TS'
export class TidyService {
  list(tenantId: string) {
    return this.prisma.order.findMany({ where: { tenantId }, take: 50 });
  }
}
TS
touch tidy.service.spec.ts
has "is clean" 0 '^clean — no mechanical smells$' bash "$scan" tidy.service.ts
mkdir -p __tests__ && mv tidy.service.spec.ts __tests__/
has "a spec in __tests__ counts" 0 '^clean — no mechanical smells$' bash "$scan" tidy.service.ts

echo "# a controller"
cat > orders.controller.ts <<'TS'
export class OrdersController {
  get(@Param('orderId') orderId: string, @Req() req) {
    return this.prisma.order.findFirst({ where: { tenantId: req.user.tenantId } });
  }
}
TS
out=$(bash "$scan" orders.controller.ts)
flags "Prisma access in a controller"
flags "Route id param without a Parse\*Pipe"
flags "req.\* read directly"
unflags "ForbiddenException in a service"

echo "# input"
has "no argument"  1 '^usage: scan.sh <file.ts>$' bash "$scan"
has "missing file" 1 '^not found: nope.ts$'       bash "$scan" nope.ts

finish
