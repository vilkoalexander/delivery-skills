import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "..", "scripts")
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
        shutil.copy(os.path.join(self.tmp, "score.json"), os.path.join(self.tmp, "score.prev.json"))
        score2, _ = self.render()
        self.assertEqual(score2["prev"], 75)
        self.assertIn("Which host is live?", html)


class ApplyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mem = os.path.join(self.tmp, "memory")
        shutil.copytree(os.path.join(ROOT, CUR, "memory"), self.mem)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def apply(self, n, yes=True):
        args = ["--audit", AUDIT, "--memdir", self.mem, "--n", str(n)] + (["--yes"] if yes else [])
        return run("apply.py", *args)

    def index(self):
        with open(os.path.join(self.mem, "MEMORY.md")) as f:
            return f.read()

    def test_resolve_exits_2(self):
        r = self.apply(1)
        self.assertEqual(r.returncode, 2)
        self.assertIn("db.internal", r.stdout)

    def test_dry_run_writes_nothing(self):
        before = self.index()
        r = self.apply(2, yes=False)
        self.assertEqual(r.returncode, 0)
        self.assertIn("dry run", r.stdout)
        self.assertEqual(self.index(), before)

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
        self.apply(5)
        self.assertFalse(os.path.exists(os.path.join(self.mem, "orphan.md")))


if __name__ == "__main__":
    unittest.main()
