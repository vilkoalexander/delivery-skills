#!/usr/bin/env bash
# Mechanical pre-scan for jpa-schema-review: one JPA entity, one Spring Data
# repository, or one SQL migration. Heuristic — flags, not a verdict.
#
# No compiler and no common linter sees any of this: a fetch plan, a bulk
# update that leaves stale entities, a migration that locks a table.
#
# Usage: scan.sh <Entity.java | Repository.java | V1__name.sql>
# Env:   MIGRATION_BASE  git ref an applied migration is compared with (default HEAD)
#        MIGRATION_NAME  ERE for a valid migration file name
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <Entity.java | Repository.java | migration.sql>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi

migration_base="${MIGRATION_BASE:-HEAD}"
migration_name="${MIGRATION_NAME:-^(V[0-9]+([._][0-9]+)*|U[0-9]+([._][0-9]+)*|R)__[A-Za-z0-9_]+\.sql$}"

found_any=0

# flag LABEL LINES — prints a finding with the lines that caused it
flag() {
  printf '## %s\n%s\n\n' "$1" "$2"
  found_any=1
}

# report LABEL REGEX — flags every line of the file that matches
report() {
  local matches
  matches=$(grep -nE -- "$2" "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

# report_i — report, ignoring case (SQL keywords)
report_i() {
  local matches
  matches=$(grep -niE -- "$2" "$file")
  [ -n "$matches" ] && flag "$1" "$matches"
}

has() {
  grep -qE -- "$1" "$file"
}

# Prints one row per annotated class, field or method:
#   LINE <tab> ANNOTATIONS <tab> DECLARATION
annotated_declarations() {
  awk '
    function parens(text) { return gsub(/\(/, "(", text) - gsub(/\)/, ")", text) }
    function trimmed(text) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", text); return text }
    {
      line = trimmed($0)
      if (declaration != "") {
        declaration = declaration " " line
      } else if (annotations != "" && depth > 0) {
        annotations = annotations " " line
        depth += parens(line)
        next
      } else if (line ~ /^@[A-Za-z]/ && line !~ /^@interface/) {
        annotations = annotations " " line
        depth = parens(line)
        next
      } else if (annotations == "" || line == "" || line ~ /^(\/\/|\/\*|\*)/) {
        next
      } else {
        declaration = line
        declared_at = NR
      }
      if (declaration ~ /[{;]/) {
        printf "%d\t%s\t%s\n", declared_at, trimmed(annotations), declaration
        annotations = ""
        declaration = ""
      }
    }
  ' "$file"
}

# rows_where ANNOTATIONS_MATCH [ANNOTATIONS_LACK] — rows as "LINE: annotations  declaration"
rows_where() {
  printf '%s\n' "$declarations" | MATCH=$1 LACK=${2:-} awk -F'\t' '
    $2 ~ ENVIRON["MATCH"] && (ENVIRON["LACK"] == "" || $2 !~ ENVIRON["LACK"]) { printf "%s: %s  %s\n", $1, $2, $3 }
  '
}

scan_entity() {
  report "@Data / @EqualsAndHashCode / @Value on an entity — equals and hashCode over every field break sets and trigger lazy loads" \
    '^@(Data|EqualsAndHashCode|Value)\b'
  if has '^@ToString' && has '@(OneToMany|ManyToOne|OneToOne|ManyToMany)' && ! has '@ToString\.Exclude|exclude *=|onlyExplicitlyIncluded'; then
    report "@ToString on an entity with associations — toString loads them, or recurses on a bidirectional pair" '^@ToString'
  fi

  local eager_default eager unsafe_cascade ordinal bags
  eager_default=$(rows_where '@(ManyToOne|OneToOne)' 'FetchType\.LAZY|LAZY')
  [ -n "$eager_default" ] && flag "@ManyToOne / @OneToOne without fetch = LAZY — the default is EAGER: one more query per row, on every query" "$eager_default"

  eager=$(rows_where 'FetchType\.EAGER|fetch *= *EAGER')
  [ -n "$eager" ] && flag "FetchType.EAGER — it cannot be turned off for one query; fetch in the query that needs it" "$eager"

  unsafe_cascade=$(rows_where '@ManyTo(One|Many)[^@]*CascadeType\.(ALL|REMOVE)')
  [ -n "$unsafe_cascade" ] && flag "CascadeType.ALL / REMOVE on @ManyToOne or @ManyToMany — removing this row removes the shared one" "$unsafe_cascade"

  ordinal=$(rows_where '@Enumerated' 'STRING')
  [ -n "$ordinal" ] && flag "@Enumerated without STRING — the ordinal is stored; reordering the enum rewrites the meaning of every row" "$ordinal"

  bags=$(rows_where '@ManyToMany' | grep -E '\bList<' || true)
  [ -n "$bags" ] && flag "@ManyToMany on a List — removing one element deletes and re-inserts the whole join table; use a Set" "$bags"

  report "java.util.Date / Calendar / Timestamp / LocalDateTime column — an instant is Instant or OffsetDateTime on timestamptz" \
    '^[[:space:]]+(private|protected) (java\.util\.)?(Date|Calendar|Timestamp|LocalDateTime) '
  report "double / float column — money and exact quantities are BigDecimal" \
    '^[[:space:]]+(private|protected) (double|float|Double|Float) '
  report "GenerationType.AUTO / TABLE — say which generator; AUTO picks one per dialect and per id type" \
    'GenerationType\.(AUTO|TABLE)'
  report "Hibernate 5 API — removed in Hibernate 6" \
    '@TypeDef|@Type\(type *=|import javax\.persistence\.|hibernate_sequence'

  if has '^@Entity' && has '@(OneToMany|ManyToMany)' && ! has 'new (ArrayList|HashSet|LinkedHashSet|TreeSet)<'; then
    flag "Collection association with no initializer — null on a new entity" \
      "$(grep -nE 'private (List|Set|Collection)<' "$file")"
  fi
}

scan_repository() {
  local unsafe_modifying missing_modifying paged_fetch native_paged unbounded
  unsafe_modifying=$(rows_where '@Modifying' 'clearAutomatically|flushAutomatically' | grep -E '@Query' || true)
  [ -n "$unsafe_modifying" ] && flag "@Modifying without clearAutomatically / flushAutomatically — entities already loaded keep the old values, and pending changes are not written first" "$unsafe_modifying"

  missing_modifying=$(rows_where '@Query\([^@]*"[[:space:]]*([uU][pP][dD][aA][tT][eE]|[dD][eE][lL][eE][tT][eE]|[iI][nN][sS][eE][rR][tT]) ' '@Modifying')
  [ -n "$missing_modifying" ] && flag "Writing @Query without @Modifying — it fails at the first call" "$missing_modifying"

  paged_fetch=$(rows_where '([jJ][oO][iI][nN] +[fF][eE][tT][cC][hH]|@EntityGraph)' | grep -E 'Pageable' || true)
  [ -n "$paged_fetch" ] && flag "Collection fetch with Pageable — Hibernate reads every row and pages in memory (HHH90003004); page the ids, then fetch" "$paged_fetch"

  native_paged=$(rows_where 'nativeQuery *= *true' 'countQuery' | grep -E 'Pageable' || true)
  [ -n "$native_paged" ] && flag "Paged native query without countQuery — the derived count is wrong or fails" "$native_paged"

  report "String concatenation in a query — bind a parameter" \
    '(@Query|createQuery|createNativeQuery)\(.*" *\+ *[a-zA-Z]|JpaSort\.unsafe'
  report "Native query — the entity model does not check it; a renamed column breaks it at run time" \
    'nativeQuery *= *true|createNativeQuery'
  report "Derived delete — loads every matching entity and deletes them one by one" \
    '^[[:space:]]+(void|long|int|Long|Integer|List<[^>]*>) (delete|remove)[A-Za-z]*By[A-Z]'
  unbounded=$(grep -nE '^[[:space:]]+(List|Collection|Set|Stream)<[^>]*Entity> find[A-Za-z]*\(' "$file" | grep -vE 'Pageable|Limit ' || true)
  [ -n "$unbounded" ] && flag "Entity list from a finder with no Pageable — unbounded when the table grows" "$unbounded"
}

# statements — one SQL statement per line, "LINE: text", comments removed
statements() {
  awk '
    function emit() {
      gsub(/[[:space:]]+/, " ", statement)
      if (length(statement) > 220) statement = substr(statement, 1, 220) " …"
      printf "%d:%s\n", started_at, statement
      statement = ""
    }
    { sub(/--.*/, "") }
    /^[[:space:]]*$/ { next }
    {
      if (statement == "") started_at = NR
      statement = statement " " $0
      if ($0 ~ /;[[:space:]]*$/) {
        emit()
      }
    }
    END { if (statement != "") emit() }
  ' "$file"
}

# sql LABEL MATCH [LACK] — flags statements matching MATCH and not LACK, ignoring case
sql() {
  local matches
  matches=$(printf '%s\n' "$sql_statements" | grep -iE -- "$2" || true)
  [ -n "${3:-}" ] && matches=$(printf '%s\n' "$matches" | grep -viE -- "$3" || true)
  [ -n "$matches" ] && flag "$1" "$matches"
}

scan_migration() {
  local name root relative version duplicates
  name=$(basename "$file")
  if ! printf '%s' "$name" | grep -qE -- "$migration_name"; then
    flag "File name is not a migration name — Flyway ignores it or fails" "  $name  (expected V<version>__<description>.sql)"
  fi

  root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$root" ] && [[ $name == V* ]]; then
    relative=$(cd "$(dirname "$file")" && git ls-files --full-name -- "$name" 2>/dev/null)
    if [ -n "$relative" ] && git -C "$root" cat-file -e "$migration_base:$relative" 2>/dev/null \
      && ! git -C "$root" diff --quiet "$migration_base" -- "$relative" 2>/dev/null; then
      flag "Versioned migration changed after $migration_base — an applied migration fails checksum validation at startup; add a new one" "  $relative"
    fi
    version=${name%%__*}
    duplicates=$(find "$(dirname "$file")" -maxdepth 1 -name "${version}__*.sql" | wc -l | tr -d ' ')
    [ "$duplicates" -gt 1 ] && flag "Two migrations share version $version" "$(find "$(dirname "$file")" -maxdepth 1 -name "${version}__*.sql" | sed 's/^/  /')"
  fi

  sql_statements=$(statements)

  sql "CREATE INDEX without CONCURRENTLY — writes to the table are blocked until the build ends" \
    'create +(unique +)?index' 'concurrently'
  sql "CREATE INDEX CONCURRENTLY — cannot run inside a transaction; this migration must be the only statement and be marked non-transactional" \
    'index +concurrently'
  sql "ADD COLUMN ... NOT NULL without DEFAULT — fails on a table that has rows" \
    'add +(column +)?[^,;]*not +null' 'default|generated'
  sql "ADD COLUMN with a volatile default — rewrites the whole table under an exclusive lock" \
    'add +(column +)?[^,;]*default +(gen_random_uuid|uuid_generate|random|clock_timestamp|nextval)'
  sql "SET NOT NULL — scans the whole table under an exclusive lock; add a validated CHECK (col IS NOT NULL) first on a large table" \
    'alter +column +[^ ]+ +set +not +null'
  sql "Column type change — rewrites the table under an exclusive lock" \
    'alter +column +[^ ]+ +(set +data +)?type '
  sql "FOREIGN KEY added without NOT VALID — validates every row while writes to both tables are blocked" \
    'add +constraint[^;]*foreign +key' 'not +valid'
  sql "CHECK added without NOT VALID — scans every row under an exclusive lock" \
    'add +constraint[^;]*check *\(' 'not +valid'
  sql "DROP / RENAME — the version still running reads the old name; ship it one release after the code stopped using it" \
    'drop +(column|table)|rename +(column|to)|drop +constraint'
  sql "UPDATE / DELETE with no WHERE — every row, in one transaction" \
    '^[0-9]+: *(update|delete +from) ' ' where '
  sql "TRUNCATE / LOCK TABLE" \
    '^[0-9]+: *(truncate|lock +table) '
  sql "timestamp without time zone — use timestamptz" \
    '[ (]timestamp([ ,;)]|\()' 'timestamp +with +time +zone|timestamptz'
  sql "Column type to avoid — money, serial, char(n)" \
    '[ (](money|serial|bigserial|smallserial|char\([0-9]+\))[ ,;)]'
}

declarations=""
case "$file" in
  *.sql)
    scan_migration
    ;;
  *.java)
    declarations=$(annotated_declarations)
    kind=other
    if has '^@(Entity|MappedSuperclass|Embeddable)'; then
      kind=entity
      scan_entity
    fi
    if has 'interface [A-Za-z0-9_]+ extends [A-Za-z0-9_.<>, ]*Repository|^@Repository|@Query\('; then
      kind=repository
      scan_repository
    fi
    if [ "$kind" = other ]; then
      echo "not an entity, a repository or a migration — use spring-service-review for $file" >&2
      exit 1
    fi
    ;;
  *)
    echo "not a .java or .sql file: $file" >&2
    exit 1
    ;;
esac

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
