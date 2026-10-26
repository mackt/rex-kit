"""Exercise the real shell functions against disposable Git repositories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WorktreeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="rex-kit-test-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.repo = self.base / "repo with 'quotes' 中文"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "--allow-empty", "-qm", "fixture")
        self.worktree = self.base / "feature with 'quotes' 中文"
        self.git("worktree", "add", "-qb", "feature/test", str(self.worktree))

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True).strip()

    def shell(self, body, stdin="", src=None):
        env = dict(os.environ, WORKTREE_SH_LIB="1", REX_WORKTREE_DIR=str(self.base / "worktrees"),
                   TEST_WORKTREE=str(self.worktree))
        # Only session integration is stubbed. Git operations use the real binary.
        prelude = '''source "$1" open "$2"
open_session() { printf 'SESSION:%s\\n' "$1"; }
session_id_for_label() { :; }
sleep() { :; }
'''
        return subprocess.run(["bash", "-c", prelude + body, "test",
                               str(ROOT / "scripts/worktree.sh"), str(src or self.repo)],
                              env=env, input=stdin, text=True, capture_output=True, check=True).stdout

    def test_paths_and_main_checkout_exclusion(self):
        self.assertEqual(self.shell("worktree_for_branch feature/test").strip(), str(self.worktree))
        expected = f"{self.worktree}\tfeature/test\n"
        self.assertEqual(self.shell("list_worktrees"), expected)
        self.assertEqual(self.shell("list_worktrees", src=self.worktree), expected)

    def test_open_existing_branch_reuses_worktree(self):
        result = self.shell('branch_arg=feature/test; cmd_new')
        self.assertEqual(result.strip(), "SESSION:" + str(self.worktree))

    def test_new_branch_starts_at_source_checkout_head(self):
        subprocess.check_call(["git", "-C", str(self.worktree), "-c", "user.name=Fixture",
                               "-c", "user.email=fixture@example.invalid", "commit",
                               "--allow-empty", "-qm", "branch commit"])
        expected = self.git("rev-parse", "feature/test")
        self.shell('branch_arg=feature/new; cmd_new', src=self.worktree)
        self.assertEqual(self.git("rev-parse", "feature/new"), expected)

    def test_typed_name_wins_over_fuzzy_branch_match(self):
        self.git("branch", "feature/failure")
        self.shell('''python3() { printf 'fail\\n'; }
branch_arg=; cmd_new''')
        self.assertEqual(self.git("rev-parse", "fail"), self.git("rev-parse", "HEAD"))
        self.assertIn("refs/heads/fail\n", self.git("worktree", "list", "--porcelain") + "\n")

    def test_current_session_opens_tab(self):
        # Exercise the actual opener; replace only the Rex transport and UI.
        env = dict(os.environ, WORKTREE_SH_LIB="1", REX_SESSION="session:current")
        script = '''source "$1" open "$2"
rex() {
  if [[ "$1 $2" == "window ls" ]]; then printf '{"windows":[]}';
  elif [[ "$1 $2" == "window new" ]]; then printf '{"window_id":"window:new"}';
  elif [[ "$1" == ls ]]; then printf '{"sessions":[]}';
  elif [[ "$1" == new ]]; then printf '{"session_id":"session:wrong"}';
  fi
}
show_in_app() { printf 'SHOW:%s:%s\\n' "$1" "${2:-}"; }
open_session "$2" "repo/feature"
'''
        result = subprocess.check_output(["bash", "-c", script, "test",
                                          str(ROOT / "scripts/worktree.sh"), str(self.repo)],
                                         env=env, text=True)
        self.assertIn("SHOW:session:current:window:new", result)

    def test_declining_delete_keeps_worktree(self):
        self.shell('pick() { cat >/dev/null; printf "%s\\tfeature/test\\n" "$TEST_WORKTREE"; }; cmd_remove', "n\n")
        self.assertTrue(self.worktree.is_dir())

    def test_confirmed_clean_delete_keeps_branch(self):
        self.shell('pick() { cat >/dev/null; printf "%s\\tfeature/test\\n" "$TEST_WORKTREE"; }; cmd_remove', "y\n")
        self.assertFalse(self.worktree.exists())
        self.git("show-ref", "--verify", "refs/heads/feature/test")

    def test_remove_never_closes_current_shared_session(self):
        result = self.shell('''REX_SESSION=session:keep
session_id_for_label() { printf '%s\\n' "$REX_SESSION"; }
rex() { printf 'UNEXPECTED_CLOSE'; return 1; }
pick() { cat >/dev/null; printf "%s\\tfeature/test\\n" "$TEST_WORKTREE"; }
cmd_remove''', "y\n")
        self.assertNotIn("UNEXPECTED_CLOSE", result)
        self.assertFalse(self.worktree.exists())

    def test_declining_force_preserves_changes(self):
        dirty = self.worktree / "uncommitted.txt"
        dirty.write_text("keep me")
        self.shell('pick() { cat >/dev/null; printf "%s\\tfeature/test\\n" "$TEST_WORKTREE"; }; cmd_remove', "y\nn\n")
        self.assertEqual(dirty.read_text(), "keep me")


class ScriptTests(unittest.TestCase):
    def test_shell_syntax(self):
        for script in (ROOT / "scripts").glob("*.sh"):
            subprocess.check_call(["bash", "-n", str(script)])

    def test_state_filter_keeps_matching_context(self):
        rows = ("session\ts\tw\t\tworking,idle\tSession\n"
                "window\ts\tw\tb\tworking,idle\tWindow\n"
                "pane\ts\tw\tb\tworking\tWorking\n"
                "pane\ts\tw\tc\tidle\tIdle\n")
        with tempfile.NamedTemporaryFile(mode="w", suffix=" rows.tsv") as f:
            f.write(rows)
            f.flush()
            result = subprocess.check_output(["bash", str(ROOT / "scripts/goto.sh"),
                                               "--filter", "working", f.name], text=True)
        self.assertIn("Session", result)
        self.assertIn("Window", result)
        self.assertIn("Working", result)
        self.assertNotIn("Idle", result)


if __name__ == "__main__":
    unittest.main()
