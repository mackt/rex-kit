"""Exercise scripts/worktree.sh against disposable Git repositories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/worktree.sh"


class WorktreeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="rex-kit-test-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.repo = self.base / "repo with 'quotes' 中文"
        self.repo.mkdir()
        self.git("init", "-q")
        self.commit(self.repo, "fixture")
        self.worktree = self.base / "feature with 'quotes' 中文"
        self.git("worktree", "add", "-qb", "feature/test", str(self.worktree))

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True).strip()

    def commit(self, where, message):
        subprocess.check_call(["git", "-C", str(where), "-c", "user.name=Fixture",
                               "-c", "user.email=fixture@example.invalid", "commit",
                               "--allow-empty", "-qm", message])

    def run_wt(self, *args, check=True):
        env = dict(os.environ, REX_WORKTREE_DIR=str(self.base / "worktrees"))
        return subprocess.run([str(SCRIPT), *map(str, args)], env=env, text=True,
                              capture_output=True, check=check)

    def test_info(self):
        out = self.run_wt("info", self.worktree).stdout
        self.assertEqual(out, f"{self.repo.name}\t{self.repo}\t{self.base / 'worktrees' / self.repo.name}\n")

    def test_list_excludes_main_checkout(self):
        expected = f"{self.worktree}\tfeature/test\n"
        self.assertEqual(self.run_wt("list", self.repo).stdout, expected)
        self.assertEqual(self.run_wt("list", self.worktree).stdout, expected)

    def test_branches_most_recent_first(self):
        self.commit(self.worktree, "newer")
        self.assertEqual(self.run_wt("branches", self.repo).stdout.split()[0], "feature/test")

    def test_path(self):
        self.assertEqual(self.run_wt("path", self.repo, "feature/test").stdout.strip(), str(self.worktree))
        self.assertEqual(self.run_wt("path", self.repo, "Fix/Some Thing").stdout.strip(),
                         str(self.base / "worktrees" / self.repo.name / "fix-some-thing"))

    def test_suggest_is_a_valid_branch(self):
        name = self.run_wt("suggest").stdout.strip()
        self.assertRegex(name, r"^worktree/[a-z]+-[a-z]+-[0-9a-f]{4}$")
        subprocess.check_call(["git", "check-ref-format", "--branch", name], stdout=subprocess.DEVNULL)

    def test_new_reuses_existing_worktree(self):
        self.assertEqual(self.run_wt("new", self.repo, "feature/test").stdout.strip(), str(self.worktree))

    def test_new_branch_starts_at_source_checkout_head(self):
        self.commit(self.worktree, "branch commit")
        out = self.run_wt("new", self.worktree, "feature/new").stdout.strip()
        self.assertEqual(out, str(self.base / "worktrees" / self.repo.name / "feature-new"))
        self.assertEqual(self.git("rev-parse", "feature/new"), self.git("rev-parse", "feature/test"))

    def test_new_checks_out_existing_branch(self):
        self.git("branch", "existing")
        out = self.run_wt("new", self.repo, "existing").stdout.strip()
        self.assertEqual(subprocess.check_output(["git", "-C", out, "branch", "--show-current"],
                                                 text=True).strip(), "existing")

    def test_new_rejects_invalid_names(self):
        for bad in ("-x", "a..b", "with space", ""):
            result = self.run_wt("new", self.repo, bad, check=False)
            self.assertEqual(result.returncode, 2, bad)
            self.assertIn("not a valid branch name", result.stderr)

    def test_not_a_repository(self):
        result = self.run_wt("info", self.base, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("not inside a Git work tree", result.stderr)

    def test_remove_keeps_branch(self):
        self.run_wt("remove", self.repo, self.worktree)
        self.assertFalse(self.worktree.exists())
        self.git("show-ref", "--verify", "refs/heads/feature/test")

    def test_remove_dirty_needs_force(self):
        dirty = self.worktree / "uncommitted.txt"
        dirty.write_text("keep me")
        result = self.run_wt("remove", self.repo, self.worktree, check=False)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(dirty.read_text(), "keep me")
        self.run_wt("remove", self.repo, self.worktree, "--force")
        self.assertFalse(self.worktree.exists())

    def test_remove_refuses_main_checkout_and_strangers(self):
        for target in (self.repo, self.base / "elsewhere"):
            result = self.run_wt("remove", self.repo, target, check=False)
            self.assertEqual(result.returncode, 2, target)
        self.assertTrue(self.repo.is_dir())


class ScriptTests(unittest.TestCase):
    def test_shell_syntax(self):
        for script in (ROOT / "scripts").glob("*.sh"):
            subprocess.check_call(["bash", "-n", str(script)])


if __name__ == "__main__":
    unittest.main()
