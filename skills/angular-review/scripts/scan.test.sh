#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

mkdir -p "$tmp/app" && cd "$tmp/app"
cat > cart.component.ts <<'TS'
import { Thing } from '../../shared/thing';
@Component({
  selector: 'app-cart',
  templateUrl: './cart.component.html',
  styleUrls: ['./cart.component.scss'],
  standalone: false,
  encapsulation: ViewEncapsulation.None,
})
export class CartComponent {
  @Input() items: any;
  total = input<number>();
  constructor(private http: HttpClient) {
    effect(() => {
      this.count.set(this.items.length);
    });
  }
  async ngOnInit() {
    this.http.get('/a').subscribe(a => {
      this.http.get('/b').subscribe(b => {
        console.log(a, b);
      });
    });
    setTimeout(() => this.cdr.detectChanges());
  }
  ngOnChanges() { this.first = this.items![0]; } // TODO
}
TS
cat > cart.component.html <<'HTML'
<div *ngIf="open" (click)="toggle()" [ngClass]="cls">
  @if (items) { <img src="a.png"> }
  @for (item of items; track $index) { <input [(ngModel)]="item.qty"> }
</div>
HTML
cat > cart.component.scss <<'CSS'
:host ::ng-deep .row { color: #ff0000 !important; }
CSS

out=$(bash "$scan" cart.component.ts)
eq   "exits 0" "$?" 0
sees "names the companion files" '^scanning: cart.component.ts \+ cart.component.html \+ cart.component.scss$' "$out"

echo "# class"
flags "Decorator inputs/outputs"
flags "Constructor parameter injection"
flags "standalone: false or NgModule declarations"
flags "Mixed input generations in one class"
flags "effect\(\)"
flags "Signal written inside an effect"
eq    "the write is located" "$(under 'Signal written inside an effect' | cut -d: -f1)" 14
flags "ngOnChanges"
flags "No OnPush"
flags "detectChanges\(\)/setTimeout"
flags "Manual subscribe with no teardown"
flags "Nested subscribe"
eq    "the inner subscribe is located" "$(under 'Nested subscribe' | cut -d: -f1)" 19
flags "async ngOnInit"
flags "ViewEncapsulation.None"
flags "any / as any"
flags "Non-null assertion"
flags "console.\* left in"
flags "Deep relative import"
flags "TODO/FIXME"

echo "# template"
flags "Structural directives"
sees  "template hits name the file" '^(\./)?cart.component.html:1:' "$(under 'Structural directives')"
flags "ngClass/ngStyle"
flags "Mixed control flow in one template"
flags "track \\\$index"
flags "\(click\) on a div/span"
flags "<img> without alt"
flags "Form control with no label hook"
flags "ngModel"

echo "# styles"
flags "::ng-deep"
flags "!important"
flags "Raw hex colors"

echo "# a tidy component"
cat > tidy.component.ts <<'TS'
@Component({
  selector: 'app-tidy',
  template: '<button (click)="go()">Go</button>',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class TidyComponent {
  private readonly http = inject(HttpClient);
  readonly label = input<string>();
}
TS
has "is clean" 0 '^clean — no mechanical smells$' bash "$scan" tidy.component.ts

echo "# teardown anywhere in the file is enough"
cat > sub.component.ts <<'TS'
@Component({ changeDetection: ChangeDetectionStrategy.OnPush })
export class SubComponent {
  load() { this.http.get('/a').pipe(takeUntilDestroyed()).subscribe(); }
}
TS
out=$(bash "$scan" sub.component.ts)
unflags "Manual subscribe with no teardown"

echo "# input"
has "no argument"  1 '^usage: scan.sh <component.ts>$' bash "$scan"
has "missing file" 1 '^not found: nope.ts$'            bash "$scan" nope.ts

finish
