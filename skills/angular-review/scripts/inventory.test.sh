#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
inventory="$here/inventory.sh"

new_repo project
shared=src/app/shared
mkdir -p "$shared" src/app/core src/app/cart
cat > "$shared/button.component.ts" <<'TS'
/**
 * Primary action button.
 */
@Component({ selector: 'app-button', changeDetection: ChangeDetectionStrategy.OnPush })
export class ButtonComponent {
  @Input() label = '';
  constructor(private theme: ThemeService) {}
}
TS
cat > "$shared/money.pipe.ts" <<'TS'
@Pipe({ name: 'money' })
export class MoneyPipe {}
TS
cat > "$shared/focus.directive.ts" <<'TS'
@Directive({ selector: '[appFocus]' })
export class FocusDirective { private el = inject(ElementRef); }
TS
cat > src/app/core/session.service.ts <<'TS'
@Injectable({ providedIn: 'root' })
export class SessionService {}
TS
echo "export const plain = 1;"                         > "$shared/plain.ts"
echo "@Component({ selector: 'app-spec' }) class S {}" > "$shared/button.component.spec.ts"
echo "@Component({ selector: 'app-cart' }) class C {}" > src/app/cart/cart.component.ts
echo '<p *ngIf="x">a</p>'                              > "$shared/button.component.html"

unit()  { printf '%s\n' "$out" | grep -E "^  $1 " | awk '{print $2, $3}'; }
count() { printf '%s\n' "$out" | grep -F -- "$1" | awk '{print $NF}'; }

out=$(bash "$inventory")
eq   "exits 0"                      "$?" 0
sees "one section per shared layer" '^=== src/app/shared$' "$out"
sees "and the core layer"           '^=== src/app/core$' "$out"
eq   "component with its selector"  "$(unit component)" "app-button ButtonComponent"
eq   "pipe with its name"           "$(unit pipe)" "money MoneyPipe"
eq   "directive"                    "$(unit directive)" "[appFocus] FocusDirective"
eq   "root service has no selector" "$(unit service)" "— SessionService"
misses "skips specs, plain files and feature code" 'app-spec|plain|app-cart' "$out"
misses "doc lines are off by default" 'Primary action button' "$out"

echo "# API generation counts"
eq "decorator inputs"        "$(count '@Input()/@Output() decorators')" 1
eq "constructor injection"   "$(count 'constructor(private …) injection')" 1
eq "inject()"                "$(count 'inject() function')" 1
eq "structural directives"   "$(count '*ngIf/*ngFor structural directives')" 1
eq "OnPush"                  "$(count 'OnPush components')" 1
eq "signals"                 "$(count 'input()/output()/model() signals')" 0

echo 'export class T { readonly n = input(0); readonly done = output(); }' > "$shared/tag.component.ts"
out=$(bash "$inventory")
eq "signals with no type argument" "$(count 'input()/output()/model() signals')" 1
rm "$shared/tag.component.ts"

echo "# options"
has "INVENTORY_DOCS adds the doc line"   0 '↳ Primary action button\.$' env INVENTORY_DOCS=1 bash "$inventory"
has "INVENTORY_LIMIT caps a section"     0 '… \+2 more lines \(raise INVENTORY_LIMIT=1 to see them\)' env INVENTORY_LIMIT=1 bash "$inventory"
has "a directory argument is the only layer" 0 '^=== src/app/cart$' bash "$inventory" src/app/cart
lacks "and the defaults are not scanned" '^=== src/app/shared$' bash "$inventory" src/app/cart

new_repo bare
has "no shared layer" 1 '^no shared layer found — pass one: inventory.sh <dir>$' bash "$inventory"

finish
