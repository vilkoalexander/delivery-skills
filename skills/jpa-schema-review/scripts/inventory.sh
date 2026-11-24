#!/usr/bin/env bash
# Live persistence inventory for jpa-schema-review: the settings that change
# the rules, the entity base classes and conventions in use, the repositories,
# and where the migrations stand.
#
# Usage: scripts/inventory.sh [root]
#   root is the directory holding the build file. Auto-detected from the
#   current directory upward when omitted.
# Env:   MIGRATION_NAME  ERE for a valid migration file name, as in scan.sh
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

# Output is bounded: INVENTORY_LIMIT lines per section (default 40), overflow
# reported as a count.
limit="${INVENTORY_LIMIT:-40}"
migration_name="${MIGRATION_NAME:-^(V[0-9]+([._][0-9]+)*|U[0-9]+([._][0-9]+)*|R)__[A-Za-z0-9_]+\.sql$}"

cap() {
  awk -v limit="$limit" '
    NR <= limit { print; next }
    END { if (NR > limit) printf "  … +%d more lines (raise INVENTORY_LIMIT=%d to see them)\n", NR - limit, limit }
  '
}

indent() {
  sed 's/^/  /'
}

or_none() {
  awk '{ print; seen = 1 } END { if (!seen) print "  none" }'
}

build_file_in() {
  [ -f "$1/settings.gradle" ] || [ -f "$1/settings.gradle.kts" ] || [ -f "$1/build.gradle" ] \
    || [ -f "$1/build.gradle.kts" ] || [ -f "$1/pom.xml" ]
}

root="${1:-}"
if [ -z "$root" ]; then
  dir=$PWD
  while [ "$dir" != / ]; do
    if build_file_in "$dir"; then root=$dir; fi
    dir=$(dirname "$dir")
  done
fi
if [ -z "$root" ] || [ ! -d "$root" ]; then
  echo "build root not found — pass it: inventory.sh <dir>" >&2
  exit 1
fi
cd "$root" || exit 1
echo "root: $root"

without_build_output() {
  grep -vE '/(build|target|bin|node_modules)/'
}

main_sources=$(find . -name '*.java' -path '*/src/main/*' 2>/dev/null | without_build_output | sed 's|^\./||' | sort)

# files_with PATTERN — main sources whose text matches PATTERN
files_with() {
  # shellcheck disable=SC2086
  [ -n "$main_sources" ] && grep -lE -- "$1" $main_sources 2>/dev/null
}

# tally — reads values on stdin; prints "3 x, 1 y", most frequent first
tally() {
  sort | uniq -c | sort -k1,1rn -k2 | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $1, $2 } END { print "" }'
}

# count_of PATTERN FILES — how many lines in FILES match
count_of() {
  local pattern=$1
  shift
  [ $# -gt 0 ] || { echo 0; return; }
  grep -hE -- "$pattern" "$@" 2>/dev/null | wc -l | tr -d ' '
}

entities=$(files_with '^@Entity')
repositories=$(files_with 'interface [A-Za-z0-9_]+ extends [A-Za-z0-9_.<>, ]*Repository')

echo
echo "=== settings that change the rules"
config=$(find . \( -name 'application*.yml' -o -name 'application*.yaml' -o -name 'application*.properties' \) \
  -path '*/src/main/*' 2>/dev/null | without_build_output)
if [ -n "$config" ]; then
  # shellcheck disable=SC2086
  grep -HnE 'open-in-view|ddl-auto|default_schema|default-schema|batch_size|jdbc\.time_zone|baseline|out-of-order|locations|flyway.*(schemas|enabled|mixed)' $config 2>/dev/null \
    | sed -E 's|^\./||; s/:[[:space:]]+/: /' | indent | cap | or_none
else
  echo "  no application.yml / application.properties found"
fi

echo
echo "=== entity base classes and shared mappings"
{
  files_with '^@MappedSuperclass' | sed 's/^/  mapped superclass  /'
  files_with '^@Embeddable' | sed 's/^/  embeddable         /'
  files_with 'implements AttributeConverter|@Converter' | sed 's/^/  converter          /'
} | cap | or_none

echo
echo "=== entity conventions in use (follow the majority)"
# shellcheck disable=SC2086
if [ -n "$entities" ]; then
  total=$(printf '%s\n' "$entities" | wc -l | tr -d ' ')
  row() {
    printf '  %-34s %s\n' "$1" "$2"
  }
  row "entities" "$total"
  row "@Data on an entity" "$(grep -lE '^@Data' $entities | wc -l | tr -d ' ')"
  row "@Getter + @Setter" "$(grep -lE '^@Getter' $entities | wc -l | tr -d ' ')"
  row "own equals()" "$(grep -lE 'boolean equals\(' $entities | wc -l | tr -d ' ')"
  row "@Version" "$(grep -lE '@Version' $entities | wc -l | tr -d ' ')"
  row "to-one LAZY / all to-one" "$(count_of '@(ManyToOne|OneToOne)\(.*LAZY' $entities) / $(count_of '@(ManyToOne|OneToOne)' $entities)"
  row "FetchType.EAGER" "$(count_of 'FetchType\.EAGER' $entities)"
  row "@Enumerated STRING / all" "$(count_of '@Enumerated\(.*STRING' $entities) / $(count_of '@Enumerated' $entities)"
  row "id generation" "$(grep -hoE '@GeneratedValue(\([^)]*\))?|@UuidGenerator|@GenericGenerator' $entities | tr -d ' ' | tally)"
  row "time types" "$(grep -hoE 'private (Instant|OffsetDateTime|ZonedDateTime|LocalDateTime|LocalDate|Date|Timestamp) ' $entities | awk '{ print $2 }' | tally)"
  row "schemas" "$(grep -hoE 'schema *= *[A-Za-z_.]+' $entities | sed -E 's/schema *= *//' | tally)"
else
  echo "  no @Entity found"
fi

echo
echo "=== repositories"
if [ -n "$repositories" ]; then
  # shellcheck disable=SC2086
  printf '  %s repositories   @Query: %s   native: %s   @Modifying: %s   @EntityGraph: %s\n' \
    "$(printf '%s\n' "$repositories" | wc -l | tr -d ' ')" \
    "$(count_of '@Query' $repositories)" \
    "$(count_of 'nativeQuery *= *true' $repositories)" \
    "$(count_of '@Modifying' $repositories)" \
    "$(count_of '@EntityGraph' $repositories)"
  # shellcheck disable=SC2086
  grep -hoE 'extends [A-Za-z]*Repository[A-Za-z]*' $repositories | sort | uniq -c | sort -rn | indent | cap
else
  echo "  none"
fi

echo
echo "=== specifications and projections — reuse before writing a query"
printf '%s\n' "$main_sources" | grep -E '(Specification|Spec|Projection|View)\.java$' | indent | cap | or_none

echo
echo "=== migrations"
migration_dirs=$(find . -type d \( -path '*/db/migration' -o -path '*/db/migration/*' \) -path '*/src/main/*' 2>/dev/null | without_build_output)
if [ -z "$migration_dirs" ]; then
  echo "  no db/migration directory under src/main"
else
  while IFS= read -r migration_dir; do
    count=$(find "$migration_dir" -maxdepth 1 -name '*.sql' | wc -l | tr -d ' ')
    [ "$count" -gt 0 ] || continue
    echo "  ${migration_dir#./}: $count files"
    find "$migration_dir" -maxdepth 1 -name 'V*.sql' -exec basename {} \; | sort -t_ -k1,1V 2>/dev/null | tail -5 | sed 's/^/    /'
    repeatable=$(find "$migration_dir" -maxdepth 1 -name 'R__*.sql' | wc -l | tr -d ' ')
    [ "$repeatable" -gt 0 ] && echo "    repeatable: $repeatable"
    unnamed=$(find "$migration_dir" -maxdepth 1 -name '*.sql' -exec basename {} \; | grep -vE -- "$migration_name" || true)
    [ -n "$unnamed" ] && printf '%s\n' "$unnamed" | sed 's/^/    not a migration name: /'
  done <<< "$migration_dirs"
fi
changed=$(git status --porcelain -- '*.sql' 2>/dev/null | grep -E '^( M|M |MM)' | grep -E '/V[0-9][^/]*\.sql$' || true)
if [ -n "$changed" ]; then
  echo "  versioned migrations modified in the working tree (an applied one must not change):"
  printf '%s\n' "$changed" | indent | indent
fi
