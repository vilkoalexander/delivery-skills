#!/usr/bin/env python3
"""Render inventory.json [+ audit.json] into index.html and open it.

Usage: render.py --dir OUTDIR [--template FILE] [--no-open]
  OUTDIR holds inventory.json, optional audit.json and audit.prev.json;
  index.html and score.json are written next to them.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Penalty table. Keep in sync with RUBRIC.md; that file is the explanation,
# this is the arithmetic.
PENALTIES = [
    ("not_indexed", 3, 15), ("dangling_index", 3, 15), ("broken_link", 2, 10),
    ("no_type", 2, 10), ("no_description", 2, 10), ("relative_date", 1, 5),
    ("thin", 1, 5),
    ("conflict", 8, 24), ("duplicate", 5, 20), ("superseded", 3, 12), ("stale", 1, 5),
]


def load(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def count_flags(project):
    counts = {}
    for m in project["memories"]:
        for fl in m["flags"]:
            code = fl.split(":")[0]
            counts[code] = counts.get(code, 0) + 1
    counts["dangling_index"] = len(project["dangling_index"])
    return counts


def score(project, audit):
    counts = count_flags(project) if project else {}
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--template", default=os.path.join(HERE, "..", "template.html"))
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    inv = load(os.path.join(args.dir, "inventory.json"))
    if inv is None:
        sys.exit("no inventory.json in " + args.dir)
    audit = load(os.path.join(args.dir, "audit.json"))
    prev = load(os.path.join(args.dir, "score.prev.json"))
    project = inv["projects"].get(inv["current"])
    sc = score(project, audit)
    sc["prev"] = prev["value"] if prev and prev.get("label") == sc["label"] else None

    with open(args.template, encoding="utf-8") as f:
        html = f.read()
    def j(x):
        return json.dumps(x, ensure_ascii=False).replace("</", "<\\/")
    html = html.replace("__INVENTORY__", j(inv)).replace("__AUDIT__", j(audit)).replace("__SCORE__", j(sc))
    out = os.path.join(args.dir, "index.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    with open(os.path.join(args.dir, "score.json"), "w", encoding="utf-8") as f:
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
