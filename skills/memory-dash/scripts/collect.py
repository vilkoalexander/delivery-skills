#!/usr/bin/env python3
"""Scan Claude Code auto-memory dirs into inventory.json.

Usage: collect.py [--root DIR] [--current SLUG] [--out FILE]
  --root     memory root, default ~/.claude/projects (env MEMORY_ROOT)
  --current  slug of the current project, default derived from $PWD
  --out      output path, default stdout
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
та і й у в на з із до для не що це як при або але від за по про від так
""".split())
RELATIVE_DATE = re.compile(
    r"\b(tomorrow|yesterday|next week|last week|this week|next month|"
    r"завтра|вчора|наступного тижня|минулого тижня|цього тижня|"
    r"наступного місяця)\b", re.I)
LINK = re.compile(r"\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]")
INDEX_PTR = re.compile(r"\]\(([^)\s]+\.md)\)|`([\w.\-]+\.md)`")
STALE_DAYS = 180
DUP_JACCARD = 0.5


def slug_from_cwd():
    return os.getcwd().replace("/", "-")


def display_from_slug(slug):
    """Undo Claude Code's lossy path encoding by probing the filesystem."""
    parts = slug.lstrip("-").split("-")

    def walk(prefix, i):
        if i == len(parts):
            return prefix
        for sep in ("/", "-"):
            if sep == "-" and i == 0:
                continue
            cand = prefix + sep + parts[i]
            if i == len(parts) - 1 and not os.path.exists(cand):
                continue
            found = walk(cand, i + 1)
            if found:
                return found
        return None

    found = walk("", 0) if slug.startswith("-") and len(parts) <= 18 else None
    return found or slug


def parse_frontmatter(text):
    """Return (fields, body, parsed_ok). Hand-rolled: no YAML lib on py3.9."""
    if not text.startswith("---"):
        return None, text, True
    lines = text.split("\n")
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None, text, False
    fields, ok, parent = {}, True, None
    for raw in lines[1:end]:
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        m = re.match(r"\s*([A-Za-z0-9_\-]+)\s*:\s*(.*)$", raw)
        if not m:
            ok = False
            continue
        key, val = m.group(1), m.group(2).strip()
        if indent == 0:
            parent = key if val == "" else None
            if val != "":
                fields[key] = unquote(val)
        elif parent:
            fields[parent + "." + key] = unquote(val)
        else:
            ok = False
    body = "\n".join(lines[end + 1:])
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


def read_memory(path, today):
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
    if typ == "project" and (today - mtime).days > STALE_DAYS:
        flags.append("stale_180")
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
        "_tokens": tokens(name + " " + desc),
    }


def scan_project(slug, mem_dir, today):
    files = sorted(f for f in os.listdir(mem_dir)
                   if f.endswith(".md") and f != "MEMORY.md")
    memories = [read_memory(os.path.join(mem_dir, f), today) for f in files]
    index_path = os.path.join(mem_dir, "MEMORY.md")
    index_present = os.path.exists(index_path)
    indexed = set()
    if index_present:
        with open(index_path, encoding="utf-8", errors="replace") as f:
            indexed = {a or b for a, b in INDEX_PTR.findall(f.read())}
    on_disk = set(files)
    not_indexed = sorted(on_disk - indexed)
    dangling = sorted(indexed - on_disk)
    names = {m["name"] for m in memories} | {re.sub(r"\.md$", "", f) for f in files}
    link_counts = {}
    for m in memories:
        for l in m["links"]:
            link_counts[l] = link_counts.get(l, 0) + 1
            if l not in names:
                m.setdefault("broken_links", []).append(l)
    for m in memories:
        if m["file"] in not_indexed:
            m["flags"].append("not_indexed")
        if m.get("broken_links"):
            m["flags"].append("broken_link")
    for i, a in enumerate(memories):
        for b in memories[i + 1:]:
            same_stem = stem_key(a["file"]) == stem_key(b["file"])
            if same_stem or jaccard(a["_tokens"], b["_tokens"]) >= DUP_JACCARD:
                a["flags"].append("dup_candidate:" + b["file"])
                b["flags"].append("dup_candidate:" + a["file"])
    by_type = {t: 0 for t in TYPES}
    by_type["none"] = 0
    by_week = {}
    for m in memories:
        by_type[m["type"] if m["type"] in TYPES else "none"] += 1
        y, w, _ = dt.date.fromisoformat(m["mtime"]).isocalendar()
        key = "%d-W%02d" % (y, w)
        by_week[key] = by_week.get(key, 0) + 1
        del m["_tokens"]
    weeks = []
    monday = today - dt.timedelta(days=today.weekday())
    for i in range(11, -1, -1):
        d = monday - dt.timedelta(weeks=i)
        y, w, _ = d.isocalendar()
        weeks.append("%d-W%02d" % (y, w))
    return {
        "display": display_from_slug(slug),
        "files": len(memories),
        "by_type": by_type,
        "index_present": index_present,
        "not_indexed": not_indexed,
        "dangling_index": dangling,
        "by_week": {w: by_week.get(w, 0) for w in weeks},
        "top_links": sorted(link_counts.items(), key=lambda kv: (-kv[1], kv[0]))[:20],
        "memories": memories,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get(
        "MEMORY_ROOT", os.path.expanduser("~/.claude/projects")))
    ap.add_argument("--current", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--today", default=None, help="YYYY-MM-DD, for tests")
    args = ap.parse_args()
    today = dt.date.fromisoformat(args.today) if args.today else dt.date.today()
    current = args.current or slug_from_cwd()
    projects, errors = {}, []
    if not os.path.isdir(args.root):
        errors.append("root not found: " + args.root)
    else:
        for slug in sorted(os.listdir(args.root)):
            mem_dir = os.path.join(args.root, slug, "memory")
            if not os.path.isdir(mem_dir):
                continue
            try:
                p = scan_project(slug, mem_dir, today)
            except OSError as e:
                errors.append("%s: %s" % (slug, e))
                continue
            if p["files"] == 0 and not p["index_present"]:
                continue
            projects[slug] = p
    totals_type = {t: 0 for t in TYPES}
    totals_type["none"] = 0
    totals_flags = {}
    for p in projects.values():
        for t, n in p["by_type"].items():
            totals_type[t] += n
        for m in p["memories"]:
            for fl in m["flags"]:
                code = fl.split(":")[0]
                totals_flags[code] = totals_flags.get(code, 0) + 1
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
