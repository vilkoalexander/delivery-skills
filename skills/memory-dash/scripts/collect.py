#!/usr/bin/env python3
"""Scan Claude Code auto-memory dirs into inventory.json.

Usage: collect.py [--root DIR] [--current SLUG] [--out FILE] [--today DATE] [--slug]
  --root     memory root, default ~/.claude/projects (env MEMORY_ROOT)
  --current  slug of the current project, default derived from $PWD
  --out      output path, default stdout
  --today    YYYY-MM-DD, default today
  --slug     print the slug of the current project and stop
"""
import argparse
import datetime as dt
import json
import os
import re
import sys

TYPES = ("user", "feedback", "project", "reference")
STOP = set("""
a an the and or of to in on for with is are was were be by as at it its this
that from not no but if then than so we you i he she they them their our your
use used using when what which who how why all any each one two into over
та і й у в на з із до для не що це як при або але від за по про так
""".split())
RELATIVE_DATE = re.compile(
    r"\b(tomorrow|yesterday|next week|last week|this week|next month|"
    r"завтра|вчора|наступного тижня|минулого тижня|цього тижня|"
    r"наступного місяця)\b", re.I)
LINK = re.compile(r"\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]")
INDEX_PTR = re.compile(r"\]\(([^)\s]+\.md)\)|`([\w.\-]+\.md)`")
STALE_DAYS = 180
DUP_JACCARD = 0.5


def slug_of(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def resolve_slug(root, cwd):
    path = cwd
    while True:
        slug = slug_of(path)
        if os.path.isdir(os.path.join(root, slug, "memory")):
            return slug
        parent = os.path.dirname(path)
        if parent == path:
            return slug_of(cwd)
        path = parent


def display_from_slug(slug):
    """Undo Claude Code's lossy path encoding by probing the filesystem."""
    parts = slug.lstrip("-").split("-")

    def walk(prefix, i):
        if i == len(parts):
            return prefix if os.path.exists(prefix) else None
        if os.path.isdir(prefix or "/"):
            found = walk(prefix + "/" + parts[i], i + 1)
            if found:
                return found
        if i > 0:
            return walk(prefix + "-" + parts[i], i + 1)
        return None

    found = walk("", 0) if slug.startswith("-") and len(parts) <= 18 else None
    return found or slug


def frontmatter_lines(text):
    """Return (lines between the fences, body), or (None, text) when a fence is missing."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i], "\n".join(lines[i + 1:])
    return None, text


def parse_frontmatter(text):
    """Return (fields, body, parsed_ok). Hand-rolled: no YAML lib on py3.9."""
    text = text.lstrip("\ufeff")
    if not text.startswith("---"):
        return None, text, True
    head, body = frontmatter_lines(text)
    if head is None:
        return None, text, False
    fields, ok, parent, block = {}, True, None, None
    for raw in head:
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if block and indent > 0:
            fields[block] = (fields.get(block, "") + " " + raw.strip()).strip()
            continue
        block = None
        m = re.match(r"\s*([A-Za-z0-9_\-]+)\s*:\s*(.*)$", raw)
        if not m:
            ok = False
            continue
        key, val = m.group(1), m.group(2).strip()
        full_key = key if indent == 0 else (parent + "." + key if parent else None)
        if full_key is None:
            ok = False
        elif re.match(r"[>|][+-]?$", val):
            block = full_key
        elif indent == 0 and val == "":
            parent = key
        else:
            if indent == 0:
                parent = None
            fields[full_key] = unquote(val)
    return fields, body, ok


def unquote(v):
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def tokens(s):
    words = re.findall(r"[^\W\d_]{3,}", s.lower())
    return {w for w in words if w not in STOP}


def jaccard(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def stem_key(file):
    s = re.sub(r"\.md$", "", file)
    s = re.sub(r"[_\-]?v?\d+", "", s)
    return s.strip("_-").lower()


def read_memory(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    st = os.stat(path)
    mtime = dt.date.fromtimestamp(st.st_mtime)
    fields, body, ok = parse_frontmatter(text)
    flags = []
    if fields is None:
        flags.append("no_frontmatter")
        fields = {}
    elif not ok:
        flags.append("frontmatter_unparsed")
    typ = fields.get("type") or fields.get("metadata.type")
    name = fields.get("name") or re.sub(r"\.md$", "", os.path.basename(path))
    desc = fields.get("description") or ""
    if typ is None:
        flags.append("no_type")
    elif typ not in TYPES:
        flags.append("bad_type")
    if len(desc) < 20:
        flags.append("no_description")
    body_stripped = body.strip()
    if len(body_stripped) < 80:
        flags.append("thin")
    if len(body_stripped) > 2500:
        flags.append("long")
    if RELATIVE_DATE.search(body):
        flags.append("relative_date")
    return {
        "file": os.path.basename(path),
        "name": name,
        "description": desc,
        "type": typ,
        "origin_session": fields.get("metadata.originSessionId"),
        "mtime": mtime.isoformat(),
        "bytes": st.st_size,
        "lines": text.count("\n") + 1,
        "links": sorted(set(LINK.findall(body))),
        "body_chars": len(body_stripped),
        "body_preview": re.sub(r"\s+", " ", body_stripped)[:240],
        "flags": flags,
    }


def index_pointers(mem_dir):
    path = os.path.join(mem_dir, "MEMORY.md")
    if not os.path.exists(path):
        return False, set()
    with open(path, encoding="utf-8", errors="replace") as f:
        return True, {a or b for a, b in INDEX_PTR.findall(f.read())}


def read_memories(mem_dir):
    memories, errors = [], []
    for file in sorted(os.listdir(mem_dir)):
        if not file.endswith(".md") or file == "MEMORY.md":
            continue
        try:
            memories.append(read_memory(os.path.join(mem_dir, file)))
        except OSError as e:
            errors.append("%s: %s" % (file, e.strerror or e))
    return memories, errors


def flag_links(memories):
    names = {m["name"] for m in memories} | {re.sub(r"\.md$", "", m["file"]) for m in memories}
    counts = {}
    for m in memories:
        for link in m["links"]:
            counts[link] = counts.get(link, 0) + 1
            if link not in names:
                m.setdefault("broken_links", []).append(link)
        if m.get("broken_links"):
            m["flags"].append("broken_link")
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:20]


def flag_duplicate_candidates(memories):
    words = {m["file"]: tokens(m["name"] + " " + m["description"]) for m in memories}
    for i, a in enumerate(memories):
        for b in memories[i + 1:]:
            same_stem = stem_key(a["file"]) == stem_key(b["file"])
            if same_stem or jaccard(words[a["file"]], words[b["file"]]) >= DUP_JACCARD:
                a["flags"].append("dup_candidate:" + b["file"])
                b["flags"].append("dup_candidate:" + a["file"])


def flag_old_and_defective(memories, today):
    for m in memories:
        age = (today - dt.date.fromisoformat(m["mtime"])).days
        if m["type"] == "project" and age > STALE_DAYS and m["flags"]:
            m["flags"].append("stale_180")


def count_by_type(memories):
    counts = {t: 0 for t in TYPES}
    counts["none"] = 0
    for m in memories:
        counts[m["type"] if m["type"] in TYPES else "none"] += 1
    return counts


def week_key(day):
    year, week, _ = day.isocalendar()
    return "%d-W%02d" % (year, week)


def count_by_week(memories, today):
    monday = today - dt.timedelta(days=today.weekday())
    counts = {week_key(monday - dt.timedelta(weeks=i)): 0 for i in range(11, -1, -1)}
    for m in memories:
        key = week_key(dt.date.fromisoformat(m["mtime"]))
        if key in counts:
            counts[key] += 1
    return counts


def flag_counts(memories):
    counts = {}
    for m in memories:
        for flag in m["flags"]:
            code = flag.split(":")[0]
            counts[code] = counts.get(code, 0) + 1
    return counts


def scan_project(slug, mem_dir, today):
    memories, errors = read_memories(mem_dir)
    index_present, indexed = index_pointers(mem_dir)
    on_disk = {m["file"] for m in memories}
    not_indexed = sorted(on_disk - indexed)
    for m in memories:
        if m["file"] in not_indexed:
            m["flags"].append("not_indexed")
    top_links = flag_links(memories)
    flag_duplicate_candidates(memories)
    flag_old_and_defective(memories, today)
    return {
        "display": display_from_slug(slug),
        "files": len(memories),
        "by_type": count_by_type(memories),
        "index_present": index_present,
        "not_indexed": not_indexed,
        "dangling_index": sorted(indexed - on_disk),
        "by_week": count_by_week(memories, today),
        "top_links": top_links,
        "memories": memories,
    }, errors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get(
        "MEMORY_ROOT", os.path.expanduser("~/.claude/projects")))
    ap.add_argument("--current", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--today", default=None, help="YYYY-MM-DD, for tests")
    ap.add_argument("--slug", action="store_true")
    args = ap.parse_args()
    today = dt.date.fromisoformat(args.today) if args.today else dt.date.today()
    current = args.current or resolve_slug(args.root, os.getcwd())
    if args.slug:
        print(current)
        return
    projects, errors = {}, []
    if not os.path.isdir(args.root):
        errors.append("root not found: " + args.root)
    else:
        for slug in sorted(os.listdir(args.root)):
            mem_dir = os.path.join(args.root, slug, "memory")
            if not os.path.isdir(mem_dir):
                continue
            try:
                p, file_errors = scan_project(slug, mem_dir, today)
            except OSError as e:
                errors.append("%s: %s" % (slug, e))
                continue
            errors.extend("%s/%s" % (slug, e) for e in file_errors)
            if p["files"] == 0 and not p["index_present"]:
                continue
            projects[slug] = p
    totals_type = {t: 0 for t in TYPES}
    totals_type["none"] = 0
    totals_flags = {}
    for p in projects.values():
        for t, n in p["by_type"].items():
            totals_type[t] += n
        for code, n in flag_counts(p["memories"]).items():
            totals_flags[code] = totals_flags.get(code, 0) + n
    out = {
        "generated": dt.datetime.now().isoformat(timespec="seconds"),
        "current": current,
        "current_found": current in projects,
        "projects": projects,
        "totals": {
            "projects": len(projects),
            "files": sum(p["files"] for p in projects.values()),
            "by_type": totals_type,
            "flags": totals_flags,
        },
        "errors": errors,
    }
    for error in errors:
        print("not read: " + error, file=sys.stderr)
    data = json.dumps(out, ensure_ascii=False, indent=1)
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(data)
        print("inventory: %d projects, %d files -> %s" % (
            out["totals"]["projects"], out["totals"]["files"], args.out))
    else:
        sys.stdout.write(data)


if __name__ == "__main__":
    main()
