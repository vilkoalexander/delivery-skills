#!/usr/bin/env bash
# Live security inventory for security-review. Prints what the project
# already has — auth, the global guard and its public marker, validation,
# rate limiting, headers, hashing, the raw-query and upload surface — so the
# review judges against the plumbing that exists, not a generic ideal.
#
# Usage: scripts/inventory.sh [root]
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

limit="${INVENTORY_LIMIT:-40}"

cap() {
  awk -v limit="$limit" '
    NR <= limit { print; next }
    END { if (NR > limit) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR - limit, limit }
  '
}

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
if [ ! -d "$root" ]; then
  echo "root not found: $root" >&2
  exit 1
fi
cd "$root" || exit 1
echo "root: $root"

# Lines of source that match, without vendored, built or test files.
source_lines() {
  grep -rnE "$1" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --include='*.ts' --include='*.tsx' --include='*.java' --include='*.kt' . 2>/dev/null \
    | grep -vE 'node_modules|/dist/|/build/|/target/|\.spec\.|\.test\.|/src/test/|__tests__'
}

# section TITLE REGEX — prints the matching lines under a heading
section() {
  echo
  echo "## $1"
  source_lines "$2" | sed 's/^/  /' | cap
}

echo
echo "## Security libraries"
relevant='passport|jsonwebtoken|jose|jwt|bcrypt|argon2|scrypt|helmet|throttler|rate-limit|csurf|csrf|class-validator|zod|joi|sanitize|dompurify|casl|cors|secure-store|keychain'
find . -name package.json -not -path '*/node_modules/*' -not -path '*/dist/*' 2>/dev/null | sort | while IFS= read -r manifest; do
  RELEVANT=$relevant node -e '
    const pkg = require(require("path").resolve(process.argv[1]));
    const deps = { ...pkg.dependencies, ...pkg.devDependencies };
    const relevant = new RegExp(process.env.RELEVANT, "i");
    for (const name of Object.keys(deps)) {
      if (relevant.test(name)) console.log("  " + name, deps[name]);
    }
  ' "$manifest" 2>/dev/null
done | sort -u | cap
grep -rhoE '(spring-boot-starter-(security|oauth2-[a-z-]+|validation)|spring-security-[a-z-]+|jjwt[a-z-]*|nimbus-jose-jwt|bucket4j[a-z-]*|owasp[a-z.-]*)' \
  --include='build.gradle' --include='build.gradle.kts' --include='pom.xml' . 2>/dev/null | sort -u | sed 's/^/  /' | cap

section "Authentication: strategies, token checks, password hashing" \
  'extends PassportStrategy|JwtModule\.register|jwtService\.(sign|verify)|\bjwt\.(sign|verify)\(|jwtVerify\(|bcrypt\.(hash|compare)|argon2\.(hash|verify)|PasswordEncoder|JwtDecoder|oauth2ResourceServer|AuthenticationManager'
section "Authorization: global guards, the public marker, role checks" \
  'APP_GUARD|useGlobalGuards|SetMetadata\(|export const (Public|Roles|Permissions)\b|implements CanActivate|SecurityFilterChain|\.requestMatchers\(|@EnableMethodSecurity|\.permitAll\(|\.authenticated\('
section "Input validation at the boundary" \
  'new ValidationPipe\(|APP_PIPE|useGlobalPipes|whitelist:|forbidNonWhitelisted|ZodValidationPipe|@Validated\b|MethodValidationPostProcessor'
section "Rate limiting, headers, CORS, CSRF, cookies" \
  'ThrottlerModule|ThrottlerGuard|rateLimit\(|Bucket4j|helmet\(|enableCors\(|CorsConfiguration|allowedOrigins|csrf\(|\.csrf|cookie\([^)]*(httpOnly|sameSite)|cookieSession|SameSite'
section "Raw SQL (each one is a place for injection)" \
  '\$(queryRaw|executeRaw)(Unsafe)?|Prisma\.(raw|sql)|createNativeQuery|nativeQuery[[:space:]]*=[[:space:]]*true|jdbcTemplate\.|\.createQueryBuilder\('
section "Shell, files and uploads" \
  'child_process|\bexecSync\(|\bspawn\(|ProcessBuilder|FileInterceptor|FilesInterceptor|MultipartFile|multer\(|\.sendFile\(|createReadStream\('
section "Webhooks and signature checks" \
  '[Ww]ebhook|constructEvent|timingSafeEqual|createHmac|Mac\.getInstance|MessageDigest\.isEqual'
section "Where the client keeps a token" \
  'SecureStore\.|Keychain\.|localStorage\.(setItem|getItem)\([^)]*[Tt]oken|AsyncStorage\.(setItem|getItem)\([^)]*[Tt]oken|httpOnly'

echo
echo "## Handlers open to everyone (each one should be meant)"
open_handlers=$(source_lines '@Public\(|@PermitAll|\.permitAll\(|@AllowAnonymous|@SkipAuth' | wc -l | tr -d ' ')
echo "  count: $open_handlers"
