import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "..", "scripts")
sys.path.insert(0, SCRIPTS)
import collect as collect_module  # noqa: E402
import render as render_module  # noqa: E402
ROOT = os.path.join(HERE, "fixtures", "root")
AUDIT = os.path.join(HERE, "fixtures", "audit.json")
CUR = "-Users-me-app-one"


def run(script, *args):
    return subprocess.run([sys.executable, os.path.join(SCRIPTS, script)] + list(args),
                          capture_output=True, text=True)


def collect(out):
    r = run("collect.py", "--root", ROOT, "--current=" + CUR, "--today", "2026-10-12", "--out", out)
    assert r.returncode == 0, r.stderr
    with open(out, encoding="utf-8") as f:
        return json.load(f)


class CollectTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        # A fresh checkout stamps every file with today; the stale flag needs an old one.
        old = 1735689600  # 2025-01-01
        os.utime(os.path.join(ROOT, CUR, "memory", "db_host.md"), (old, old))
        cls.inv = collect(os.path.join(cls.tmp, "inventory.json"))
        cls.p = cls.inv["projects"][CUR]
        cls.by_file = {m["file"]: m for m in cls.p["memories"]}

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def test_projects_and_counts(self):
        self.assertEqual(self.inv["current"], CUR)
        self.assertTrue(self.inv["current_found"])
        self.assertEqual(set(self.inv["projects"]), {CUR, "-Users-me-app-two"})
        self.assertEqual(self.p["files"], 5)
        self.assertEqual(self.inv["totals"]["files"], 6)

    def test_frontmatter_variants(self):
        self.assertEqual(self.by_file["db_host.md"]["type"], "project")       # metadata.type
        self.assertEqual(self.by_file["db_host_v2.md"]["type"], "project")    # top-level, quoted desc
        self.assertEqual(self.by_file["db_host_v2.md"]["description"][:10], "Production")
        self.assertIsNone(self.by_file["raw.md"]["type"])
        self.assertIn("no_frontmatter", self.by_file["raw.md"]["flags"])
        self.assertIn("no_type", self.by_file["raw.md"]["flags"])

    def test_index(self):
        self.assertEqual(self.p["not_indexed"], ["orphan.md", "raw.md"])
        self.assertEqual(self.p["dangling_index"], ["ghost.md"])
        self.assertIn("not_indexed", self.by_file["orphan.md"]["flags"])
        self.assertNotIn("not_indexed", self.by_file["feedback_style.md"]["flags"])  # backtick pointer counts

    def test_links(self):
        m = self.by_file["db_host.md"]
        self.assertEqual(m["links"], ["feedback-style", "missing-target"])
        self.assertEqual(m["broken_links"], ["missing-target"])
        self.assertIn("broken_link", m["flags"])
        self.assertEqual(self.p["top_links"][0], ["feedback-style", 1])

    def test_flags(self):
        self.assertIn("relative_date", self.by_file["db_host_v2.md"]["flags"])
        self.assertIn("stale_180", self.by_file["db_host.md"]["flags"])
        self.assertIn("dup_candidate:db_host_v2.md", self.by_file["db_host.md"]["flags"])
        self.assertIn("dup_candidate:db_host.md", self.by_file["db_host_v2.md"]["flags"])
        self.assertNotIn("thin", self.by_file["feedback_style.md"]["flags"])

    def test_by_type_and_week(self):
        self.assertEqual(self.p["by_type"], {"user": 0, "feedback": 1, "project": 2, "reference": 1, "none": 1})
        self.assertEqual(len(self.p["by_week"]), 12)
        self.assertEqual(list(self.p["by_week"])[-1], "2026-W42")


MEMORY = "---\nname: %s\ndescription: %s\ntype: %s\n---\n\n%s\n"
LONG_BODY = "The production database listens on db.internal port 5432 and the role is api_rw for every service."


def make_root(tmp, files, index=None):
    mem = os.path.join(tmp, "root", "-Users-me-app", "memory")
    os.makedirs(mem)
    for name, text in files.items():
        with open(os.path.join(mem, name), "w", encoding="utf-8") as f:
            f.write(text)
    if index is not None:
        with open(os.path.join(mem, "MEMORY.md"), "w", encoding="utf-8") as f:
            f.write(index)
    return os.path.join(tmp, "root"), mem


def collect_root(root, out):
    r = run("collect.py", "--root", root, "--current=-Users-me-app", "--today", "2026-10-12", "--out", out)
    assert r.returncode == 0, r.stderr
    with open(out, encoding="utf-8") as f:
        return json.load(f), r


class CollectEdgeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.out = os.path.join(self.tmp, "inventory.json")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_slug_replaces_every_non_alphanumeric(self):
        self.assertEqual(collect_module.slug_of("/Users/me/my.app/x_y z"), "-Users-me-my-app-x-y-z")

    def test_slug_resolves_to_the_parent_that_has_memory(self):
        self.assertEqual(collect_module.resolve_slug(ROOT, "/Users/me/app-one/skills/deep"), CUR)
        self.assertEqual(collect_module.resolve_slug(ROOT, "/Users/me/nowhere"), "-Users-me-nowhere")

    def test_slug_flag_prints_the_slug(self):
        r = run("collect.py", "--root", ROOT, "--slug")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.startswith("-"))

    def test_unreadable_file_is_listed_and_the_project_stays(self):
        root, mem = make_root(self.tmp, {"good.md": MEMORY % ("good", "A good memory about the database", "project", LONG_BODY)},
                              "- [good](good.md) — x\n")
        os.symlink(os.path.join(mem, "missing-target"), os.path.join(mem, "broken.md"))
        inv, r = collect_root(root, self.out)
        self.assertIn("-Users-me-app", inv["projects"])
        self.assertEqual(inv["projects"]["-Users-me-app"]["files"], 1)
        self.assertTrue(any("broken.md" in e for e in inv["errors"]), inv["errors"])
        self.assertIn("broken.md", r.stderr)

    def test_folded_description_and_bom(self):
        folded = "---\nname: folded\ndescription: >\n  The production database host\n  and its port.\ntype: project\n---\n\n" + LONG_BODY + "\n"
        bom = "\ufeff" + MEMORY % ("bom", "A memory that starts with a byte order mark", "user", LONG_BODY)
        root, _ = make_root(self.tmp, {"folded.md": folded, "bom.md": bom}, "- [a](folded.md) — x\n- [b](bom.md) — y\n")
        inv, _ = collect_root(root, self.out)
        by_file = {m["file"]: m for m in inv["projects"]["-Users-me-app"]["memories"]}
        self.assertEqual(by_file["folded.md"]["description"], "The production database host and its port.")
        self.assertNotIn("no_description", by_file["folded.md"]["flags"])
        self.assertNotIn("no_frontmatter", by_file["bom.md"]["flags"])
        self.assertEqual(by_file["bom.md"]["type"], "user")

    def test_age_alone_is_not_a_flag(self):
        root, mem = make_root(self.tmp, {"old.md": MEMORY % ("old", "An old but healthy project memory", "project", LONG_BODY)},
                              "- [old](old.md) — x\n")
        old = 1735689600
        os.utime(os.path.join(mem, "old.md"), (old, old))
        inv, _ = collect_root(root, self.out)
        self.assertEqual(inv["projects"]["-Users-me-app"]["memories"][0]["flags"], [])

    def test_memories_carry_no_private_fields(self):
        root, _ = make_root(self.tmp, {"a.md": MEMORY % ("a", "A memory about the database host", "project", LONG_BODY)})
        inv, _ = collect_root(root, self.out)
        self.assertFalse([k for k in inv["projects"]["-Users-me-app"]["memories"][0] if k.startswith("_")])


class Checker(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        for k, v in attrs:
            if k == "id":
                self.ids.add(v)


class RenderTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        collect(os.path.join(self.tmp, "inventory.json"))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def render(self):
        r = run("render.py", "--dir", self.tmp, "--no-open")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(os.path.join(self.tmp, "score.json")) as f:
            score = json.load(f)
        with open(os.path.join(self.tmp, "index.html"), encoding="utf-8") as f:
            html = f.read()
        return score, html

    def test_stats_only(self):
        score, html = self.render()
        # not_indexed 2*3 + dangling 1*3 + broken_link 2 + no_type 2 + no_description 2 + relative_date 1 = 16
        self.assertEqual(score["value"], 84)
        self.assertEqual(score["label"], "score, stats only")
        c = Checker(); c.feed(html)
        for sid in ("score", "actions", "projects", "c-type-all", "c-week", "t-cur", "s-conflicts", "t-all"):
            self.assertIn(sid, c.ids)

    def test_with_audit_and_delta(self):
        shutil.copy(AUDIT, os.path.join(self.tmp, "audit.json"))
        score, html = self.render()
        # 16 + conflict 8 + stale 1 = 25 (plausible duplicate not counted)
        self.assertEqual(score["value"], 75)
        self.assertEqual(score["label"], "score")
        self.assertIsNone(score["prev"])
        score2, _ = self.render()
        self.assertEqual(score2["prev"], 75)
        self.assertIn("Which host is live?", html)

    def blocks(self, html):
        found = {}
        for block_id in ("inventory", "audit", "score-data"):
            m = re.search(r'<script type="application/json" id="%s">(.*?)</script>' % block_id, html, re.S)
            self.assertIsNotNone(m, block_id)
            self.assertNotIn("<", m.group(1))
            found[block_id] = json.loads(m.group(1))
        return found

    def test_memory_text_cannot_break_the_page(self):
        inv_path = os.path.join(self.tmp, "inventory.json")
        with open(inv_path, encoding="utf-8") as f:
            inv = json.load(f)
        hostile = "__AUDIT__ __SCORE__ __INVENTORY__ <!-- <script> </script> \u2028 &amp;"
        inv["projects"][CUR]["memories"][0]["description"] = hostile
        with open(inv_path, "w", encoding="utf-8") as f:
            json.dump(inv, f)
        shutil.copy(AUDIT, os.path.join(self.tmp, "audit.json"))
        _, html = self.render()
        found = self.blocks(html)
        self.assertEqual(found["inventory"]["projects"][CUR]["memories"][0]["description"], hostile)
        self.assertEqual(len(found["inventory"]["projects"][CUR]["memories"]), 5)
        self.assertEqual(found["audit"]["slug"], CUR)
        self.assertNotIn("\u2028", html)

    def test_no_audit_flag_ignores_a_stale_audit(self):
        shutil.copy(AUDIT, os.path.join(self.tmp, "audit.json"))
        r = run("render.py", "--dir", self.tmp, "--no-open", "--no-audit")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(os.path.join(self.tmp, "score.json")) as f:
            self.assertEqual(json.load(f)["label"], "score, stats only")

    def test_audit_of_another_project_is_ignored(self):
        with open(AUDIT, encoding="utf-8") as f:
            audit = json.load(f)
        audit["slug"] = "-Users-me-app-two"
        with open(os.path.join(self.tmp, "audit.json"), "w", encoding="utf-8") as f:
            json.dump(audit, f)
        score, _ = self.render()
        self.assertEqual(score["label"], "score, stats only")

    def test_applied_actions_are_not_shown(self):
        with open(AUDIT, encoding="utf-8") as f:
            audit = json.load(f)
        audit["next_actions"][4]["applied"] = True
        with open(os.path.join(self.tmp, "audit.json"), "w", encoding="utf-8") as f:
            json.dump(audit, f)
        _, html = self.render()
        self.assertNotIn("Drop orphan", html)
        self.assertIn("Which host is live?", html)

    def test_penalties_match_the_rubric_table(self):
        with open(os.path.join(HERE, "..", "RUBRIC.md"), encoding="utf-8") as f:
            rows = re.findall(r"^\| ([a-z_]+)[^|]*\| (\d+) \| (\d+) \|", f.read(), re.M)
        self.assertEqual([(code, int(per), int(cap)) for code, per, cap in rows], render_module.PENALTIES)

    def test_page_says_so_when_charts_cannot_load(self):
        _, html = self.render()
        self.assertTrue('id="charts-offline"' in html)
        self.assertTrue("getElementById('charts-offline').hidden = false" in html)


class ApplyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mem = os.path.join(self.tmp, "memory")
        shutil.copytree(os.path.join(ROOT, CUR, "memory"), self.mem)
        self.audit = os.path.join(self.tmp, "out", "audit.json")
        os.makedirs(os.path.dirname(self.audit))
        shutil.copy(AUDIT, self.audit)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def apply(self, n, yes=True):
        args = ["--audit", self.audit, "--memdir", self.mem, "--n", str(n)] + (["--yes"] if yes else [])
        return run("apply.py", *args)

    def action(self, kind, files, edit=None):
        with open(self.audit, "w", encoding="utf-8") as f:
            json.dump({"slug": CUR, "next_actions": [{"n": 1, "kind": kind, "files": files, "text": "t", "edit": edit}]}, f)

    def index(self):
        with open(os.path.join(self.mem, "MEMORY.md")) as f:
            return f.read()

    def put(self, name, text="x\n"):
        with open(os.path.join(self.mem, name), "w", encoding="utf-8") as f:
            f.write(text)

    def test_resolve_exits_2(self):
        r = self.apply(1)
        self.assertEqual(r.returncode, 2)
        self.assertIn("db.internal", r.stdout)

    def test_dry_run_writes_nothing(self):
        before = self.index()
        with open(self.audit, encoding="utf-8") as f:
            audit_before = f.read()
        r = self.apply(2, yes=False)
        self.assertEqual(r.returncode, 0)
        self.assertIn("dry run", r.stdout)
        self.assertEqual(self.index(), before)
        with open(self.audit, encoding="utf-8") as f:
            self.assertEqual(f.read(), audit_before)

    def test_reindex(self):
        r = self.apply(2)
        self.assertEqual(r.returncode, 0, r.stderr)
        idx = self.index()
        self.assertIn("(orphan.md)", idx)
        self.assertIn("[raw.md](raw.md)", idx)
        self.assertNotIn("ghost.md", idx)

    def test_rewrite(self):
        self.apply(3)
        with open(os.path.join(self.mem, "raw.md")) as f:
            self.assertTrue(f.read().startswith("---\nname: staging-bucket"))
        self.assertIn("[staging-bucket](raw.md) — Staging assets bucket name", self.index())

    def test_merge(self):
        r = self.apply(4)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.mem, "db_host.md")))
        with open(os.path.join(self.mem, "db_host_v2.md")) as f:
            self.assertIn("db2.internal:5432, role api_rw", f.read())
        idx = self.index()
        self.assertNotIn("(db_host.md)", idx)
        self.assertIn("[db-host](db_host_v2.md)", idx)
        self.assertIn("before", r.stdout); self.assertIn("after", r.stdout)

    def test_delete(self):
        self.action("delete", ["feedback_style.md"])
        r = self.apply(1)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.mem, "feedback_style.md")))
        self.assertNotIn("feedback_style.md", self.index())
        self.assertIn("(db_host.md)", self.index())

    def test_paths_outside_the_memory_dir_are_refused(self):
        outside = os.path.join(self.tmp, "outside.txt")
        with open(outside, "w") as f:
            f.write("keep me")
        link = os.path.join(self.mem, "link.md")
        os.symlink(outside, link)
        nested = os.path.join(self.mem, "sub")
        os.makedirs(nested)
        cases = [("delete", ["../outside.txt"], None), ("delete", [outside], None),
                 ("rewrite", [outside], "new"), ("rewrite", ["../outside.txt"], "new"),
                 ("delete", ["link.md"], None), ("rewrite", ["link.md"], "new"),
                 ("merge", ["db_host.md", "../outside.txt"], "new"),
                 ("reindex", ["../outside.txt"], None), ("delete", ["sub/../../outside.txt"], None),
                 ("delete", ["MEMORY.md"], None), ("resolve", ["../outside.txt"], None)]
        before = self.index()
        for kind, files, edit in cases:
            self.action(kind, files, edit)
            r = self.apply(1)
            self.assertEqual(r.returncode, 1, (kind, files, r.stdout))
            self.assertNotIn("keep me", r.stdout)
            with open(outside) as f:
                self.assertEqual(f.read(), "keep me", (kind, files))
            self.assertTrue(os.path.islink(link))
            self.assertEqual(self.index(), before)

    def test_index_edits_match_the_whole_file_name(self):
        self.put("host.md")
        self.put("style.md", MEMORY % ("style", "A second style memory", "feedback", "body"))
        with open(os.path.join(self.mem, "MEMORY.md"), "a") as f:
            f.write("- [host](host.md) — the short one\n")
        self.action("delete", ["host.md"])
        self.assertEqual(self.apply(1).returncode, 0)
        self.assertIn("(db_host.md)", self.index())
        self.assertIn("(db_host_v2.md)", self.index())
        self.assertNotIn("(host.md)", self.index())
        self.action("reindex", ["style.md"])
        self.assertEqual(self.apply(1).returncode, 0)
        self.assertIn("[style](style.md)", self.index())
        self.assertIn("feedback_style.md", self.index())

    def test_rewrite_keeps_the_position_of_the_index_line(self):
        self.action("rewrite", ["db_host.md"], MEMORY % ("db-primary", "Primary database host", "project", "body"))
        self.assertEqual(self.apply(1).returncode, 0)
        self.assertEqual(self.index().split("\n")[1], "- [db-primary](db_host.md) — Primary database host")

    def test_rewrite_keeps_a_hand_written_line_when_the_pointer_did_not_change(self):
        self.put("note.md", MEMORY % ("note", "A note about the release", "project", "old body"))
        with open(os.path.join(self.mem, "MEMORY.md"), "a") as f:
            f.write("- [note](note.md) — my own words\n")
        self.action("rewrite", ["note.md"], MEMORY % ("note", "A note about the release", "project", "new body"))
        self.assertEqual(self.apply(1).returncode, 0)
        self.assertIn("- [note](note.md) — my own words", self.index())

    def test_second_apply_is_a_no_op(self):
        for n in (5, 4):
            self.assertEqual(self.apply(n).returncode, 0)
            index = self.index()
            again = self.apply(n)
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertIn("nothing to do", again.stdout)
            self.assertEqual(self.index(), index)

    def test_dry_run_says_when_a_file_is_already_gone(self):
        self.action("delete", ["never_there.md"])
        r = self.apply(1, yes=False)
        self.assertEqual(r.returncode, 0)
        self.assertIn("already gone", r.stdout)
        self.assertNotIn("(deleted)", r.stdout)

    def test_delete_does_not_create_an_index(self):
        os.remove(os.path.join(self.mem, "MEMORY.md"))
        self.action("delete", ["orphan.md"])
        self.assertEqual(self.apply(1).returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(self.mem, "MEMORY.md")))

    def test_old_content_is_kept_in_a_backup(self):
        with open(os.path.join(self.mem, "db_host.md"), "rb") as f:
            original = f.read()
        r = self.apply(4)
        self.assertEqual(r.returncode, 0, r.stderr)
        backups = os.path.join(os.path.dirname(self.audit), "backup")
        stamps = os.listdir(backups)
        self.assertEqual(len(stamps), 1)
        with open(os.path.join(backups, stamps[0], "db_host.md"), "rb") as f:
            self.assertEqual(f.read(), original)
        self.assertTrue(os.path.exists(os.path.join(backups, stamps[0], "MEMORY.md")))
        self.assertIn(os.path.join(backups, stamps[0]), r.stdout)

    def test_non_utf8_file_does_not_crash(self):
        with open(os.path.join(self.mem, "orphan.md"), "wb") as f:
            f.write(b"\xff\xfe broken bytes")
        r = self.apply(5)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.mem, "orphan.md")))

    def test_applied_action_leaves_the_audit(self):
        self.assertEqual(self.apply(4).returncode, 0)
        with open(self.audit, encoding="utf-8") as f:
            audit = json.load(f)
        self.assertTrue(audit["next_actions"][3]["applied"])
        self.assertEqual(audit["conflicts"], [])
        self.assertEqual(audit["duplicates"], [])
        self.assertEqual(audit["stale"], [])
        self.assertNotIn("applied", audit["next_actions"][0])


if __name__ == "__main__":
    unittest.main()
