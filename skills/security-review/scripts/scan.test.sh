#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

mkdir -p "$tmp/app" && cd "$tmp/app"

echo "# a controller with most of it"
cat > files.controller.ts <<'TS'
@Controller('files')
export class FilesController {
  @Get(':name')
  read(@Param() params, @Res() res) {
    const rows = this.prisma.$queryRawUnsafe(`select * from f where n = '${params.name}'`);
    const other = this.db.query('select * from f where n = ' + params.name);
    exec(`convert ${params.name}`);
    return res.sendFile(path.join(root, params.name));
  }
  @Post('login')
  login(@Body() dto) {
    const claims = jwt.decode(dto.token);
    const resetToken = Math.random().toString(36);
    if (dto.signature === expected) {}
    return this.users.update({ where: { id: dto.id }, data: dto });
  }
  @Post('avatar')
  @UseInterceptors(FileInterceptor('file'))
  upload(@UploadedFile() file) { return file.originalname; }
  @Get('go')
  go(@Query() query, @Res() res) { res.redirect(query.next); }
}
TS
out=$(bash "$scan" files.controller.ts)
eq "exits 0" "$?" 0
flags "SQL built from a string"
sees  "the unsafe raw query is located"   '^5:.*queryRawUnsafe' "$out"
sees  "and the concatenated one"          '^6:.*select \* from f' "$out"
flags "Shell command"
flags "File path from outside input"
flags "Token decoded"
flags "Random that is predictable"
flags "Secret compared with an operator"
flags "Handlers and no guard or public marker in the file"
flags "Request body written as it came"
flags "Request or redirect to a URL from outside input"
flags "Sign-in, sign-up or reset route with no rate limit"
flags "Upload"
unflags "HTML written"
unflags "TLS"
unflags "Webhook"

echo "# a controller that does it right"
cat > orders.controller.ts <<'TS'
@Controller('orders')
@UseGuards(JwtAuthGuard)
export class OrdersController {
  @Get(':id')
  read(@Param('id') id: string) {
    return this.prisma.$queryRaw`select * from orders where id = ${id}`;
  }
  @Throttle({ default: { limit: 5 } })
  @Post('login')
  login(@Body() dto: LoginDto) {
    if (token == null) return;
    return this.auth.login(dto.email, dto.password);
  }
}
TS
has "is clean" 0 '^clean — no mechanical smells$' bash "$scan" orders.controller.ts

echo "# configuration and transport"
cat > main.ts <<'TS'
app.enableCors({ origin: true, credentials: true });
const agent = new https.Agent({ rejectUnauthorized: false });
app.useGlobalPipes(new ValidationPipe({ whitelist: false }));
res.cookie('sid', id, { httpOnly: false });
const h = createHash('md5').update(password).digest('hex');
const re = new RegExp(query.q);
eval(body.code);
TS
out=$(bash "$scan" main.ts)
flags "CORS open to every origin"
flags "TLS or certificate check turned off"
flags "Security control turned off"
sees  "both controls are listed" '^4:.*httpOnly: false' "$out"
flags "Fast or broken hash or cipher"
flags "Regular expression built from outside input"
flags "Code run from a string"

echo "# a webhook"
cat > stripe.webhook.ts <<'TS'
export async function handle(req) { await orders.markPaid(req.body.id); }
TS
out=$(bash "$scan" stripe.webhook.ts)
flags "Webhook with no signature check in the file"
cat > stripe.webhook.ts <<'TS'
export async function handle(req) { const event = stripe.webhooks.constructEvent(req.rawBody, sig, key); }
TS
out=$(bash "$scan" stripe.webhook.ts)
unflags "Webhook with no signature check"

echo "# a client file"
cat > Profile.tsx <<'TSX'
export function Profile({ bio }) {
  localStorage.setItem('accessToken', token);
  const key = process.env.NEXT_PUBLIC_STRIPE_SECRET;
  return <div dangerouslySetInnerHTML={{ __html: bio }} />;
}
TSX
out=$(bash "$scan" Profile.tsx)
flags "HTML written without escaping"
flags "Secret or token kept where script or another app can read it"
flags "Secret-named value compiled into the client bundle"
unflags "Handlers and no guard"

echo "# Java"
cat > ReportController.java <<'JAVA'
@RestController
public class ReportController {
    @GetMapping("/reports")
    public List<Report> find(@RequestParam String name) {
        return em.createNativeQuery("select * from report where name = '" + name + "'").getResultList();
    }
    @PermitAll
    @PostMapping("/import")
    public void load(InputStream in) throws Exception {
        Object o = new ObjectInputStream(in).readObject();
        MessageDigest md = MessageDigest.getInstance("MD5");
        e.printStackTrace();
    }
}
JAVA
out=$(bash "$scan" ReportController.java)
flags "SQL built from a string"
flags "Open to everyone"
flags "Deserialization of data that can come from outside"
flags "Fast or broken hash or cipher"
flags "Error detail sent to the caller"
unflags "Handlers and no guard"

echo "# project settings"
cat > hooks.controller.ts <<'TS'
@Controller() export class C { @Get() a(@Body() dto) { return fs.readFile(upload.name); } }
TS
out=$(bash "$scan" hooks.controller.ts)
unflags "File path from outside input"
flags   "Handlers and no guard"
out=$(INPUT=upload GUARD= bash "$scan" hooks.controller.ts)
flags   "File path from outside input"
unflags "Handlers and no guard"

echo "# input"
has "no argument"  1 '^usage: scan.sh <source file>$' bash "$scan"
has "missing file" 1 '^not found: nope.ts$'           bash "$scan" nope.ts

finish
