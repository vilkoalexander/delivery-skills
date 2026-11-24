#!/usr/bin/env python3
"""Apply one next_action from audit.json to the memory dir.

Usage: apply.py --audit FILE --memdir DIR --n N [--yes]
Prints the old and new content of every file it touches, then writes. The old
content goes to backup/<time>/ next to the audit file before anything changes.
A file must be a plain *.md name inside --memdir: no path, no symlink.
Exit 2 for a `resolve` action (needs a human answer), 1 on a bad action.
"""
import argparse
import datetime as dt
import json
import os
import re
import shutil
import sys

from collect import parse_frontmatter

INDEX = "MEMORY.md"
POINTER = re.compile(r"\]\(([^)\s]+)\)|`([^`\s]+\.md)`")
FINDING_FILES = {
    "duplicates": lambda f: [f.get("keep"), f.get("drop")],
    "conflicts": lambda f: f.get("files", []),
    "superseded": lambda f: [f.get("newer"), f.get("older")],
    "stale": lambda f: [f.get("file")],
    "task_like": lambda f: [f.get("file")],
}


def read(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def write(path, content):
    temp = path + ".memory-dash.tmp"
    with open(temp, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(temp, path)


def show(title, old, new):
    print("=" * 72)
    print(title)
    print("-" * 32 + " before " + "-" * 32)
    print(old if old is not None else "(no file)")
    print("-" * 32 + " after  " + "-" * 32)
    print(new if new is not None else "(deleted)")


def memory_path(mem, file):
    if not isinstance(file, str) or os.path.basename(file) != file or not file.endswith(".md") or file == INDEX:
        sys.exit("refused %r: a memory file is a plain *.md name inside %s" % (file, mem))
    path = os.path.join(mem, file)
    if os.path.islink(path):
        sys.exit("refused %r: it is a symlink" % file)
    if os.path.realpath(path) != os.path.join(os.path.realpath(mem), file):
        sys.exit("refused %r: it is outside %s" % (file, mem))
    return path


def points_to(line, file):
    return any(file in pair for pair in POINTER.findall(line))


def index_line(file, content):
    fields = parse_frontmatter(content)[0] or {}
    return "- [%s](%s) — %s" % (fields.get("name") or file, file, fields.get("description") or "")


def index_remove(lines, file):
    return [line for line in lines if not points_to(line, file)]


def index_add(lines, file, content):
    if any(points_to(line, file) for line in lines):
        return lines
    while lines and lines[-1] == "":
        lines = lines[:-1]
    return lines + [index_line(file, content), ""]


def index_update(lines, file, old_content, new_content):
    """Replaces the line of a rewritten file where it stands; a line whose name and description still hold stays as written."""
    new_line = index_line(file, new_content)
    if not any(points_to(line, file) for line in lines):
        return index_add(lines, file, new_content)
    if old_content is not None and index_line(file, old_content) == new_line:
        return lines
    return [new_line if points_to(line, file) else line for line in lines]


def plan_action(action, mem, index_lines):
    """Returns (changes, index_lines). A change is (file, new content or None for a delete)."""
    kind, files, edit = action["kind"], action["files"], action.get("edit")
    paths = {file: memory_path(mem, file) for file in files}
    changes = []

    def delete(file):
        nonlocal index_lines
        changes.append((file, None))
        index_lines = index_remove(index_lines, file)

    def put(file):
        nonlocal index_lines
        changes.append((file, edit))
        index_lines = index_update(index_lines, file, read(paths[file]), edit)

    if kind == "delete":
        for file in files:
            delete(file)
    elif kind == "merge":
        if not edit or len(files) < 2:
            sys.exit("merge needs `edit` and files [keep, drop, ...]")
        put(files[0])
        for file in files[1:]:
            delete(file)
    elif kind == "rewrite":
        if not edit or len(files) != 1:
            sys.exit("rewrite needs `edit` and exactly one file")
        put(files[0])
    elif kind == "reindex":
        for file in files:
            content = read(paths[file])
            if content is None:
                index_lines = index_remove(index_lines, file)
            else:
                index_lines = index_add(index_lines, file, content)
    else:
        sys.exit("unknown kind %s" % kind)
    return changes, index_lines


def back_up(paths, audit_path):
    folder = os.path.join(os.path.dirname(os.path.abspath(audit_path)), "backup",
                          dt.datetime.now().strftime("%Y%m%dT%H%M%S%f"))
    os.makedirs(folder)
    for path in paths:
        shutil.copy2(path, os.path.join(folder, os.path.basename(path)))
    return folder


def mark_applied(audit, action, touched):
    action["applied"] = True
    for section, files_of in FINDING_FILES.items():
        if section in audit:
            audit[section] = [f for f in audit[section] if not touched.intersection(files_of(f))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", required=True)
    ap.add_argument("--memdir", required=True)
    ap.add_argument("--n", type=int, required=True)
    ap.add_argument("--yes", action="store_true", help="write; without it only print")
    args = ap.parse_args()

    with open(args.audit, encoding="utf-8") as f:
        audit = json.load(f)
    actions = {a["n"]: a for a in audit.get("next_actions", [])}
    if args.n not in actions:
        sys.exit("no action %d in %s" % (args.n, args.audit))
    action = actions[args.n]
    mem = args.memdir
    if not os.path.isdir(mem):
        sys.exit("no memory dir %s" % mem)

    if action["kind"] == "resolve":
        paths = [(file, memory_path(mem, file)) for file in action["files"]]
        print("action %d needs a decision: %s" % (args.n, action["text"]))
        for file, path in paths:
            print("--- " + file)
            print(read(path))
        sys.exit(2)

    index_path = os.path.join(mem, INDEX)
    old_index = read(index_path)
    start_lines = (old_index or "# Memory Index\n").split("\n")
    changes, index_lines = plan_action(action, mem, start_lines)
    new_index = "\n".join(index_lines)

    writes, deletes = [], []
    for file, new in changes:
        path = os.path.join(mem, file)
        old = read(path)
        if new is None and old is None:
            print("%s: already gone" % file)
        elif new is None:
            deletes.append(path)
            show(path, old, None)
        elif old != new:
            writes.append((path, new))
            show(path, old, new)
    if index_lines != start_lines:
        writes.append((index_path, new_index))
        show(index_path, old_index, new_index)

    if not writes and not deletes:
        print("\naction %d (%s): nothing to do" % (args.n, action["kind"]))
        return
    if not args.yes:
        print("\n(dry run; add --yes to write)")
        return

    existing = [path for path, _ in writes if os.path.exists(path)] + deletes
    backup = back_up(existing, args.audit) if existing else None
    for path, new in writes:
        write(path, new)
    for path in deletes:
        os.remove(path)
    mark_applied(audit, action, {file for file, _ in changes})
    write(args.audit, json.dumps(audit, ensure_ascii=False, indent=1))
    print("\napplied action %d (%s): %d written, %d deleted" % (args.n, action["kind"], len(writes), len(deletes)))
    if backup:
        print("old content: " + backup)


if __name__ == "__main__":
    main()
