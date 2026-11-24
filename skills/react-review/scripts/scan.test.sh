#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

mkdir -p "$tmp/app" && cd "$tmp/app"
cat > Cart.tsx <<'TSX'
import { money } from '../../lib/money';
export const Cart = forwardRef((props: any, ref) => {
  if (props.open) useTracking();
  useEffect(() => { console.log('x'); }, []);
  const first = props.items![0]; // TODO
  return (
    <ScrollView className="p-[13px]" style={{ color: '#ff0000' }}>
      {props.items.map((item, index) => (
        <Pressable key={index} onPress={item.go}>
          {Platform.OS === 'ios' ? <Ios /> : null}
        </Pressable>
      ))}
    </ScrollView>
  );
});
TSX
out=$(bash "$scan" Cart.tsx)
eq "exits 0" "$?" 0

echo "# styling"
flags "Raw hex colors"
flags "Arbitrary utility values"
flags "Mixed styling systems"

echo "# hooks"
flags "forwardRef"
flags "Array index as key"
flags "useEffect"
flags "Hook on the line of an if, for or while"

echo "# typescript and hygiene"
flags "any / as any"
flags "Non-null assertion"
flags "console.\* left in"
flags "Deep relative import"
flags "TODO/FIXME"

echo "# cross-cutting"
flags "\.map\(\) inside a ScrollView"
flags "Interactive element with no accessibilityRole"
flags "Platform.OS branch"

sees "hits carry the line number" '^2:export const Cart = forwardRef' "$out"

echo "# a tidy component"
cat > Tidy.tsx <<'TSX'
export function Tidy({ label }: { label: string }) {
  return <Pressable accessibilityRole="button"><Text>{label}</Text></Pressable>;
}
TSX
has "is clean" 0 '^clean — no mechanical smells$' bash "$scan" Tidy.tsx

echo "# double quotes"
cat > Quoted.tsx <<'TSX'
import { money } from "../../lib/money";
import { near } from "../near";
export function Quoted() {
  const user = useUser();
  if (!user) return null;
  const cart = useCart();
  return Platform.OS === "android" ? <Text>{money(cart.total)}</Text> : null;
}
TSX
out=$(bash "$scan" Quoted.tsx)
deep=$(under 'Deep relative import')
sees   "a double-quoted deep import"         '^1:' "$deep"
misses "one level up is not deep"            '^2:' "$deep"
flags  "Platform.OS branch"
unflags "Hook on the line of an if, for or while"
unflags "useEffect"

echo "# input"
has "no argument"  1 '^usage: scan.sh <component.tsx>$' bash "$scan"
has "missing file" 1 '^not found: Nope.tsx$'            bash "$scan" Nope.tsx

finish
