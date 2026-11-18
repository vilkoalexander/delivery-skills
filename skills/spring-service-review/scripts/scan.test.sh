#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

new_repo shop
main=billing/src/main/java/shop
test=billing/src/test/java/shop
mkdir -p $main $test

echo "# a service"
cat > $main/InvoiceServiceImpl.java <<'JAVA'
package shop;

import javax.persistence.EntityManager;
import jakarta.transaction.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class InvoiceServiceImpl implements InvoiceService {

    private final InvoiceRepository invoiceRepository;
    private final ModelMapper modelMapper;
    private int processed = 0;
    @Autowired
    private Clock clock;

    @Override
    public InvoiceEntity create(InvoiceRequest request) {
        var entity = modelMapper.map(request, InvoiceEntity.class);
        log.info("calling saveWithLines(entity) next");
        return saveWithLines(entity);
    }

    @Transactional
    public InvoiceEntity saveWithLines(InvoiceEntity entity) {
        return invoiceRepository.save(entity);
    }

    @Transactional
    void audit(UUID id) {
    }

    @Override
    @Transactional
    public void pay(UUID id) throws IOException {
        var invoice = invoiceRepository.findById(id).get();
        var response = httpClient.newCall(request).execute();
        eventPublisher.publishEvent(new InvoicePaidEvent(id));
        log.info("Paid invoice " + id);
        log.debug("charged {}", invoice.getPaymentToken());
        log.debug("token refreshed for {}", id);
    }

    @Override
    @Transactional(readOnly = true)
    public List<InvoiceEntity> overdue() {
        if (invoiceRepository.count() == 0 || status == "OVERDUE") {
            return invoiceRepository.findAll();
        }
        try {
            Thread.sleep(10);
        } catch (Exception e) {
            log.error("failed");
        }
        try {
            run();
        } catch (IllegalStateException e) {
            throw new ApiException(e);
        }
        var due = LocalDate.now();
        var total = new BigDecimal(0.1);
        double totalAmount = 1;
        return List.of();
    }
}
JAVA
out=$(bash "$scan" $main/InvoiceServiceImpl.java)
flags "javax\.\* import"
flags "Proxied annotation on a method that is not public"
sees  "names the non-public method"            '^[0-9]+: void audit' "$(under 'Proxied annotation on a method that is not public')"
flags "Self-invocation of a proxied method"
calls=$(under 'Self-invocation of a proxied method')
sees  "the self call"                          'return saveWithLines\(entity\);' "$calls"
misses "a name inside a string is not a call"  'calling saveWithLines' "$calls"
flags "@Transactional method throws a checked exception"
flags "Remote call inside a @Transactional method"
flags "jakarta/javax @Transactional"
flags "Event published inside a transaction"
flags "Field injection"
flags "Mutable field in a singleton bean"
mutable=$(under 'Mutable field in a singleton bean')
sees  "the counter"                            'private int processed' "$mutable"
misses "a final field is not mutable"          'invoiceRepository' "$mutable"
flags "findAll\(\) with no page"
flags "Optional.get\(\)"
flags "Request mapped straight onto an entity"
flags "catch of Exception"
flags "catch block that neither rethrows the exception nor passes it to the logger"
swallowed=$(under 'catch block that neither rethrows the exception')
eq    "only the swallowing catch"              "$(printf '%s\n' "$swallowed" | wc -l | tr -d ' ')" 1
flags "String concatenation in a log call"
flags "Secret-looking value in a log call"
secrets=$(under 'Secret-looking value in a log call')
sees  "the token argument"                     'getPaymentToken' "$secrets"
misses "the word in the message is not one"    'token refreshed' "$secrets"
flags "String compared with == or !="
flags "now\(\) with no Clock"
flags "BigDecimal from a double literal"
flags "Money-looking value as double"
flags "Thread.sleep"
flags "No test class for this unit"

echo "# a clean service with a test"
cat > $main/OrderServiceImpl.java <<'JAVA'
package shop;

@Service
@RequiredArgsConstructor
public class OrderServiceImpl implements OrderService {

    private static final int LIMIT = 10;
    private final OrderRepository orderRepository;

    @Override
    @Transactional(readOnly = true)
    public Order get(UUID id) {
        return orderRepository.findById(id).map(this::toOrder).orElseThrow(() -> new ApiException(NOT_FOUND));
    }

    private Order toOrder(OrderEntity entity) {
        return new Order(entity.getId());
    }
}
JAVA
echo "class OrderServiceTest {}" > $test/OrderServiceTest.java
has "nothing to flag"                          0 '^clean' bash "$scan" $main/OrderServiceImpl.java

echo "# a controller"
cat > $main/InvoiceController.java <<'JAVA'
package shop;

@RestController
@RequiredArgsConstructor
@RequestMapping("/invoices")
public class InvoiceController {

    private final InvoiceService invoiceService;
    private final InvoiceRepository invoiceRepository;

    @GetMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN') or hasPermission(#id, 'Invoice', 'READ')")
    public ResponseEntity<Invoice> get(@PathVariable UUID id) {
        return ResponseEntity.ok(invoiceService.get(id));
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<Invoice> create(@RequestBody InvoiceRequest request,
                                          @RequestHeader UUID orgId) {
        return ResponseEntity.ok(invoiceService.create(request));
    }

    @PutMapping("/{id}")
    @Transactional
    public InvoiceEntity update(@PathVariable UUID id, @RequestBody @Valid InvoiceRequest request) {
        return invoiceRepository.save(null);
    }
}
JAVA
out=$(bash "$scan" $main/InvoiceController.java)
flags "Handler with no authorization annotation"
handlers=$(under 'Handler with no authorization annotation')
sees  "the unannotated handler"                'InvoiceEntity update' "$handlers"
misses "an annotated handler is not listed"    'Invoice> get' "$handlers"
flags "@RequestBody without @Valid"
unvalidated=$(under '@RequestBody without @Valid')
sees  "the body of create, though it wraps"    '@RequestBody InvoiceRequest request' "$unvalidated"
misses "a validated body is not listed"        '@Valid' "$unvalidated"
flags "Entity type in a controller"
entities=$(under 'Entity type in a controller')
sees  "the entity return type"                 'InvoiceEntity update' "$entities"
misses "ResponseEntity is not an entity"       'ResponseEntity<Invoice> get' "$entities"
flags "Repository in a controller"
flags "@Transactional in a controller"

echo "# authorization by annotation, by class, or not at all"
out=$(AUTHZ="" bash "$scan" $main/InvoiceController.java)
unflags "Handler with no authorization annotation"
out=$(AUTHZ='@OrgScoped' bash "$scan" $main/InvoiceController.java)
sees  "AUTHZ names the project's annotation"   'Invoice> get' "$(under 'Handler with no authorization annotation')"
printf '%s\n' '@RestController' '@PreAuthorize("isAuthenticated()")' 'public class AdminController {' \
  '    @GetMapping' '    public List<Role> roles() {' '        return List.of();' '    }' '}' > $main/AdminController.java
echo "class AdminControllerTest {}" > $test/AdminControllerTest.java
out=$(bash "$scan" $main/AdminController.java)
unflags "Handler with no authorization annotation"

echo "# REMOTE_CALL names the project's clients"
out=$(REMOTE_CALL='nothingLikeThis' bash "$scan" $main/InvoiceServiceImpl.java)
unflags "Remote call inside a @Transactional method"

echo "# old platform"
printf '%s\n' '@Configuration' 'public class SecurityConfig extends WebSecurityConfigurerAdapter {' \
  '    void configure(HttpSecurity http) { http.authorizeRequests().antMatchers("/x").permitAll(); }' '}' > $main/SecurityConfig.java
out=$(bash "$scan" $main/SecurityConfig.java)
flags "Removed Spring Security API"

echo "# an interface is not a bean"
printf '%s\n' 'public interface InvoiceService {' '    @Transactional' '    InvoiceEntity create(InvoiceRequest request);' '}' > $main/InvoiceService.java
out=$(bash "$scan" $main/InvoiceService.java)
unflags "Proxied annotation on a method that is not public"
unflags "No test class for this unit"

echo "# a test class"
cat > $test/InvoiceServiceTest.java <<'JAVA'
package shop;

@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class InvoiceServiceTest extends CoreTestTemplate {
    @MockBean
    private Clock clock;

    @Test
    void createsAnInvoice() {
        service.create(request);
    }

    @Test
    @Sql(statements = {
            "insert into invoice values (1)"
    })
    void findsAnInvoice() {
        assertEquals(1, service.overdue().size());
    }

    @Test
    @Disabled
    void paysAnInvoice() throws Exception {
        var due = LocalDate.now();
        mockMvc.perform(post("/invoices/1/pay")).andExpect(status().isNoContent());
    }
}
JAVA
out=$(bash "$scan" $test/InvoiceServiceTest.java)
flags "Test with no assertion"
unasserted=$(under 'Test with no assertion')
sees  "the test with no assertion"             'createsAnInvoice' "$unasserted"
misses "assertEquals is an assertion"          'findsAnInvoice' "$unasserted"
misses "andExpect is an assertion"             'paysAnInvoice' "$unasserted"
misses "@TestMethodOrder is not @Test"         'class InvoiceServiceTest' "$unasserted"
flags "@Disabled with no reason"
flags "@MockBean / @SpyBean"
unflags "now\(\) with no Clock"
unflags "No test class for this unit"
unflags "Mutable field in a singleton bean"

echo "# usage"
has "no argument"                              1 'usage: scan.sh' bash "$scan"
has "a missing file"                           1 'not found: nope.java' bash "$scan" nope.java

finish
