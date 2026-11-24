#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/erosion-scan.sh"
count="$here/complexity.mjs"

# branches N — N lines of `if`, the body of a function with complexity N + 1
branches() {
  local n
  for n in $(seq 1 "$1"); do echo "  if (a === $n) return $n;"; done
}

# counted NAME WANT LANG — the source on stdin gives exactly the lines WANT
counted() {
  local name=$1 want=$2 lang=$3 got
  got=$(node "$count" "$lang" | tr '\t' ' ')
  eq "$name" "$got" "$want"
}

echo "# what counts as a branch"
counted "if, loop, case, catch, logic, ternary" "f 1 10" js <<'EOF'
function f(a, b) {
  if (a && b || a) return 1;
  for (const x of a) while (x) x.next();
  switch (b) { case 1: return 2; default: return 3; }
  try { go(); } catch (e) { return a ?? b ? 1 : 2; }
}
EOF
counted "optional markers are not a ternary" "f 1 1" js <<'EOF'
function f(a?: string, b?: Map<string, number>) { return a?.length; }
EOF
counted "a comment, a string and a regex are not code" "f 1 1" js <<'EOF'
function f(a) {
  // if (a) { for (;;) {}
  const s = "if (a) {" + 'while (' + `x ${a ? '{' : '}'} if`;
  return /if\/[}{]/.test(s);
}
EOF
counted "a regex with a quote inside a template" "quote 1 1
after 2 2" js <<'EOF'
const quote = text => { return `'${text.replace(/'/g, `'\\''`)}'`; };
function after(a) { if (a) b(); }
EOF
counted "an apostrophe in JSX text is not a string" "Row 1 2" js <<'EOF'
const Row = ({ a }: Props) => {
  return <li>{a && <b>Don't</b>}</li>;
};
EOF

echo "# what is a function"
counted "declaration, arrow, method, property" "plain 1 2
arrow 2 2
Svc.handler 4 2
Svc.find 5 2
Svc.label 6 2
key 8 2
short 8 2" js <<'EOF'
function plain(a) { if (a) b(); }
export const arrow = async (a: A): Promise<void> => { if (a) b(); };
class Svc<T> {
  private readonly handler = (a) => { if (a) b(); };
  async find<K>(id: string): Promise<Row | null> { if (id) b(); return null; }
  get label(): string { return this.a || 'x'; }
}
const o = { key: (a) => { if (a) b(); }, short(a) { if (a) b(); } };
EOF
counted "a callback counts toward the function around it" "Card 1 3" js <<'EOF'
const Card = ({ items }) => {
  useEffect(() => { if (items) load(); }, [items]);
  return items.map(i => { if (i) return i; return null; });
};
EOF
counted "the same name twice" "A.run 1 1
B.run 2 2
B.run#2 2 1" js <<'EOF'
class A { run() {} }
class B { run(a) { if (a) b(); } run() {} }
EOF
counted "Java: a method, throws, a lambda, an anonymous class" "Orders.find 3 4
Orders.toString 6 2
Orders.P.twice 9 2" java <<'EOF'
@Service
public class Orders extends Base<Order> {
  public Order find(String id, List<? extends A> xs) throws IOException {
    if (id == null || id.isEmpty()) { throw new X("{"); }
    Runnable r = () -> { if (xs.size() > 2) go('}'); };
    Object o = new Object() { public String toString() { return id != null ? "a" : "b"; } };
    return null;
  }
  record P(int x) { int twice() { return x > 0 ? x * 2 : 0; } }
}
EOF
counted "Kotlin: fun, elvis, a trailing lambda" "Repo.find 2 4" kt <<'EOF'
class Repo(val db: Db) : Base(db) {
  fun find(id: String?): Row? {
    val x = id ?: return null
    if (x.isEmpty()) return null
    run(x) { y -> if (y) z() }
    return db.get(x)
  }
}
EOF
has "brackets that do not balance: nothing, exit 3" 3 "" bash -c "echo 'function f() { if (a) {' | node '$count' js"
has "an unknown language"                          2 "usage" bash -c "echo | node '$count' py"

new_repo project
mkdir -p src
{ echo "export function small(a) {"; branches 2; echo "}"; echo "export function big(a) {"; branches 11; echo "}"; } > src/a.ts
{ echo "class Orders {"; echo "  int near(int a) {"; branches 8; echo "    return 0;"; echo "  }"; echo "}"; } > src/Orders.java
commit_all
clean='^EROSION: 0 flags \(limit 10\)$'

# grow FILE AFTER_LINE N — adds N branches below the line that matches
grow() {
  local file=$1 after=$2 n=$3 added
  added=$(branches "$n")
  ADDED=$added AFTER=$after awk '{ print } index($0, ENVIRON["AFTER"]) { print ENVIRON["ADDED"] }' "$file" > "$file.new"
  mv "$file.new" "$file"
}

echo "# a function that was complex and grew"
has "an unchanged tree is clean"       0 "$clean" bash "$scan"
grow src/a.ts "function big" 2
has "over the limit and grew"          0 "^src/a.ts:5 — complex function grew — big: 12 → 14$" bash "$scan"
has "counts the flags"                 0 "^EROSION: 1 flags \(limit 10\)$" bash "$scan"
has "a flag says what to do"           0 "give the new branch a function of its own" bash "$scan"
git checkout -q src/a.ts

grow src/Orders.java "int near" 1
has "crossed the limit"                0 "^src/Orders.java:2 — complex function grew — Orders.near: 9 → 10$" bash "$scan"
git checkout -q src/Orders.java

echo "# what is not a flag"
grow src/a.ts "function small" 3
has "grew and stayed under the limit"  0 "$clean" bash "$scan"
git checkout -q src/a.ts
sed -i.bak '6,8d' src/a.ts && rm src/a.ts.bak
has "a complex function that shrank"   0 "$clean" bash "$scan"
git checkout -q src/a.ts
{ echo "export function fresh(a) {"; branches 15; echo "}"; } > src/fresh.ts
has "a new file"                       0 "$clean" bash "$scan" src/fresh.ts
rm src/fresh.ts
{ echo "export function added(a) {"; branches 15; echo "}"; } >> src/a.ts
has "a new function in an old file"    0 "$clean" bash "$scan"
git checkout -q src/a.ts
mkdir -p src/__tests__ && cp src/a.ts src/a.spec.ts && commit_all tests
grow src/a.spec.ts "function big" 2
has "a test file"                      0 "$clean" bash "$scan"
git checkout -q src/a.spec.ts
echo "notes" > notes.md && commit_all notes && echo "more" >> notes.md
has "a file that is not source"        0 "$clean" bash "$scan"
git checkout -q notes.md

echo "# the limit and the allow list"
grow src/a.ts "function small" 3
has "EROSION_THRESHOLD lowers the limit" 0 "small: 3 → 6" env EROSION_THRESHOLD=5 bash "$scan"
has "and is in the count line"         0 "^EROSION: 1 flags \(limit 5\)$" env EROSION_THRESHOLD=5 bash "$scan"
has "a threshold that is not a number" 2 "threshold must be a number" env EROSION_THRESHOLD=high bash "$scan"
git checkout -q src/a.ts
grow src/a.ts "function big" 1
has "EROSION_ALLOW by function"        0 "$clean" env EROSION_ALLOW='^src/a\.ts:big$' bash "$scan"
has "and only for what it names"       0 "big: 12 → 13" env EROSION_ALLOW='^src/a\.ts:small$' bash "$scan"

echo "# which paths, and the exit code"
has "a path as an argument"            0 "src/a.ts:5"  bash "$scan" src/a.ts
has "another path is clean"            0 "$clean"      bash "$scan" src/Orders.java
has "paths on stdin"                   0 "src/a.ts:5"  bash -c "echo src/a.ts | bash '$scan'"
has "EROSION_STRICT fails on a flag"   1 "^EROSION: 1 flags" env EROSION_STRICT=1 bash "$scan"
commit_all grew
has "committed, so the tree is clean"  0 "$clean"      bash "$scan"
has "EROSION_STRICT passes a clean tree" 0 "$clean"    env EROSION_STRICT=1 bash "$scan"
has "EROSION_DIFF_RANGE scans a range" 0 "big: 12 → 13" env EROSION_DIFF_RANGE=HEAD~1..HEAD bash "$scan"
has "a three-dot range"                0 "big: 12 → 13" env EROSION_DIFF_RANGE=HEAD~1...HEAD bash "$scan"

echo "# a file the scan cannot read"
echo "export function open(a) { if (a) {" >> src/a.ts
has "is named, and is not a flag"      0 "^not read, the brackets do not balance for the scan: src/a.ts$" bash "$scan"
has "and the count stays honest"       0 "$clean" bash "$scan"
git checkout -q src/a.ts

mkdir -p "$tmp/plain" && cd "$tmp/plain"
has "outside git" 2 "erosion-scan: not a git repository" env GIT_CEILING_DIRECTORIES="$tmp" bash "$scan"

finish
