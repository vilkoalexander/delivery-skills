#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

mkdir -p "$tmp/app" && cd "$tmp/app"

echo "# a file with a logger"
cat > orders.service.ts <<'TS'
export class OrdersService {
  private readonly logger = new Logger();
  async place(order, tenantId) {
    this.logger.info(`placing ${order.id}`);
    this.logger.debug(JSON.stringify(order));
    this.logger.info('auth', { token: order.token });
    this.logger.warn('in', req.headers);
    try {
      await this.http.post('/pay', order);
    } catch (e) {
      order.failed = true;
    }
    try { await save(order); } catch (e) { this.logger.error('save failed'); throw e; }
    for (const line of order.lines) {
      this.logger.info('line', { id: line.id });
    }
  }
  @Cron('* * * * *')
  sweep() {}
}
TS
out=$(bash "$scan" orders.service.ts)
eq "exits 0" "$?" 0
flags "Logger without class context"
flags "String interpolation in a log call"
flags "JSON.stringify in a log call"
flags "Possible secret in a log call"
flags "Request headers or full body in a log call"
flags "Silent catch"
sees  "the silent catch is located" '^10: catch block with no log and no throw$' "$out"
misses "a catch that logs and rethrows is not silent" '^13: catch block' "$out"
flags "logger.error with a string only"
flags "Error-level log next to a rethrow"
flags "Outbound HTTP / SDK call"
flags "Timer or cron entry"
flags "Log calls present, no correlation id reference"
flags "Tenant-scoped file whose log calls never carry the tenant id"
flags "Per-item info log in a loop"
unflags "No logger in a file"
unflags "console"

echo "# a file without one"
cat > refunds.service.ts <<'TS'
export class RefundsService {
  async refund(id) {
    try { await this.stripe.refund(id); } catch (e) { console.error(e); throw e; }
  }
}
TS
out=$(bash "$scan" refunds.service.ts)
flags "console.\* — bypasses level"
flags "No logger in a file with catch blocks or external calls"
flags "Deletion, money or auth path with no log line"

echo "# a catch that logs is not silent"
cat > quiet.ts <<'TS'
try { a(); } catch (e) {
  this.logger.warn({ err: e, requestId }, 'skipped');
}
TS
out=$(bash "$scan" quiet.ts)
unflags "Silent catch"

echo "# project settings"
cat > audit.ts <<'TS'
audit.write('login', { pin: user.pin });
TS
has "a default scan sees nothing"       0 '^clean — no mechanical smells$' bash "$scan" audit.ts
has "LOG_CALL names the log function"   0 '^## Log calls present'          env LOG_CALL='audit\.write\(' bash "$scan" audit.ts
has "SECRETS adds field names"          0 '^## Possible secret in a log call' env LOG_CALL='audit\.write\(' SECRETS=pin bash "$scan" audit.ts

echo "# input"
has "no argument"  1 '^usage: scan.sh <backend file>$' bash "$scan"
has "missing file" 1 '^not found: nope.ts$'            bash "$scan" nope.ts

finish
