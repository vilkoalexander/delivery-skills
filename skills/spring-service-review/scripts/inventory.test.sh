#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo shop
main=billing/src/main/java/shop
test=billing/src/test/java/shop
mkdir -p $main/controller $main/service/impl $main/util $main/error $main/persistence $test billing/src/main/resources billing/build/src/main/java/shop model/src/main/java/shop
cat > settings.gradle <<'GRADLE'
include 'billing'
include 'model'
GRADLE
cat > build.gradle <<'GRADLE'
plugins { id 'checkstyle' }
java { sourceCompatibility = JavaVersion.VERSION_17 }
tasks.withType(JavaCompile) { options.compilerArgs << '-Xlint:deprecation' }
GRADLE
printf 'springBootPlugin=3.1.4\nlombok=1.18.28\n' > gradle.properties
printf 'spring:\n  jpa:\n    open-in-view: false\n' > billing/src/main/resources/application.yml

cat > $main/controller/InvoiceController.java <<'JAVA'
@RestController
public class InvoiceController {
    @GetMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN') or hasPermission(#id, 'Invoice', 'READ')")
    public Invoice get(@PathVariable UUID id) { return null; }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('USER') or hasPermission(#invoiceId, 'Invoice', 'WRITE')")
    public Invoice update(@PathVariable UUID invoiceId) { return null; }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable UUID id) { }
}
JAVA
echo "public class OrderController {}"                           > $main/controller/OrderController.java
echo "public interface InvoiceService {}"                        > $main/service/InvoiceService.java
echo "public class InvoiceServiceImpl { RestTemplate rest; }"    > $main/service/impl/InvoiceServiceImpl.java
echo "public class OrderServiceImpl { MinioClient files; RestTemplate rest; }" > $main/service/impl/OrderServiceImpl.java
echo "public class MoneyUtils {}"                                > $main/util/MoneyUtils.java
echo "public class DateUtils {}"                                 > $main/util/DateUtils.java
echo "@RestControllerAdvice public class GlobalExceptionHandler {}" > $main/error/GlobalExceptionHandler.java
echo "public @interface ValidName {}"                            > $main/persistence/ValidName.java
echo "public class InvoiceRepository {}"                         > $main/persistence/InvoiceRepository.java
echo "public class InvoiceEntity {}"                             > model/src/main/java/shop/InvoiceEntity.java
echo "public class Stale {}"                                     > billing/build/src/main/java/shop/StaleController.java
printf '%s\n' '@SpringBootTest' 'public abstract class CoreTestTemplate {' '    @MockBean Clock clock;' '}' > $test/CoreTestTemplate.java
echo "class InvoiceControllerTest extends CoreTestTemplate {}"   > $test/InvoiceControllerTest.java
echo "class InvoiceServiceTest {}"                               > $test/InvoiceServiceTest.java

out=$(bash "$inventory")
sees  "the root is found from the build file"  "^root: $tmp/shop$" "$out"

versions=$(under versions)
sees  "Spring Boot version"                    'springBootPlugin=3.1.4' "$versions"
sees  "Java version"                           'JavaVersion.VERSION_17' "$versions"

analyzers=$(under 'analyzers in the build')
sees  "a configured analyzer"                  '^  checkstyle +configured$' "$analyzers"
sees  "an absent analyzer"                     '^  errorprone +absent$' "$analyzers"
sees  "javac flags"                            '^  javac flags +-Xlint:deprecation$' "$analyzers"

modules=$(under modules)
sees  "counts per module"                      '^  billing +controllers:2 +services:3 +repositories:1 +entities:0 +tests:3$' "$modules"
sees  "a module with no tests"                 '^  model +controllers:0 +services:0 +repositories:0 +entities:1 +tests:0$' "$modules"

shared=$(under 'shared primitives')
sees  "helpers grouped by package"             '^  shop/util +DateUtils, MoneyUtils$' "$shared"
sees  "the error package"                      '^  shop/error +GlobalExceptionHandler$' "$shared"
misses "a service is not a shared primitive"   'InvoiceServiceImpl' "$shared"

handlers=$(under 'exception handlers and custom annotations')
sees  "the advice"                             '^  advice +billing/.*/GlobalExceptionHandler.java$' "$handlers"
sees  "a custom annotation"                    '^  annotation +billing/.*/ValidName.java$' "$handlers"

authorized=$(under 'how handlers are authorized')
sees  "expressions grouped, names blanked"     "^ +2 @PreAuthorize\(\"hasRole\('…'\) or hasPermission\(#…, 'Invoice', '…'\)\"\)$" "$authorized"
sees  "handlers against annotations"           '^  handlers: 3   authorization annotations: 2$' "$authorized"

clients=$(under 'remote clients in use')
sees  "the most used client first"             '^ +2 RestTemplate$' "$(printf '%s\n' "$clients" | head -1)"
sees  "another client"                         '^ +1 MinioClient$' "$clients"

sees  "a setting that changes the review"      'application.yml:3: open-in-view: false' "$(under 'settings that change the review')"

bases=$(under 'test bases and fixtures')
sees  "the test base class"                    'CoreTestTemplate.java$' "$bases"
sees  "context and mock counts"                '^  classes with @SpringBootTest: 1   @MockBean/@SpyBean: 1$' "$bases"

untested=$(under 'no test class')
sees  "a unit with no test"                    'OrderController.java$' "$untested"
sees  "an impl with no test"                   'OrderServiceImpl.java$' "$untested"
misses "a tested controller"                   'InvoiceController' "$untested"
misses "an impl whose interface has a test"    'InvoiceServiceImpl' "$untested"
misses "build output is not source"            'StaleController' "$out"

echo "# REVIEW_FILES limits the missing-test check"
out=$(REVIEW_FILES="$main/controller/OrderController.java $main/util/MoneyUtils.java" bash "$inventory")
untested=$(under 'no test class among REVIEW_FILES')
sees  "the file under review"                  'OrderController.java$' "$untested"
misses "a unit that is not under review"       'OrderServiceImpl' "$untested"

echo "# limits and roots"
out=$(INVENTORY_LIMIT=1 bash "$inventory")
sees  "sections are cut with a count"          '… \+1 more lines \(raise INVENTORY_LIMIT=1' "$(under modules)"
cd billing/src || exit 1
sees  "the root is the outermost build file"   "^root: $tmp/shop$" "$(bash "$inventory")"
cd "$tmp/shop" || exit 1
sees  "the root can be passed"                 "^root: $tmp/shop$" "$(cd / && bash "$inventory" "$tmp/shop")"
mkdir -p "$tmp/empty" && cd "$tmp/empty" || exit 1
has "no build file"                            1 'build root not found' bash "$inventory"

finish
