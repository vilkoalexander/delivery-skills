#!/usr/bin/env python3
"""Render inventory.json [+ audit.json] into index.html and open it.

Usage: render.py --dir OUTDIR [--template FILE] [--no-audit] [--no-open]
  OUTDIR holds inventory.json and an optional audit.json. index.html and
  score.json are written next to them; the score.json of the run before
  becomes score.prev.json.
  --no-audit  score from the inventory alone, also when audit.json exists
"""
import argparse
import json
import os
import re
import subprocess
import sys

from collect import flag_counts

HERE = os.path.dirname(os.path.abspath(__file__))

PENALTIES = [
    ("not_indexed", 3, 15), ("dangling_index", 3, 15), ("broken_link", 2, 10),
    ("no_type", 2, 10), ("no_description", 2, 10), ("relative_date", 1, 5),
    ("thin", 1, 5),
    ("conflict", 8, 24), ("duplicate", 5, 20), ("superseded", 3, 12), ("stale", 1, 5),
]

INLINE_SCRIPT_ESCAPES = {"<": "\\u003c", ">": "\\u003e", "&": "\\u0026",
                         "\u2028": "\\u2028", "\u2029": "\\u2029"}


def load(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def score(project, audit):
    counts = flag_counts(project["memories"]) if project else {}
    if project:
        counts["dangling_index"] = len(project["dangling_index"])
    if audit:
        counts["conflict"] = sum(1 for c in audit.get("conflicts", []) if c.get("resolution") in (None, "", "unknown"))
        counts["duplicate"] = sum(1 for d in audit.get("duplicates", []) if d.get("confidence") == "confirmed")
        counts["superseded"] = len(audit.get("superseded", []))
        counts["stale"] = len(audit.get("stale", []))
    total, breakdown = 100, {}
    for code, per, cap in PENALTIES:
        n = counts.get(code, 0)
        if n:
            pen = min(n * per, cap)
            breakdown[code] = {"n": n, "penalty": pen}
            total -= pen
    total = max(0, total)
    label = "score" if audit else "score, stats only"
    if not project:
        label = "no memory dir for this project"
    return {"value": total, "label": label, "breakdown": breakdown}


def audit_for(inv, audit):
    if not audit or audit.get("slug") not in (None, inv["current"]):
        return None
    shown = dict(audit)
    shown["next_actions"] = [a for a in audit.get("next_actions", []) if not a.get("applied")]
    return shown


def inline_json(value):
    text = json.dumps(value, ensure_ascii=False)
    return re.sub("[<>&\u2028\u2029]", lambda m: INLINE_SCRIPT_ESCAPES[m.group(0)], text)


def fill(template, values):
    return re.sub("__(INVENTORY|AUDIT|SCORE)__", lambda m: inline_json(values[m.group(1)]), template)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--template", default=os.path.join(HERE, "..", "template.html"))
    ap.add_argument("--no-audit", action="store_true")
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    inv = load(os.path.join(args.dir, "inventory.json"))
    if inv is None:
        sys.exit("no inventory.json in " + args.dir)
    audit = None if args.no_audit else audit_for(inv, load(os.path.join(args.dir, "audit.json")))
    score_path = os.path.join(args.dir, "score.json")
    prev = load(score_path)
    if prev is not None:
        os.replace(score_path, os.path.join(args.dir, "score.prev.json"))
    project = inv["projects"].get(inv["current"])
    sc = score(project, audit)
    sc["prev"] = prev["value"] if prev and prev.get("label") == sc["label"] else None

    with open(args.template, encoding="utf-8") as f:
        html = fill(f.read(), {"INVENTORY": inv, "AUDIT": audit, "SCORE": sc})
    out = os.path.join(args.dir, "index.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    with open(score_path, "w", encoding="utf-8") as f:
        json.dump(sc, f, indent=1)
    print("score %d (%s) -> %s" % (sc["value"], sc["label"], out))
    if not args.no_open:
        opener = "open" if sys.platform == "darwin" else "xdg-open"
        try:
            subprocess.Popen([opener, out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass


if __name__ == "__main__":
    main()
