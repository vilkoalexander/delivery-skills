#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
audit="$here/audit.sh"

# A stand-in plugin, so the plugin's own wording can change without failing this.
export PLUGIN_ROOT="$tmp/plugin"
skill() { mkdir -p "$PLUGIN_ROOT/skills/$1/references"; cat > "$PLUGIN_ROOT/skills/$1/${2:-SKILL.md}"; }
skill chunked-delivery <<'MD'
Global Constraints: build only when the inventory shows none, fewer than two callers stay local.
MD
skill chunked-delivery references/plan.md <<'MD'
No new runtime dependency. ## Inventory goes in the dispatch. ## Reuse goes in the report.
The gate runs reuse-scan. The final review reads the jscpd report.
MD
skill review-routing <<'MD'
Run reuse-scan first.
MD

# status ID prints the PASS / MISS / MANUAL word of one row
status() { printf '%s\n' "$out" | awk -v id="$1" '$1 == id {print $2}'; }

echo "# a project with nothing set up"
new_repo bare
out=$(bash "$audit")
eq   "exits 0"                               "$?" 0
sees "says whose skills are in force"        '^  delivery-pipeline: plugin · chunked-delivery: plugin · review-routing: plugin$' "$out"
eq   "A1 inherits the plugin's constraints"  "$(status A1)" PASS
eq   "A2 inherits the inventory block"       "$(status A2)" PASS
eq   "A3 inherits the reuse block"           "$(status A3)" PASS
eq   "A4 no project layer"                   "$(status A4)" MISS
eq   "B1 no jscpd"                           "$(status B1)" MISS
eq   "B2 no eslint config"                   "$(status B2)" MISS
eq   "B3 no eslint config"                   "$(status B3)" MISS
eq   "B4 inherits reuse-scan in the gate"    "$(status B4)" PASS
eq   "B5 no lint hook"                       "$(status B5)" MISS
eq   "C1 plugin rubrics carry the rule"      "$(status C1)" PASS
eq   "C2 inherits reuse-scan in routing"     "$(status C2)" PASS
eq   "C3 jscpd named but not installed"      "$(status C3)" MISS
eq   "C4 is always for a human"              "$(status C4)" MANUAL
sees "lists what is missing"                 '^MISS: A4 B1 B2 B3 B5 C3$' "$out"
sees "lists what needs a human"              '^MANUAL: C4$' "$out"

echo "# a project with everything set up"
new_repo ready
mkdir -p docs/review .claude .github/workflows
echo "Shared primitives: Button. Caught by hand: none yet." > docs/review/react-review.md
echo '{ "devDependencies": { "jscpd": "4.0.0" }, "scripts": { "dupes": "jscpd src" } }' > package.json
echo '{}' > .jscpd.json
echo "export default [{ rules: { 'no-restricted-imports': 'error', 'max-lines': ['error', 300] } }]" > eslint.config.mjs
echo '{ "hooks": { "PostToolUse": [{ "hooks": [{ "command": "npx eslint --fix" }] }] } }' > .claude/settings.json
out=$(bash "$audit")
sees "nothing is missing"                    '^MISS: nothing$' "$out"
sees "A4 counts the layer files"             '^  A4  PASS    1 project layer files$' "$out"
sees "B1 says where jscpd runs"              '^  B1  PASS    jscpd \(.jscpd.json\) in a script or CI$' "$out"
sees "B2 names the config"                   '^  B2  PASS    hand-roll bans in eslint.config.mjs$' "$out"
sees "C4 points at the section"              '^  C4  MANUAL  Caught by hand section exists' "$out"

echo "# markup in a filled layer is not a placeholder"
printf '%s\n' 'Use `<ui-skeleton>` and a `<button>` in a `<table>`.<br>' '<details><summary>More</summary></details>' > docs/review/react-review.md
has "A4 custom elements and HTML tags pass"  0 '^  A4  PASS    1 project layer files$' bash "$audit"

echo "# partial setups"
echo "Use <the shared button> from <path> here." > docs/review/react-review.md
has "A4 a layer still holding placeholders"  0 '^  A4  MISS    template placeholders still in: docs/review/react-review.md' bash "$audit"
echo '{ "devDependencies": { "jscpd": "4.0.0" } }' > package.json
has "B1 configured but never run"            0 '^  B1  MISS    jscpd configured \(.jscpd.json\) but no script or CI step runs it$' bash "$audit"
rm .jscpd.json
has "B1 installed but not configured"        0 '^  B1  MISS    jscpd installed, no .jscpd.json$' bash "$audit"
echo '{ "devDependencies": { "jscpd": "4.0.0" }, "jscpd": { "threshold": 1 } }' > package.json
has "B1 configured in package.json"          0 '^  B1  MISS    jscpd configured \(package.json#jscpd\) but no script' bash "$audit"
echo "export default []" > eslint.config.mjs
has "B2 a config with no bans"               0 '^  B2  MISS    no no-restricted-\* rule in: eslint.config.mjs$' bash "$audit"
has "B3 a config with no size limit"         0 '^  B3  MISS    no max-lines in any eslint config$' bash "$audit"
mkdir -p apps/web
echo "export default [{ rules: { 'no-restricted-syntax': 'error' } }]" > apps/web/eslint.config.mjs
has "B2 bans in every app config"            0 '^  B2  PASS    hand-roll bans in every app config$' bash "$audit"

echo "# a project copy of a skill replaces the plugin's"
mkdir -p .claude/skills/review-routing .claude/skills/react-review
echo "Route by file type." > .claude/skills/review-routing/SKILL.md
echo "Check hooks."        > .claude/skills/react-review/SKILL.md
out=$(bash "$audit")
sees "the header names the owner"            'review-routing: project$' "$out"
sees "C2 reads the project copy"             '^  C2  MISS    review-routing never runs reuse-scan \(project ' "$out"
sees "C1 a project rubric with no rule"      '^  C1  MISS    no reinvention rule in: react-review$' "$out"
echo "Do not reinvent a shared helper." >> .claude/skills/react-review/SKILL.md
has  "C1 a project rubric with the rule"     0 '^  C1  PASS    reinvention rule in 1 project rubrics$' bash "$audit"

echo "# a root argument"
has "audits the directory it is given" 0 "^Reuse guardrails — $tmp/bare$" bash "$audit" "$tmp/bare"

finish
