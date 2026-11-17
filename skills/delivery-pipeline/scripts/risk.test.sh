#!/usr/bin/env bash
# The path half of risk.sh. The content pass is in risk-content.test.sh.
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
risk="$here/risk.sh"

new_repo project

# class NAME PATH WANTED_CLASS WANTED_RULE
class() {
  local line
  line=$(bash "$risk" "$2" 2>&1 | head -1)
  eq "$1" "$line" "$(printf '%-7s %s  (%s)' "$3" "$2" "$4")"
}

echo "# high"
class "prisma schema"       prisma/schema.prisma              high "schema or migration"
class "migration folder"    db/migrations/001/up.txt          high "schema or migration"
class "sql file"            scripts/backfill.sql              high "schema or migration"
class "contract package"    libs/shared/src/user.ts           high "shared contract package"
class "auth folder"         src/auth/login.ts                 high "auth, guard, session"
class "guard file"          src/users/owner.guard.ts          high "auth, guard, session"
class "money word"          src/billing/total.ts              high "money path"
class "env file"            .env.local                        high "env or secrets"
class "workflow"            .github/workflows/ci.yml          high "CI, deploy, infra"
class "dockerfile"          Dockerfile                        high "CI, deploy, infra"
class "high beats low"      src/auth/login.spec.ts            high "auth, guard, session"

echo "# low"
class "spec file"           src/users/users.service.spec.ts   low "tests"
class "tests folder"        tests/helpers.ts                  low "tests"
class "markdown"            README.md                         low "docs"
class "stylesheet"          src/app.scss                      low "styling or assets"
class "translations"        src/i18n/en.json                  low "copy, i18n"
class "tooling config"      eslint.config.mjs                 low "dev tooling config"
class "feature screen"      src/features/cart/CartPage.tsx    low "feature-local UI"
class "leaf component"      src/Button.tsx                    low "leaf component"

echo "# medium"
class "nest service"        src/users/users.service.ts        medium "NestJS unit"
class "shared hook"         src/hooks/useCart.ts              medium "shared primitive, hook or util"
class "shared ui beats leaf" src/components/ui/Button.tsx     medium "shared primitive, hook or util"
class "manifest"            package.json                      medium "dependency change"
class "lockfile"            apps/web/pnpm-lock.yaml           medium "dependency change"
class "anything else"       src/thing.ts                      medium "no rule matched — unsure is medium"

echo "# the class for the set"
has "highest path wins"           0 '^class: high$'   bash "$risk" README.md src/thing.ts src/auth/login.ts
has "all low stays low"           0 '^class: low$'    bash "$risk" README.md src/Button.tsx
has "counts the files"            0 '^files: 2$'      bash "$risk" README.md src/Button.tsx
has "many low files are medium"   0 '^class: medium  \(raised: 6 files > RISK_MAX_LOW_FILES=5\)$' bash "$risk" a.md b.md c.md d.md e.md f.md
has "the limit can move"          0 '^class: medium  \(raised: 2 files > RISK_MAX_LOW_FILES=1\)$' env RISK_MAX_LOW_FILES=1 bash "$risk" a.md b.md
has "without a key the controller owns the escalators" 0 '^escalators: controller$' bash "$risk" README.md

echo "# project patterns"
has "RISK_HIGH"                   0 '^high    src/thing.ts  \(RISK_HIGH\)$'    env RISK_HIGH='thing' bash "$risk" src/thing.ts
has "RISK_MEDIUM"                 0 '^medium  README.md  \(RISK_MEDIUM\)$'     env RISK_MEDIUM='README' bash "$risk" README.md
has "RISK_HIGH beats RISK_MEDIUM" 0 '\(RISK_HIGH\)'                            env RISK_HIGH='thing' RISK_MEDIUM='thing' bash "$risk" src/thing.ts

echo "# input"
has "paths on stdin"   0 '^class: high$'      bash -c "printf 'README.md\n\nsrc/auth/a.ts\n' | bash '$risk'"
has "no paths"         2 '^usage: risk.sh'    bash "$risk"

echo "# a dependency change sharing the chunk"
mixed() { bash "$risk" "$@" 2>&1 | grep -c '^mixed: '; }
eq "bump alone is not mixed"       "$(mixed package.json pnpm-lock.yaml)" 0
eq "bump with source is mixed"     "$(mixed package.json src/a.ts src/b.ts)" 1
eq "workspace package.json counts" "$(mixed apps/web/package.json src/a.ts)" 1
eq "no dependency change, no line" "$(mixed src/a.ts)" 0
has "says how many other paths"    0 '^mixed: dependency change shares the chunk with other paths \(2\)' bash "$risk" package.json src/a.ts src/b.ts

finish
