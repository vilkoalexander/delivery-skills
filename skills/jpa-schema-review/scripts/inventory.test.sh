#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo shop
model=model/src/main/java/shop
resources=app/src/main/resources
mkdir -p $model/spec $resources/db/migration model/build/src/main/java/shop
echo "include 'model'" > settings.gradle
cat > $resources/application.yml <<'YML'
spring:
  flyway:
    baseline-on-migrate: on
  jpa:
    open-in-view: false
    hibernate:
      ddl-auto: none
YML

cat > $model/BaseEntity.java <<'JAVA'
@MappedSuperclass
public abstract class BaseEntity {
    private Instant created;
}
JAVA
cat > $model/InvoiceEntity.java <<'JAVA'
@Getter
@Setter
@Entity
@Table(name = "invoice", schema = SCHEMA_BILLING)
public class InvoiceEntity extends BaseEntity {
    @Id
    @GeneratedValue
    private UUID id;
    @Version
    private Long version;
    @ManyToOne(fetch = FetchType.LAZY)
    private CustomerEntity customer;
    @ManyToOne
    private OrganizationEntity organization;
    @Enumerated(EnumType.STRING)
    private InvoiceStatus status;
    @Enumerated
    private InvoiceKind kind;
    private Instant paid;
    private LocalDate due;
    public boolean equals(Object other) { return false; }
}
JAVA
cat > $model/CustomerEntity.java <<'JAVA'
@Data
@Entity
@Table(name = "customer", schema = SCHEMA_BILLING)
public class CustomerEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @OneToMany(fetch = FetchType.EAGER)
    private List<InvoiceEntity> invoices;
    private Instant created;
}
JAVA
echo "@Embeddable public class Address {}"                                          > $model/Address.java
echo "public class MoneyConverter implements AttributeConverter<Money, Long> {}"    > $model/MoneyConverter.java
cat > $model/InvoiceRepository.java <<'JAVA'
public interface InvoiceRepository extends JpaRepository<InvoiceEntity, UUID> {
    @Modifying
    @Query("update InvoiceEntity i set i.status = 'PAID'")
    void payAll();
    @Query(value = "select * from invoice", nativeQuery = true)
    List<InvoiceEntity> everything();
    @EntityGraph(attributePaths = "customer")
    Optional<InvoiceEntity> findWithCustomerById(UUID id);
}
JAVA
echo "public interface CustomerRepository extends JpaRepository<CustomerEntity, Long> {}" > $model/CustomerRepository.java
echo "public class InvoiceSpecification {}"                                         > $model/spec/InvoiceSpecification.java
echo "public interface InvoiceTotalProjection {}"                                   > $model/InvoiceTotalProjection.java
echo "@Entity public class StaleEntity {}"                                          > model/build/src/main/java/shop/StaleEntity.java
for name in V1.001__init V1.002__customer V1.010__invoice V1.009__index R__views add_table; do
  echo "select 1;" > $resources/db/migration/$name.sql
done
commit_all

out=$(bash "$inventory")
settings=$(under 'settings that change the rules')
sees  "open-in-view"                           'application.yml:5: open-in-view: false' "$settings"
sees  "ddl-auto"                               'application.yml:7: ddl-auto: none' "$settings"
sees  "a Flyway setting"                       'baseline-on-migrate: on' "$settings"

bases=$(under 'entity base classes and shared mappings')
sees  "the mapped superclass"                  '^  mapped superclass +model/.*/BaseEntity.java$' "$bases"
sees  "an embeddable"                          '^  embeddable +model/.*/Address.java$' "$bases"
sees  "a converter"                            '^  converter +model/.*/MoneyConverter.java$' "$bases"

conventions=$(under 'entity conventions in use')
value() { printf '%s\n' "$conventions" | sed -nE "s|^  $1  +||p"; }
eq    "entities, without build output"         "$(value entities)" 2
eq    "@Data on an entity"                     "$(value '@Data on an entity')" 1
eq    "getter and setter"                      "$(value '@Getter \+ @Setter')" 1
eq    "own equals"                             "$(value 'own equals\(\)')" 1
eq    "@Version"                               "$(value '@Version')" 1
eq    "lazy to-one of all to-one"              "$(value 'to-one LAZY / all to-one')" "1 / 2"
eq    "eager"                                  "$(value 'FetchType.EAGER')" 1
eq    "string enums of all enums"              "$(value '@Enumerated STRING / all')" "1 / 2"
eq    "id generation"                      "$(value 'id generation')" "1 @GeneratedValue, 1 @GeneratedValue(strategy=GenerationType.IDENTITY)"
eq    "time types"                             "$(value 'time types')" "2 Instant, 1 LocalDate"
eq    "schemas"                                "$(value schemas)" "2 SCHEMA_BILLING"

repositories=$(under repositories)
sees  "repository counts"                      '^  2 repositories   @Query: 2   native: 1   @Modifying: 1   @EntityGraph: 1$' "$repositories"
sees  "the base interface in use"              '^ +2 extends JpaRepository$' "$repositories"

reusable=$(under 'specifications and projections')
sees  "a specification"                        'spec/InvoiceSpecification.java$' "$reusable"
sees  "a projection"                           'InvoiceTotalProjection.java$' "$reusable"

migrations=$(under migrations)
sees  "the directory and its count"            '^  app/src/main/resources/db/migration: 6 files$' "$migrations"
eq    "the last versioned migration, by version" "$(printf '%s\n' "$migrations" | grep -E '^    V' | tail -1 | tr -d ' ')" "V1.010__invoice.sql"
sees  "repeatable migrations"                  '^    repeatable: 1$' "$migrations"
sees  "a file that is not a migration"         'not a migration name: add_table.sql' "$migrations"
misses "nothing modified yet"                  'modified in the working tree' "$migrations"

echo "# an edited migration"
echo "select 2;" >> $resources/db/migration/V1.001__init.sql
out=$(bash "$inventory")
sees  "a modified versioned migration"         'V1.001__init.sql' "$(under migrations | sed -n '/modified in the working tree/,$p')"

echo "# no persistence, no build"
mkdir -p "$tmp/plain/src/main/java" && cd "$tmp/plain" && touch build.gradle
out=$(bash "$inventory")
sees  "no entities"                            'no @Entity found' "$(under 'entity conventions in use')"
sees  "no repositories"                        '^  none$' "$(under repositories)"
sees  "no migrations"                          'no db/migration directory' "$(under migrations)"
sees  "no config"                              'no application.yml' "$(under 'settings that change the rules')"
mkdir -p "$tmp/empty" && cd "$tmp/empty" || exit 1
has "no build file"                            1 'build root not found' bash "$inventory"

finish
