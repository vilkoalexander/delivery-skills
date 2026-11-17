#!/usr/bin/env bash
# Live backend inventory for spring-service-review: versions, analyzers,
# modules, shared primitives that already exist, how handlers are authorized,
# and the test bases.
#
# Usage: scripts/inventory.sh [root]
#   root is the directory holding the build file (build.gradle, pom.xml).
#   Auto-detected from the current directory upward when omitted.
# Env:   REVIEW_FILES  space-separated files under review; limits the
#                      missing-test check to them
# Reporting script: a grep with no match is a normal outcome, not an error.
set -uo pipefail

# Output is bounded: INVENTORY_LIMIT lines per section (default 40), overflow
# reported as a count.
limit="${INVENTORY_LIMIT:-40}"

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

# Every Java source, without build output.
sources() {
  find . -name '*.java' -path '*/src/*' -not -path '*/build/*' -not -path '*/target/*' -not -path '*/bin/*' 2>/dev/null | sed 's|^\./||' | sort
}
all_sources=$(sources)
main_sources=$(printf '%s\n' "$all_sources" | grep -E '/src/main/' || true)
test_sources=$(printf '%s\n' "$all_sources" | grep -vE '/src/main/' || true)

build_files() {
  find . -maxdepth 3 \( -name 'build.gradle*' -o -name 'gradle.properties' -o -name 'pom.xml' -o -name 'libs.versions.toml' \) \
    -not -path '*/build/*' -not -path '*/node_modules/*' 2>/dev/null
}

# count_matching PATTERN — how many main sources have a path matching PATTERN
count_in() {
  printf '%s\n' "$1" | grep -cE -- "$2" || true
}

echo
echo "=== versions"
# shellcheck disable=SC2046
grep -hoE "(springBoot[A-Za-z]*|spring-boot[A-Za-z.-]*|sourceCompatibility|java\.version|lombok|jjwt|modelmapper|mapstruct|testcontainers|hibernate[A-Za-z.-]*) *[=:] *['\"]?[A-Za-z_.]*[0-9][0-9A-Za-z_.]*|JavaVersion\.VERSION_[0-9_]+|org\.springframework\.boot['\"]? version ['\"][0-9.]+" \
  $(build_files) 2>/dev/null | sort -u | indent | cap | or_none

echo
echo "=== analyzers in the build (absent = this review's job)"
for analyzer in errorprone nullaway spotbugs checkstyle pmd spotless archunit sonarqube jacoco; do
  # shellcheck disable=SC2046
  if grep -qi -- "$analyzer" $(build_files) 2>/dev/null; then
    printf '  %-12s configured\n' "$analyzer"
  else
    printf '  %-12s absent\n' "$analyzer"
  fi
done
# shellcheck disable=SC2046
lint_flags=$(grep -hoE -- '-Xlint[:a-z,-]*|-Werror|-parameters' $(build_files) 2>/dev/null | sort -u | paste -sd' ' -)
printf '  %-12s %s\n' "javac flags" "${lint_flags:-none}"

echo
echo "=== modules"
printf '%s\n' "$main_sources" | sed -E 's|/?src/main/.*||' | sort -u | while IFS= read -r module; do
  prefix="^${module:+$module/}src/"
  printf '  %-20s controllers:%-3s services:%-3s repositories:%-3s entities:%-3s tests:%s\n' \
    "${module:-.}" \
    "$(count_in "$all_sources" "${prefix}main/.*Controller\.java$")" \
    "$(count_in "$all_sources" "${prefix}main/.*Service(Impl)?\.java$")" \
    "$(count_in "$all_sources" "${prefix}main/.*Repository\.java$")" \
    "$(count_in "$all_sources" "${prefix}main/.*Entity\.java$")" \
    "$(count_in "$all_sources" "${prefix}(test|testFixtures|integrationTest)/.*\.java$")"
done | cap

echo
echo "=== shared primitives — do not rebuild"
shared='/(utils?|commons?|shared|support|helpers?|mapp?ers?|validation|validators?|exceptions?|exeption|errors?|handlers?|constants?|aspects?|converters?)/[^/]+\.java$'
printf '%s\n' "$main_sources" | grep -E -- "$shared" | awk -F/ '
  {
    file = $NF
    sub(/\.java$/, "", file)
    dir = $0
    sub(/\/[^\/]+$/, "", dir)
    sub(/.*\/src\/main\/java\//, "", dir)
    names[dir] = names[dir] (names[dir] == "" ? "" : ", ") file
  }
  END { for (dir in names) printf "  %-44s %s\n", dir, names[dir] }
' | sort | cap | or_none

echo
echo "=== exception handlers and custom annotations"
{
  # shellcheck disable=SC2086
  grep -lE '@(Rest)?ControllerAdvice' $main_sources 2>/dev/null | sed 's/^/  advice      /'
  # shellcheck disable=SC2086
  grep -lE 'public @interface ' $main_sources 2>/dev/null | sed 's/^/  annotation  /'
} | cap | or_none

echo
echo "=== how handlers are authorized"
# shellcheck disable=SC2086
grep -hoE '@(PreAuthorize|PostAuthorize|Secured|RolesAllowed)\("[^"]*"\)' $main_sources 2>/dev/null \
  | sed -E "s/#[A-Za-z_.]+/#…/g; s/'[A-Z_]+'/'…'/g" | sort | uniq -c | sort -rn | indent | cap | or_none
handlers=$(grep -hE '^[[:space:]]*@(Get|Post|Put|Patch|Delete)Mapping' $main_sources 2>/dev/null | wc -l | tr -d ' ')
# shellcheck disable=SC2086
authorized=$(grep -hE '^[[:space:]]*@(PreAuthorize|PostAuthorize|Secured|RolesAllowed)' $main_sources 2>/dev/null | wc -l | tr -d ' ')
echo "  handlers: $handlers   authorization annotations: $authorized"

echo
echo "=== remote clients in use (set REMOTE_CALL for scan.sh from these)"
# shellcheck disable=SC2086
grep -hoE '\b(OkHttpClient|RestTemplate|RestClient|WebClient|FeignClient|MinioClient|S3Client|JavaMailSender|TelegramLongPollingBot|TelegramWebhookBot|AbsSender|KafkaTemplate|RabbitTemplate)\b' \
  $main_sources 2>/dev/null | sort | uniq -c | sort -rn | indent | cap | or_none

echo
echo "=== settings that change the review"
config=$(find . \( -name 'application*.yml' -o -name 'application*.yaml' -o -name 'application*.properties' \) \
  -path '*/src/main/*' -not -path '*/build/*' -not -path '*/bin/*' 2>/dev/null)
if [ -n "$config" ]; then
  # shellcheck disable=SC2086
  grep -HnE 'open-in-view|ddl-auto|max-page-size|default-page-size|problemdetails|allow-circular-references' $config 2>/dev/null \
    | sed -E 's|^\./||; s/:[[:space:]]+/: /' | indent | cap | or_none
else
  echo "  no application.yml / application.properties found"
fi

echo
echo "=== test bases and fixtures"
{
  # shellcheck disable=SC2086
  grep -lE '@SpringBootTest|@WebMvcTest|@DataJpaTest|Testcontainers|PostgreSQLContainer' $test_sources 2>/dev/null \
    | xargs grep -lE '^(public )?(abstract )?class [A-Za-z]*(Base|Template|Abstract|Support)[A-Za-z]*|^public abstract class ' 2>/dev/null
  printf '%s\n' "$test_sources" | grep -E '/testFixtures/' || true
} | sort -u | indent | cap | or_none
# shellcheck disable=SC2086
contexts=$(grep -lE '@SpringBootTest' $test_sources 2>/dev/null | wc -l | tr -d ' ')
# shellcheck disable=SC2086
mock_beans=$(grep -hE '@(MockBean|SpyBean|MockitoBean)' $test_sources 2>/dev/null | wc -l | tr -d ' ')
echo "  classes with @SpringBootTest: $contexts   @MockBean/@SpyBean: $mock_beans"

echo
# units_without_a_test — reads unit paths on stdin; prints the ones no test class is named after
units_without_a_test() {
  local unit name
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    name=$(basename "$unit" .java)
    printf '%s\n' "$test_sources" | grep -qE "/(${name}|${name%Impl})(Test|Tests|IT|IntegrationTest)\.java$" \
      || printf '  %s\n' "$unit"
  done
}
units='(Controller|ServiceImpl)\.java$'
if [ -n "${REVIEW_FILES:-}" ]; then
  echo "=== no test class among REVIEW_FILES (a new unit needs one)"
  # shellcheck disable=SC2086
  candidates=$(printf '%s\n' $REVIEW_FILES | grep -E -- "$units" | sort)
else
  echo "=== no test class (a new unit here needs one)"
  candidates=$(printf '%s\n' "$main_sources" | grep -E -- "$units")
fi
units_without_a_test <<< "$candidates" | cap | or_none
