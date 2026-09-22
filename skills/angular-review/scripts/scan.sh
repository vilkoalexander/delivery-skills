#!/usr/bin/env bash
# Mechanical pre-scan for angular-review. Follows templateUrl / styleUrl(s) so
# the template and stylesheet are scanned with the class. Heuristic — flags,
# not a verdict; the project's API generation decides which flags matter.
#
# Usage: scan.sh <path/to/thing.component.ts>
set -uo pipefail

file="${1:-}"
[ -z "$file" ] && { echo "usage: scan.sh <component.ts>" >&2; exit 1; }
[ -f "$file" ] || { echo "not found: $file" >&2; exit 1; }
dir=$(dirname "$file")

# Resolve companion files declared in the decorator.
tpl=""; styles=""
t=$(grep -oE "templateUrl:[[:space:]]*['\"][^'\"]+['\"]" "$file" | sed -E "s/.*['\"]([^'\"]+)['\"]/\1/")
[ -n "$t" ] && [ -f "$dir/$t" ] && tpl="$dir/$t"
for s in $(grep -oE "styleUrls?:[[:space:]]*\[?[^]]*" "$file" | grep -oE "['\"][^'\"]+['\"]" | tr -d "'\""); do
  [ -f "$dir/$s" ] && styles="$styles $dir/$s"
done

hits=0
report() {
  # $1 = label, $2 = extended-regex, $3.. = files
  local label="$1" re="$2"; shift 2
  local out
  out=$(grep -nE "$re" "$@" /dev/null 2>/dev/null | sed "s|^$dir/||")
  if [ -n "$out" ]; then printf '## %s\n%s\n\n' "$label" "$out"; hits=1; fi
}
emit() { printf '## %s\n%s\n\n' "$1" "$2"; hits=1; }

echo "scanning: $(basename "$file")${tpl:+ + $(basename "$tpl")}${styles:+ +$(for s in $styles; do printf ' %s' "$(basename "$s")"; done)}"
echo

# --- API generation markers (decide against the project's generation) --------
report "Decorator inputs/outputs — project on signals? then input()/output()/model()" \
  '@(Input|Output)\(' "$file"
report "Constructor parameter injection — project on inject()? then migrate" \
  'constructor\([^)]*(private|public|protected|readonly)[[:space:]]' "$file"
report "Structural directives — project on built-in control flow? then @if/@for/@switch" \
  '\*ng(If|For|Switch)' "$file" $tpl
report "ngClass/ngStyle — prefer direct [class.x] / [style.x] bindings" \
  '\[ng(Class|Style)\]' "$file" $tpl
report "standalone: false or NgModule declarations — on 19+ standalone is the default" \
  'standalone:[[:space:]]*false|declarations:[[:space:]]*\[' "$file"

# Mixed generations inside ONE file are a finding on any project.
if grep -qE '@(Input|Output)\(' "$file" && grep -qE '\b(input|output|model)(\.required)?<' "$file"; then
  emit "Mixed input generations in one class — decorators and signal inputs together" "  pick one"
fi
if [ -n "$tpl" ] && grep -qE '\*ng(If|For)' "$tpl" && grep -qE '@(if|for)[[:space:]]*\(' "$tpl"; then
  emit "Mixed control flow in one template — *ngIf/*ngFor and @if/@for together" "  pick one"
fi

# --- signals & effects --------------------------------------------------------
report "effect() — verify against CHECKLIST §2: syncing to a non-signal API only, never writing app state" \
  '\beffect\(' "$file"
set_in_effect=$(awk '
  ineff { if ($0 ~ /\.(set|update)\(/) printf "%d: %s  <- signal write inside effect\n", NR, $0
          d += gsub(/\{/,"{") - gsub(/\}/,"}"); if (d <= 0) ineff = 0; next }
  /(^|[^A-Za-z_])effect\(/ { ineff = 1; d = gsub(/\{/,"{") - gsub(/\}/,"}")
                 if ($0 ~ /\.(set|update)\(/) printf "%d: %s  <- signal write inside effect\n", NR, $0
                 if (d <= 0) ineff = 0 }
' "$file")
[ -n "$set_in_effect" ] && emit "Signal written inside an effect — derived state is computed(), not an effect" "$set_in_effect"
report "ngOnChanges — usually an input copied into a field; with signal inputs this is a computed()" \
  'ngOnChanges' "$file"

# --- change detection --------------------------------------------------------
if grep -q '@Component(' "$file" && ! grep -q 'ChangeDetectionStrategy.OnPush' "$file"; then
  emit "No OnPush — Default change detection on a component (hard if siblings are OnPush)" "  add changeDetection: ChangeDetectionStrategy.OnPush"
fi
report "detectChanges()/setTimeout — forcing a render is a symptom of state mutated outside Angular" \
  'detectChanges\(\)|setTimeout\(' "$file"

# --- rxjs --------------------------------------------------------------------
subs=$(grep -nE '\.subscribe\(' "$file" || true)
if [ -n "$subs" ] && ! grep -qE 'takeUntilDestroyed|DestroyRef|take\(1\)|first\(\)' "$file"; then
  emit "Manual subscribe with no teardown anywhere in the file — takeUntilDestroyed, take(1), or the async pipe" "$subs"
fi
nested=$(awk '/\.subscribe\(/ { if (open) printf "%d: %s  <- subscribe inside subscribe\n", NR, $0; open = 1; d = 0 }
  open { d += gsub(/\{/,"{") - gsub(/\}/,"}"); if (d <= 0 && $0 ~ /\}\)/) open = 0 }' "$file")
[ -n "$nested" ] && emit "Nested subscribe — switchMap / concatMap / exhaustMap, chosen deliberately" "$nested"
report "async ngOnInit — a rejected promise there is an unhandled rejection with no template feedback" \
  'async ngOnInit' "$file"

# --- template ----------------------------------------------------------------
[ -n "$tpl" ] && report "track \$index — breaks on reorder/insert/delete; track a stable id" \
  'track \$index' "$tpl"
[ -n "$tpl" ] && report "(click) on a div/span — needs a <button>, or role + tabindex + keyboard handler" \
  '<(div|span)[^>]*\(click\)' "$tpl"
if [ -n "$tpl" ]; then
  noalt=$(grep -nE '<img\b' "$tpl" | grep -vE '\balt=' || true)
  [ -n "$noalt" ] && emit "<img> without alt" "$noalt"
  nolabel=$(grep -nE '<(input|select|textarea)\b' "$tpl" | grep -vE 'aria-label|\bid=|type="(hidden|submit)"' || true)
  [ -n "$nolabel" ] && emit "Form control with no label hook — needs <label for>, aria-label or aria-labelledby" "$nolabel"
fi
[ -n "$tpl" ] && report "ngModel — template-driven form; prefer typed reactive forms beyond a single field" \
  '\[\(ngModel\)\]' "$tpl"

# --- styles ------------------------------------------------------------------
[ -n "$styles" ] && report "::ng-deep — deprecated, leaks past encapsulation" '::ng-deep' $styles
[ -n "$styles" ] && report "!important — a specificity fight" '!important' $styles
[ -n "$styles" ] && report "Raw hex colors — use the project's tokens / custom properties" '#[0-9a-fA-F]{3,8}\b' $styles
report "ViewEncapsulation.None — legitimate on a layout shell / theme root, a finding on a leaf" \
  'ViewEncapsulation\.None' "$file"

# --- typescript / hygiene ----------------------------------------------------
report "any / as any — type it or use unknown + guard" ':[[:space:]]*any\b|as any\b' "$file"
report "Non-null assertion — handle the null instead" '[A-Za-z0-9_\)\]]![.\[]' "$file"
report "console.* left in" 'console\.(log|warn|debug|info)' "$file"
report "Deep relative import — use the project's path alias" "from '\.\./\.\./" "$file"
report "TODO/FIXME — confirm intentional" '(TODO|FIXME|XXX)' "$file" $tpl

[ "$hits" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
