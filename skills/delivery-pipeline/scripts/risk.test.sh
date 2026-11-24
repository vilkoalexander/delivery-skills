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
class "flyway migration"    app/src/main/resources/db/migration/V1.2__x.sql high "schema or migration"
class "jpa entity"          model/src/main/java/shop/InvoiceEntity.java high "schema or migration"
class "security module"     security/src/main/java/shop/filter/PhoneFilter.java high "auth, guard, session"
class "java auth class"     user/src/main/java/shop/JwtTokenManager.java high "auth, guard, session"

class "the config of the gate" docs/review/delivery.json        high "the config of the gate"
class "the drift checks"    docs/review/drift.checks          high "the config of the gate"
class "money word, any case" api/src/main/java/shop/PaymentService.java high "money path"
class "money word in a screen" src/features/cart/CheckoutScreen.tsx high "money path"
class "kotlin entity"       model/src/main/kotlin/shop/OrderEntity.kt high "schema or migration"
class "typeorm entity"      src/users/user.entity.ts          high "schema or migration"
class "secrets file"        config/secrets.yaml               high "env or secrets"

echo "# low"
class "a doc about money"   docs/billing.md                   low "docs"
class "a style named after auth" src/oauth-button.css         low "styling or assets"
class "spec file"           src/users/users.service.spec.ts   low "tests"
class "tests folder"        tests/helpers.ts                  low "tests"
class "java test"           user/src/test/java/shop/UnitControllerTest.java low "tests"
class "java test fixtures"  test-utils/src/testFixtures/java/shop/BaseTest.java low "tests"
class "markdown"            README.md                         low "docs"
class "stylesheet"          src/app.scss                      low "styling or assets"
class "translations"        src/i18n/en.json                  low "copy, i18n"
class "tooling config"      eslint.config.mjs                 low "dev tooling config"
class "feature screen"      src/features/cart/CartPage.tsx    low "feature-local UI"
class "leaf component"      src/Button.tsx                    low "leaf component"

echo "# medium"
class "nest service"        src/users/users.service.ts        medium "NestJS unit"
class "spring controller"   user/src/main/java/shop/UnitController.java medium "Spring unit"
class "spring service"      user/src/main/java/shop/impl/UnitServiceImpl.java medium "Spring unit"
class "spring repository"   model/src/main/java/shop/UnitRepository.java medium "Spring unit"
class "spring config file"  app/src/main/resources/application-local.yml medium "runtime configuration"
class "gradle build"        crm/build.gradle                  medium "dependency change"
class "gradle versions"     gradle.properties                 medium "dependency change"
class "shared hook"         src/hooks/useCart.ts              medium "shared primitive, hook or util"
class "shared ui beats leaf" src/components/ui/Button.tsx     medium "shared primitive, hook or util"
class "manifest"            package.json                      medium "dependency change"
class "lockfile"            apps/web/pnpm-lock.yaml           medium "dependency change"
class "anything else"       src/thing.ts                      medium "no rule matched — unsure is medium"

class "requirements file"   requirements.txt                  medium "dependency change"
class "vite inside a word"  src/invites/invite.service.ts     medium "NestJS unit"
class "jest inside a word"  src/lib2/majestic.ts              medium "no rule matched — unsure is medium"
class "secret inside a word" src/secretary/list.ts            medium "no rule matched — unsure is medium"
class "kotlin service"      user/src/main/kotlin/shop/UnitService.kt medium "Spring unit"

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

has "a pattern that does not compile" 2 "RISK_HIGH .* is not a valid pattern" env RISK_HIGH='(reports' bash "$risk" src/thing.ts
mkdir -p docs/review && echo '{"risk":{"hihg":["x"]},"typo":1}' > docs/review/delivery.json
has "an invalid config"               2 'unknown key "typo"'                   bash "$risk" src/thing.ts
rm -rf docs

echo "# input"
has "paths on stdin"   0 '^class: high$'      bash -c "printf 'README.md\n\nsrc/auth/a.ts\n' | bash '$risk'"
has "no paths"         2 '^usage: risk.sh'    bash "$risk"

echo "# a dependency change sharing the chunk"
mixed() { bash "$risk" "$@" 2>&1 | grep -c '^mixed: '; }
eq "bump alone is not mixed"       "$(mixed package.json pnpm-lock.yaml)" 0
eq "bump with source is mixed"     "$(mixed package.json src/a.ts src/b.ts)" 1
eq "workspace package.json counts" "$(mixed apps/web/package.json src/a.ts)" 1
eq "a Gradle build with source is mixed" "$(mixed build.gradle src/main/java/A.java)" 1
eq "no dependency change, no line" "$(mixed src/a.ts)" 0
has "says how many other paths"    0 '^mixed: dependency change shares the chunk with other paths \(2\)' bash "$risk" package.json src/a.ts src/b.ts

echo "# no paths: the change itself"
new_repo changed
mkdir -p src/auth && echo a > src/auth/guard.ts && commit_all
echo b > src/auth/guard.ts && echo c > notes.md
base=$(git rev-parse HEAD^{tree})
has "takes each path that differs from HEAD" 0 'src/auth/guard.ts' bash "$risk"
has "a file git does not track too"          0 'notes.md'          bash "$risk"
echo d > src/auth/guard.ts && commit_all
echo e > later.md
has "DELIVERY_BASE moves the start"          0 'src/auth/guard.ts' env DELIVERY_BASE="$base" bash "$risk"
lacks "and without it only the new work"     'guard.ts'            bash "$risk"

finish
