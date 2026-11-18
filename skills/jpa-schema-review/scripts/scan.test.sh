#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

new_repo shop
model=model/src/main/java/shop
migrations=app/src/main/resources/db/migration
mkdir -p $model $migrations

echo "# an entity"
cat > $model/InvoiceEntity.java <<'JAVA'
package shop;

import javax.persistence.Entity;

@Data
@ToString
@Entity
@Table(name = "invoice")
public class InvoiceEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @ManyToOne
    @JoinColumn(name = "customer_id")
    private CustomerEntity customer;

    @ManyToOne(fetch = FetchType.LAZY,
               optional = false)
    private OrganizationEntity organization;

    @OneToMany(mappedBy = "invoice", cascade = CascadeType.ALL, fetch = FetchType.EAGER)
    private List<InvoiceLineEntity> lines;

    @ManyToMany(cascade = CascadeType.ALL)
    private List<TagEntity> tags;

    @Enumerated
    private InvoiceKind kind;

    @Enumerated(EnumType.STRING)
    private InvoiceStatus status;

    private double total;
    private Date created;
}
JAVA
out=$(bash "$scan" $model/InvoiceEntity.java)
flags "@Data / @EqualsAndHashCode / @Value on an entity"
flags "@ToString on an entity with associations"
flags "@ManyToOne / @OneToOne without fetch = LAZY"
eager_default=$(under '@ManyToOne / @OneToOne without fetch = LAZY')
sees  "the association with the default"       'CustomerEntity customer' "$eager_default"
misses "LAZY on a wrapped annotation counts"   'OrganizationEntity' "$eager_default"
flags "FetchType.EAGER"
flags "CascadeType.ALL / REMOVE on @ManyToOne or @ManyToMany"
cascades=$(under 'CascadeType.ALL / REMOVE on @ManyToOne or @ManyToMany')
sees  "the many-to-many cascade"               'TagEntity' "$cascades"
misses "a one-to-many cascade is the normal case" 'InvoiceLineEntity' "$cascades"
flags "@Enumerated without STRING"
ordinal=$(under '@Enumerated without STRING')
sees  "the bare annotation"                    'InvoiceKind kind' "$ordinal"
misses "STRING is fine"                        'InvoiceStatus' "$ordinal"
flags "@ManyToMany on a List"
flags "java.util.Date / Calendar / Timestamp / LocalDateTime column"
flags "double / float column"
flags "GenerationType.AUTO / TABLE"
flags "Hibernate 5 API"
flags "Collection association with no initializer"

echo "# a clean entity"
cat > $model/OrderEntity.java <<'JAVA'
package shop;

@Getter
@Setter
@Entity
public class OrderEntity {
    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    private CustomerEntity customer;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderLineEntity> lines = new ArrayList<>();

    @Enumerated(EnumType.STRING)
    private OrderStatus status;

    private Instant created;
    private BigDecimal total;
}
JAVA
has "nothing to flag"                          0 '^clean' bash "$scan" $model/OrderEntity.java

echo "# a repository"
cat > $model/InvoiceRepository.java <<'JAVA'
package shop;

public interface InvoiceRepository extends JpaRepository<InvoiceEntity, UUID> {

    @Modifying
    @Query("update InvoiceEntity i set i.status = 'PAID' where i.id = :id")
    void markPaid(UUID id);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from InvoiceEntity i where i.created < :before")
    void purge(Instant before);

    @Query("update InvoiceEntity i set i.kind = :kind")
    void setKind(InvoiceKind kind);

    @Query("select i from InvoiceEntity i join fetch i.lines where i.status = :status")
    Page<InvoiceEntity> findByStatusWithLines(String status, Pageable pageable);

    @Query("select i from InvoiceEntity i join fetch i.lines where i.id = :id")
    Optional<InvoiceEntity> findWithLines(UUID id);

    @Query(value = "select * from invoice where status = :status", nativeQuery = true)
    Page<InvoiceEntity> findNative(String status, Pageable pageable);

    @Query("select i from InvoiceEntity i where i.name = '" + NAME + "'")
    List<InvoiceEntity> findNamed();

    void deleteByCustomerId(UUID customerId);

    List<InvoiceEntity> findAllByStatus(String status);

    Page<InvoiceEntity> findByCustomerId(UUID customerId, Pageable pageable);

    Optional<InvoiceEntity> findByNumber(String number);
}
JAVA
out=$(bash "$scan" $model/InvoiceRepository.java)
flags "@Modifying without clearAutomatically / flushAutomatically"
stale=$(under '@Modifying without clearAutomatically')
sees  "the bare @Modifying"                    'markPaid' "$stale"
misses "one that clears and flushes"           'purge' "$stale"
flags "Writing @Query without @Modifying"
sees  "the update with no @Modifying"          'setKind' "$(under 'Writing @Query without @Modifying')"
flags "Collection fetch with Pageable"
paged=$(under 'Collection fetch with Pageable')
sees  "the paged fetch"                        'findByStatusWithLines' "$paged"
misses "a fetch of one row"                    'findWithLines' "$paged"
flags "Paged native query without countQuery"
flags "String concatenation in a query"
flags "Native query"
flags "Derived delete"
flags "Entity list from a finder with no Pageable"
unbounded=$(under 'Entity list from a finder with no Pageable')
sees  "the unbounded list"                     'findAllByStatus' "$unbounded"
misses "a page is bounded"                     'findByCustomerId' "$unbounded"
misses "an optional is one row"                'findByNumber' "$unbounded"

echo "# a migration"
cat > $migrations/V1.002__invoice_due_date.sql <<'SQL'
-- due date for invoices; DROP TABLE in a comment is not a statement
ALTER TABLE invoice ADD COLUMN due_date timestamp NOT NULL DEFAULT now();
ALTER TABLE invoice ADD COLUMN number varchar(20) NOT NULL;
ALTER TABLE invoice ADD COLUMN ref uuid NOT NULL DEFAULT gen_random_uuid();
UPDATE invoice
   SET due_date = created + interval '30 days';
UPDATE invoice SET number = 'n/a' WHERE number IS NULL;
create index idx_invoice_status on invoice (status);
CREATE INDEX CONCURRENTLY idx_invoice_due ON invoice (due_date);
ALTER TABLE invoice ADD CONSTRAINT fk_invoice_customer FOREIGN KEY (customer_id) REFERENCES customer (id);
ALTER TABLE invoice ADD CONSTRAINT fk_invoice_org FOREIGN KEY (org_id) REFERENCES org (id) NOT VALID;
ALTER TABLE invoice ADD CONSTRAINT total_positive CHECK (total >= 0);
ALTER TABLE invoice ALTER COLUMN status SET NOT NULL;
ALTER TABLE invoice ALTER COLUMN total TYPE numeric(12, 2);
ALTER TABLE invoice DROP COLUMN legacy_ref;
ALTER TABLE invoice RENAME COLUMN ref TO reference;
TRUNCATE invoice_cache;
CREATE TABLE price (id serial PRIMARY KEY, amount money, at timestamptz);
SQL
out=$(bash "$scan" $migrations/V1.002__invoice_due_date.sql)
flags "CREATE INDEX without CONCURRENTLY"
plain_index=$(under 'CREATE INDEX without CONCURRENTLY')
sees  "the plain index, in any case"           'idx_invoice_status' "$plain_index"
misses "a concurrent index"                    'idx_invoice_due' "$plain_index"
flags "CREATE INDEX CONCURRENTLY — cannot run inside a transaction"
flags "ADD COLUMN ... NOT NULL without DEFAULT"
no_default=$(under 'ADD COLUMN ... NOT NULL without DEFAULT')
sees  "the column with no default"             'number varchar' "$no_default"
misses "a column with a default"               'due_date' "$no_default"
flags "ADD COLUMN with a volatile default"
flags "SET NOT NULL"
flags "Column type change"
flags "FOREIGN KEY added without NOT VALID"
foreign=$(under 'FOREIGN KEY added without NOT VALID')
sees  "the validated key"                      'fk_invoice_customer' "$foreign"
misses "a NOT VALID key"                       'fk_invoice_org' "$foreign"
flags "CHECK added without NOT VALID"
flags "DROP / RENAME"
dropped=$(under 'DROP / RENAME')
eq    "drop and rename, not the comment"       "$(printf '%s\n' "$dropped" | wc -l | tr -d ' ')" 2
flags "UPDATE / DELETE with no WHERE"
unfiltered=$(under 'UPDATE / DELETE with no WHERE')
sees  "the statement that wraps, at its first line" '^5: UPDATE invoice SET due_date' "$unfiltered"
misses "an update with a where"                "n/a" "$unfiltered"
flags "TRUNCATE / LOCK TABLE"
flags "timestamp without time zone"
zoneless=$(under 'timestamp without time zone')
sees  "the timestamp column"                   'due_date timestamp' "$zoneless"
misses "timestamptz is fine"                   'CREATE TABLE price' "$zoneless"
flags "Column type to avoid"
unflags "File name is not a migration name"
unflags "Versioned migration changed"

echo "# migration history"
echo "create table a (id uuid);" > $migrations/V1.001__init.sql
commit_all
has "a merged migration, untouched"            0 '^clean' bash "$scan" $migrations/V1.001__init.sql
echo "create table b (id uuid);" >> $migrations/V1.001__init.sql
out=$(bash "$scan" $migrations/V1.001__init.sql)
flags "Versioned migration changed after HEAD"
git checkout -q -- $migrations/V1.001__init.sql
base=$(git rev-parse --abbrev-ref HEAD)
git switch -q -c feature
echo "create table b (id uuid);" >> $migrations/V1.001__init.sql
commit_all edit
has "MIGRATION_BASE names the base branch"     0 "Versioned migration changed after $base" env MIGRATION_BASE="$base" bash "$scan" $migrations/V1.001__init.sql
has "against HEAD the edit is not seen"        0 '^clean' bash "$scan" $migrations/V1.001__init.sql

echo "create table c (id uuid);" > $migrations/V1.001__again.sql
out=$(bash "$scan" $migrations/V1.001__again.sql)
flags "Two migrations share version V1.001"
echo "create table d (id uuid);" > $migrations/add_table.sql
out=$(bash "$scan" $migrations/add_table.sql)
flags "File name is not a migration name"
echo "create or replace view v as select 1;" > $migrations/R__views.sql
has "a repeatable migration"                   0 '^clean' bash "$scan" $migrations/R__views.sql
cp $migrations/add_table.sql $migrations/2024_01_add.sql
has "MIGRATION_NAME sets the project's pattern" 0 '^clean' env MIGRATION_NAME='^[0-9_]+[a-z]+\.sql$' bash "$scan" $migrations/2024_01_add.sql

echo "# usage"
echo "public class InvoiceService {}" > $model/InvoiceService.java
has "a class of another kind"                  1 'use spring-service-review' bash "$scan" $model/InvoiceService.java
echo "x" > notes.txt
has "another extension"                        1 'not a .java or .sql file' bash "$scan" notes.txt
has "no argument"                              1 'usage: scan.sh' bash "$scan"
has "a missing file"                           1 'not found: nope.sql' bash "$scan" nope.sql

finish
