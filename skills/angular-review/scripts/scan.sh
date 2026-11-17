#!/usr/bin/env bash
# Mechanical pre-scan for angular-review. Follows templateUrl / styleUrl(s) so
# the template and stylesheet are scanned with the class. Heuristic — flags,
# not a verdict; the project's API generation decides which flags matter.
#
# Usage: scan.sh <path/to/thing.component.ts>
set -uo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "usage: scan.sh <component.ts>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "not found: $file" >&2
  exit 1
fi
dir=$(dirname "$file")

# Resolve companion files declared in the decorator.
quoted="['\"][^'\"]+['\"]"
template=""
styles=""

template_url=$(grep -oE "templateUrl:[[:space:]]*$quoted" "$file" | sed -E "s/.*['\"]([^'\"]+)['\"]/\1/")
if [ -n "$template_url" ] && [ -f "$dir/$template_url" ]; then
  template="$dir/$template_url"
fi

style_urls=$(grep -oE "styleUrls?:[[:space:]]*\[?[^]]*" "$file" | grep -oE "$quoted" | tr -d "'\"")
for style_url in $style_urls; do
  [ -f "$dir/$style_url" ] && styles="$styles $dir/$style_url"
done

found_any=0

# flag LABEL LINES — prints a finding with the lines that caused it
flag() {
  printf '## %s\n%s\n\n' "$1" "$2"
  found_any=1
}

# report LABEL REGEX file... — flags every line of the files that matches
report() {
  local label=$1 regex=$2 matches
  shift 2
  matches=$(grep -nE "$regex" "$@" /dev/null 2>/dev/null | sed "s|^$dir/||")
  [ -n "$matches" ] && flag "$label" "$matches"
}

has() {
  grep -qE "$1" "$2"
}

scanned="$(basename "$file")"
[ -n "$template" ] && scanned="$scanned + $(basename "$template")"
if [ -n "$styles" ]; then
  scanned="$scanned +"
  for style in $styles; do
    scanned="$scanned $(basename "$style")"
  done
fi
echo "scanning: $scanned"
echo

decorator_io='@(Input|Output)\('
signal_io='\b(input|output|model)(\.required)?<'
old_control_flow='\*ng(If|For)'
new_control_flow='@(if|for)[[:space:]]*\('

# --- API generation markers (decide against the project's generation) --------
report "Decorator inputs/outputs — project on signals? then input()/output()/model()" \
  "$decorator_io" "$file"
report "Constructor parameter injection — project on inject()? then migrate" \
  'constructor\([^)]*(private|public|protected|readonly)[[:space:]]' "$file"
report "Structural directives — project on built-in control flow? then @if/@for/@switch" \
  '\*ng(If|For|Switch)' "$file" $template
report "ngClass/ngStyle — prefer direct [class.x] / [style.x] bindings" \
  '\[ng(Class|Style)\]' "$file" $template
report "standalone: false or NgModule declarations — on 19+ standalone is the default" \
  'standalone:[[:space:]]*false|declarations:[[:space:]]*\[' "$file"

# Mixed generations inside ONE file are a finding on any project.
if has "$decorator_io" "$file" && has "$signal_io" "$file"; then
  flag "Mixed input generations in one class — decorators and signal inputs together" "  pick one"
fi
if [ -n "$template" ] && has "$old_control_flow" "$template" && has "$new_control_flow" "$template"; then
  flag "Mixed control flow in one template — *ngIf/*ngFor and @if/@for together" "  pick one"
fi

# --- signals & effects --------------------------------------------------------
report "effect() — verify against CHECKLIST §2: syncing to a non-signal API only, never writing app state" \
  '\beffect\(' "$file"

# Follows the braces from each effect( to its end and prints the .set( / .update( lines inside.
signal_writes_in_effects() {
  awk '
    function braces(line) { return gsub(/\{/, "{", line) - gsub(/\}/, "}", line) }
    function report_write() {
      if ($0 ~ /\.(set|update)\(/) printf "%d: %s  <- signal write inside effect\n", NR, $0
    }
    in_effect {
      report_write()
      depth += braces($0)
      if (depth <= 0) in_effect = 0
      next
    }
    /(^|[^A-Za-z_])effect\(/ {
      in_effect = 1
      depth = braces($0)
      report_write()
      if (depth <= 0) in_effect = 0
    }
  ' "$file"
}
writes=$(signal_writes_in_effects)
[ -n "$writes" ] && flag "Signal written inside an effect — derived state is computed(), not an effect" "$writes"

report "ngOnChanges — usually an input copied into a field; with signal inputs this is a computed()" \
  'ngOnChanges' "$file"

# --- change detection --------------------------------------------------------
if grep -q '@Component(' "$file" && ! grep -q 'ChangeDetectionStrategy.OnPush' "$file"; then
  flag "No OnPush — Default change detection on a component (hard if siblings are OnPush)" \
    "  add changeDetection: ChangeDetectionStrategy.OnPush"
fi
report "detectChanges()/setTimeout — forcing a render is a symptom of state mutated outside Angular" \
  'detectChanges\(\)|setTimeout\(' "$file"

# --- rxjs --------------------------------------------------------------------
subscribes=$(grep -nE '\.subscribe\(' "$file" || true)
if [ -n "$subscribes" ] && ! has 'takeUntilDestroyed|DestroyRef|take\(1\)|first\(\)' "$file"; then
  flag "Manual subscribe with no teardown anywhere in the file — takeUntilDestroyed, take(1), or the async pipe" "$subscribes"
fi

# Prints each .subscribe( that opens while an earlier one is still open.
nested_subscribes() {
  awk '
    /\.subscribe\(/ {
      if (open) printf "%d: %s  <- subscribe inside subscribe\n", NR, $0
      open = 1
      depth = 0
    }
    open {
      depth += gsub(/\{/, "{") - gsub(/\}/, "}")
      if (depth <= 0 && $0 ~ /\}\)/) open = 0
    }
  ' "$file"
}
nested=$(nested_subscribes)
[ -n "$nested" ] && flag "Nested subscribe — switchMap / concatMap / exhaustMap, chosen deliberately" "$nested"

report "async ngOnInit — a rejected promise there is an unhandled rejection with no template feedback" \
  'async ngOnInit' "$file"

# --- template ----------------------------------------------------------------
if [ -n "$template" ]; then
  report "track \$index — breaks on reorder/insert/delete; track a stable id" \
    'track \$index' "$template"
  report "(click) on a div/span — needs a <button>, or role + tabindex + keyboard handler" \
    '<(div|span)[^>]*\(click\)' "$template"

  images_without_alt=$(grep -nE '<img\b' "$template" | grep -vE '\balt=' || true)
  [ -n "$images_without_alt" ] && flag "<img> without alt" "$images_without_alt"

  unlabelled_controls=$(grep -nE '<(input|select|textarea)\b' "$template" \
    | grep -vE 'aria-label|\bid=|type="(hidden|submit)"' || true)
  [ -n "$unlabelled_controls" ] && flag "Form control with no label hook — needs <label for>, aria-label or aria-labelledby" "$unlabelled_controls"

  report "ngModel — template-driven form; prefer typed reactive forms beyond a single field" \
    '\[\(ngModel\)\]' "$template"
fi

# --- styles ------------------------------------------------------------------
if [ -n "$styles" ]; then
  report "::ng-deep — deprecated, leaks past encapsulation" '::ng-deep' $styles
  report "!important — a specificity fight" '!important' $styles
  report "Raw hex colors — use the project's tokens / custom properties" '#[0-9a-fA-F]{3,8}\b' $styles
fi
report "ViewEncapsulation.None — legitimate on a layout shell / theme root, a finding on a leaf" \
  'ViewEncapsulation\.None' "$file"

# --- typescript / hygiene ----------------------------------------------------
report "any / as any — type it or use unknown + guard" ':[[:space:]]*any\b|as any\b' "$file"
report "Non-null assertion — handle the null instead" '[]A-Za-z0-9_)]!(\.|\[)' "$file"
report "console.* left in" 'console\.(log|warn|debug|info)' "$file"
report "Deep relative import — use the project's path alias" "from '\.\./\.\./" "$file"
report "TODO/FIXME — confirm intentional" '(TODO|FIXME|XXX)' "$file" $template

[ "$found_any" -eq 0 ] && echo "clean — no mechanical smells"
exit 0
