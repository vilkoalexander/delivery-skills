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
main_sources=$(printf '%s\n' "$all_sources" | grep -E '(^|/)src/main/' || true)
test_sources=$(printf '%s\n' "$all_sources" | grep -vE '(^|/)src/main/' || true)

build_files() {
  find . -maxdepth 3 \( -name 'build.gradle*' -o -name 'gradle.properties' -o -name 'pom.xml' -o -name 'libs.versions.toml' \) \
    -not -path '*/build/*' -not -path '*/node_modules/*' 2>/dev/null
}

main_files=()
test_files=()
build_file_list=()
while IFS= read -r file; do [ -n "$file" ] && main_files+=("$file"); done <<< "$main_sources"
while IFS= read -r file; do [ -n "$file" ] && test_files+=("$file"); done <<< "$test_sources"
while IFS= read -r file; do [ -n "$file" ] && build_file_list+=("$file"); done < <(build_files)

# /dev/null keeps grep off stdin when the list is empty.
in_main()  { grep "$@" ${main_files[@]+"${main_files[@]}"} /dev/null 2>/dev/null; }
in_tests() { grep "$@" ${test_files[@]+"${test_files[@]}"} /dev/null 2>/dev/null; }
in_build() { grep "$@" ${build_file_list[@]+"${build_file_list[@]}"} /dev/null 2>/dev/null; }

# count_in LIST PATTERN — how many paths of LIST match PATTERN
count_in() {
  printf '%s\n' "$1" | grep -cE -- "$2" || true
}

echo
echo "=== versions"
in_build -hoE "(springBoot[A-Za-z]*|spring-boot[A-Za-z.-]*|sourceCompatibility|java\.version|lombok|jjwt|modelmapper|mapstruct|testcontainers|hibernate[A-Za-z.-]*) *[=:] *['\"]?[A-Za-z_.]*[0-9][0-9A-Za-z_.]*|JavaVersion\.VERSION_[0-9_]+|org\.springframework\.boot['\"]? version ['\"][0-9.]+" \
  | sort -u | indent | cap | or_none

echo
echo "=== analyzers in the build (absent = this review's job)"
for analyzer in errorprone nullaway spotbugs checkstyle pmd spotless archunit sonarqube jacoco; do
  if in_build -qi -- "$analyzer"; then
    printf '  %-12s configured\n' "$analyzer"
  else
    printf '  %-12s absent\n' "$analyzer"
  fi
done
lint_flags=$(in_build -hoE -- '-Xlint[:a-z,-]*|-Werror|-parameters' | sort -u | paste -sd' ' -)
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
    sub(/^(.*\/)?src\/main\/java\//, "", dir)
    names[dir] = names[dir] (names[dir] == "" ? "" : ", ") file
  }
  END { for (dir in names) printf "  %-44s %s\n", dir, names[dir] }
' | sort | cap | or_none

echo
echo "=== exception handlers and custom annotations"
{
  in_main -lE '@(Rest)?ControllerAdvice' | sed 's/^/  advice      /'
  in_main -lE 'public @interface ' | sed 's/^/  annotation  /'
} | cap | or_none

echo
echo "=== how handlers are authorized"
in_main -hoE '@(PreAuthorize|PostAuthorize|Secured|RolesAllowed)\("[^"]*"\)' \
  | sed -E "s/#[A-Za-z_.]+/#…/g; s/'[A-Z_]+'/'…'/g" | sort | uniq -c | sort -rn | indent | cap | or_none
handlers=$(in_main -hE '^[[:space:]]*@(Get|Post|Put|Patch|Delete)Mapping' | wc -l | tr -d ' ')
authorized=$(in_main -hE '^[[:space:]]*@(PreAuthorize|PostAuthorize|Secured|RolesAllowed)' | wc -l | tr -d ' ')
echo "  handlers: $handlers   authorization annotations: $authorized"

echo
echo "=== remote clients in use (set REMOTE_CALL for scan.sh from these)"
in_main -hoE '\b(OkHttpClient|RestTemplate|RestClient|WebClient|FeignClient|MinioClient|S3Client|JavaMailSender|TelegramLongPollingBot|TelegramWebhookBot|AbsSender|KafkaTemplate|RabbitTemplate)\b' \
  | sort | uniq -c | sort -rn | indent | cap | or_none

echo
echo "=== settings that change the review"
config=()
while IFS= read -r file; do [ -n "$file" ] && config+=("$file"); done < <(
  find . \( -name 'application*.yml' -o -name 'application*.yaml' -o -name 'application*.properties' \) \
    -path '*/src/main/*' -not -path '*/build/*' -not -path '*/bin/*' 2>/dev/null)
if [ ${#config[@]} -gt 0 ]; then
  grep -HnE 'open-in-view|ddl-auto|max-page-size|default-page-size|problemdetails|allow-circular-references' "${config[@]}" /dev/null 2>/dev/null \
    | sed -E 's|^\./||; s/:[[:space:]]+/: /' | indent | cap | or_none
else
  echo "  no application.yml / application.properties found"
fi

echo
echo "=== test bases and fixtures"
{
  in_tests -lE '@SpringBootTest|@WebMvcTest|@DataJpaTest|Testcontainers|PostgreSQLContainer' \
    | tr '\n' '\0' | xargs -0 grep -lE '^(public )?(abstract )?class [A-Za-z]*(Base|Template|Abstract|Support)[A-Za-z]*|^public abstract class ' /dev/null 2>/dev/null
  printf '%s\n' "$test_sources" | grep -E '/testFixtures/' || true
} | sort -u | indent | cap | or_none
contexts=$(in_tests -lE '@SpringBootTest' | wc -l | tr -d ' ')
mock_beans=$(in_tests -hE '@(MockBean|SpyBean|MockitoBean)' | wc -l | tr -d ' ')
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
