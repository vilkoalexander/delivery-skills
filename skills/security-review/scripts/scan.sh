#!/usr/bin/env bash
# Mechanical pre-scan for security-review. Catches the shapes an attacker
# looks for first, so the review spends judgement on whether outside input
# reaches them. Heuristic — flags, not a verdict.
#
# Tenant scoping and role-versus-object checks belong to the service and
# schema rubrics and are not repeated here.
#
# Usage: scan.sh <source file>          TypeScript, JavaScript, Java or Kotlin
# Env:   INPUT   extra |-separated names that hold outside input in this
#                project (default: req, request, body, query, params, dto, input, payload)
#        GUARD   ERE for what authorizes a handler or marks it public
#                (default: @UseGuards|@Public|@Roles|@Auth|@Permissions|@PreAuthorize|
#                @Secured|@RolesAllowed|@PermitAll; "" when a global guard or URL rules decide)
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <source file>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

input="(req|request|ctx|body|query|params|dto|input|payload${INPUT:+|$INPUT})"
from_input="\\b$input\\b"
guard="${GUARD-@UseGuards|@Public|@Roles|@Auth|@Permissions|@PreAuthorize|@Secured|@RolesAllowed|@PermitAll}"

found_any=0

# flag LABEL [LINES] — prints a finding, with the lines that caused it when there are any
flag() {
  printf '## %s\n' "$1"
  [ -n "${2:-}" ] && printf '%s\n' "$2"
  printf '\n'
  found_any=1
}

# report LABEL REGEX [i] — flags every line of the file that matches
report() {
  local matches
  matches=$(grep -n"${3:-}"E -- "$2" "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

has() {
  grep -qE -- "$1" "$file"
}

has_i() {
  grep -qiE -- "$1" "$file"
}

# --- input that reaches an interpreter ------------------------------------------
report "SQL built from a string — parameters, or the tagged template" \
  '\$(queryRaw|executeRaw)Unsafe|Prisma\.raw\(|\.(query|execute)\([[:space:]]*(`[^`]*\$\{|["'"'"'][^)]*["'"'"'][[:space:]]*\+)|(createNativeQuery|createQuery|prepareStatement|jdbcTemplate\.[A-Za-z]+|\.(query|update|execute))\([^)]*"[[:space:]]*\+'
report "Shell command — is any part of it outside input?" \
  'child_process|\b(exec|execSync|execFile|spawn|spawnSync|execa)\(|Runtime\.getRuntime\(\)\.exec|new ProcessBuilder'
report "Code run from a string" \
  '\beval\(|new Function\(|vm\.(runIn|Script)|ScriptEngine|(setTimeout|setInterval)\([[:space:]]*["'"'"'`]'
report "File path from outside input — traversal" \
  "\\b(fs|fsp|promises)\\.[A-Za-z]+\\([^)]*$from_input|path\\.(join|resolve)\\([^)]*$from_input|(sendFile|download|createReadStream|createWriteStream)\\([^)]*$from_input|(new File|Paths\\.get|Path\\.of)\\([^)]*(\\+|$from_input)"
report "HTML written without escaping" \
  'dangerouslySetInnerHTML|\.(innerHTML|outerHTML)[[:space:]]*=|\[innerHTML\]|bypassSecurityTrust|v-html|document\.write\(|insertAdjacentHTML'
report "Deserialization of data that can come from outside" \
  'ObjectInputStream|\.readObject\(|XMLDecoder|enableDefaultTyping|yaml\.load\(|unserialize\('
report "Regular expression built from outside input" \
  "new RegExp\\([^)]*$from_input|Pattern\\.compile\\([^)]*$from_input"

# --- who is asking ---------------------------------------------------------------
report "Token decoded — is it verified first?" \
  '\bjwt\.decode\(|\bjwtDecode\(|\bdecodeJwt\(|JWT\.decode\(|ignoreExpiration:[[:space:]]*true|algorithms?:[^]]*none|parseClaimsJwt\(|setAllowedClockSkewSeconds'
report "Fast or broken hash or cipher" \
  'createHash\(["'"'"'](md5|sha1)["'"'"']\)|getInstance\("(MD5|SHA-?1|DES|RC4)[^"]*"\)|createCipher\(|/ECB/|NoOpPasswordEncoder|MessageDigestPasswordEncoder'
if has_i 'token|secret|password|otp|nonce|salt|reset|invite|session|api_?key'; then
  report "Random that is predictable, in a file about secrets" \
    'Math\.random\(\)|new Random\(|ThreadLocalRandom|RandomStringUtils\.random'
fi
report "Secret compared with an operator — timing-safe compare" \
  '(signature|hmac|digest|secret)[A-Za-z0-9_.]*[[:space:]]*(===|!==|==|!=)[[:space:]]*[A-Za-z_]|(signature|hmac|digest|secret)[A-Za-z0-9_.]*\.equals\(' i

# --- who may act -----------------------------------------------------------------
routes='@(Get|Post|Put|Patch|Delete|All)\(|@(Query|Mutation|Subscription|SubscribeMessage|MessagePattern)\(|@(Get|Post|Put|Patch|Delete|Request)Mapping'
if [ -n "$guard" ] && has "$routes" && ! has "$guard"; then
  flag "Handlers and no guard or public marker in the file — confirm a global guard or the URL rules cover each one"
fi
report "Open to everyone — is each one meant to be?" \
  '@Public\(|@PermitAll|\.permitAll\(|@AllowAnonymous|@SkipAuth|anonymous\(\)'
report "Request body written as it came — mass assignment" \
  "data:[[:space:]]*(req\\.body|request\\.body|body|dto|input|payload)[[:space:]]*[,}]|\\.\\.\\.(req\\.body|request\\.body|body)\\b|Object\\.assign\\([^,]+,[[:space:]]*(req\\.body|request\\.body|body|dto)\\b|BeanUtils\\.copyProperties|\\.(save|merge|persist)\\([[:space:]]*(request|dto|body)[[:space:]]*\\)"
report "Privilege field set from a variable — who may set it?" \
  '\b(role|roles|isAdmin|is_admin|permissions|scopes|tenantId|ownerId|userId)[[:space:]]*[:=][[:space:]]*(req|request|body|dto|input|payload|params|query)\b'

# --- where it sends, and what it lets in -----------------------------------------
report "Request or redirect to a URL from outside input" \
  "(redirect|sendRedirect)\\([^)]*$from_input|\\b(fetch|got|axios(\\.[a-z]+)?|request|httpService\\.[a-z]+|this\\.http\\.[a-z]+|restTemplate\\.[A-Za-z]+|webClient\\.[a-z]+)\\([[:space:]]*$input\\b"
report "TLS or certificate check turned off" \
  'rejectUnauthorized:[[:space:]]*false|NODE_TLS_REJECT_UNAUTHORIZED|TrustAll|InsecureTrustManager|setHostnameVerifier|ALLOW_ALL_HOSTNAME|trustAllCerts|verify(Ssl|SSL)?[[:space:]]*[:=][[:space:]]*false'
report "CORS open to every origin" \
  "origin:[[:space:]]*(true|[\"']\\*[\"'])|Access-Control-Allow-Origin[\"']?[[:space:]]*[,:][[:space:]]*[\"']\\*|allowedOrigins?(Patterns)?\\([[:space:]]*\"\\*\"|@CrossOrigin[[:space:]]*(\\(\\))?[[:space:]]*\$"
report "Security control turned off" \
  '@SkipThrottle|csrf[^;]*\.disable\(|csrf\(\)\.disable|frameOptions[^;]*disable|whitelist:[[:space:]]*false|forbidNonWhitelisted:[[:space:]]*false|contentSecurityPolicy:[[:space:]]*false|httpOnly:[[:space:]]*false|secure:[[:space:]]*false'

if { grep -qi webhook <<< "$file" || has_i 'webhook'; } && ! has_i 'signature|hmac|constructEvent|timingSafeEqual|verify'; then
  flag "Webhook with no signature check in the file"
fi
auth_route='["'"'"'`/](login|signin|sign-in|signup|sign-up|register|forgot|reset|otp|verify|token|refresh)'
if has "$routes" && has_i "$auth_route" && ! has_i 'throttle|ratelimit|rate_limit|bucket|limiter'; then
  flag "Sign-in, sign-up or reset route with no rate limit in the file — confirm a global one covers it"
fi
report "Upload — size and type limited, name not taken from the client?" \
  'FileInterceptor|FilesInterceptor|@UploadedFiles?\(|multer\(|MultipartFile|originalname|getOriginalFilename'

# --- what leaves -----------------------------------------------------------------
report "Secret or token kept where script or another app can read it" \
  '(localStorage|sessionStorage|AsyncStorage)\.setItem\([^)]*(token|jwt|secret|password|session|refresh)' i
report "Secret-named value compiled into the client bundle" \
  '(NEXT_PUBLIC|EXPO_PUBLIC|VITE|REACT_APP|NG_APP)_[A-Z0-9_]*(SECRET|PRIVATE|PASSWORD)'
report "Error detail sent to the caller" \
  '(res|response|reply)\.[a-z.()0-9]*(send|json)\([^)]*(\.stack|err\b|error\b|e\b)\)|printStackTrace\(|getStackTrace\(\)|include-stacktrace|includeStackTrace'

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
