#!/usr/bin/env python3
"""Apply one next_action from audit.json to the memory dir.

Usage: apply.py --audit FILE --memdir DIR --n N [--yes]
Prints the full old and new content of every file it touches, then writes.
Exit 2 for a `resolve` action (needs a human answer), 1 on a bad action.
"""
import argparse
import json
import os
import re
import sys


def read(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def show(title, old, new):
    print("=" * 72)
    print(title)
    print("-" * 32 + " before " + "-" * 32)
    print(old if old is not None else "(no file)")
    print("-" * 32 + " after  " + "-" * 32)
    print(new if new is not None else "(deleted)")


def index_remove(index, file):
    lines = [l for l in index.split("\n") if file not in l]
    return "\n".join(lines)


def index_add(index, file, name, description):
    line = "- [%s](%s) — %s" % (name, file, description)
    if file in index:
        return index
    return index.rstrip("\n") + "\n" + line + "\n"


def frontmatter_of(text):
    m = re.match(r"^---\n(.*?)\n---", text or "", re.S)
    fields = {}
    if m:
        for raw in m.group(1).split("\n"):
            km = re.match(r"\s*([\w\-]+)\s*:\s*(.*)$", raw)
            if km:
                fields[km.group(1)] = km.group(2).strip().strip("\"'")
    return fields


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", required=True)
    ap.add_argument("--memdir", required=True)
    ap.add_argument("--n", type=int, required=True)
    ap.add_argument("--yes", action="store_true", help="write; without it only print")
    args = ap.parse_args()

    audit = json.load(open(args.audit, encoding="utf-8"))
    acts = {a["n"]: a for a in audit.get("next_actions", [])}
    if args.n not in acts:
        sys.exit("no action %d in %s" % (args.n, args.audit))
    a = acts[args.n]
    kind, files, edit = a["kind"], a["files"], a.get("edit")
    mem = args.memdir
    idx_path = os.path.join(mem, "MEMORY.md")
    index = read(idx_path) or "# Memory Index\n"
    plan = []  # (path, new_content or None)

    if kind == "resolve":
        print("action %d needs a decision: %s" % (args.n, a["text"]))
        for f in files:
            print("--- " + f); print(read(os.path.join(mem, f)))
        sys.exit(2)
    elif kind == "delete":
        for f in files:
            plan.append((os.path.join(mem, f), None))
            index = index_remove(index, f)
    elif kind == "merge":
        if not edit or len(files) < 2:
            sys.exit("merge needs `edit` and files [keep, drop, ...]")
        keep, drops = files[0], files[1:]
        plan.append((os.path.join(mem, keep), edit))
        for d in drops:
            plan.append((os.path.join(mem, d), None))
            index = index_remove(index, d)
        fm = frontmatter_of(edit)
        index = index_remove(index, keep)
        index = index_add(index, keep, fm.get("name", keep), fm.get("description", ""))
    elif kind == "rewrite":
        if not edit or len(files) != 1:
            sys.exit("rewrite needs `edit` and exactly one file")
        plan.append((os.path.join(mem, files[0]), edit))
        fm = frontmatter_of(edit)
        index = index_remove(index, files[0])
        index = index_add(index, files[0], fm.get("name", files[0]), fm.get("description", ""))
    elif kind == "reindex":
        for f in files:
            path = os.path.join(mem, f)
            if os.path.exists(path):
                fm = frontmatter_of(read(path))
                index = index_add(index, f, fm.get("name", f), fm.get("description", ""))
            else:
                index = index_remove(index, f)
    else:
        sys.exit("unknown kind " + kind)

    old_index = read(idx_path)
    if old_index != index:
        plan.append((idx_path, index))
    for path, new in plan:
        show(path, read(path), new)
    if not args.yes:
        print("\n(dry run; add --yes to write)")
        return
    for path, new in plan:
        if new is None:
            os.remove(path)
        else:
            write(path, new)
    print("\napplied action %d (%s): %d file(s) written" % (args.n, kind, len(plan)))


if __name__ == "__main__":
    main()
