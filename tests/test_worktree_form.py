"""Exercise the real branch form in a terminal, without touching Rex."""
import errno
import fcntl
import importlib.util
import os
from pathlib import Path
import pty
import select
import signal
import struct
import sys
import termios
import time
import unittest

FORM = Path(__file__).resolve().parents[1] / "scripts/worktree-form.py"
spec = importlib.util.spec_from_file_location("worktree_form", FORM)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WorktreeFormTests(unittest.TestCase):
    def run_form(self, keys):
        env = dict(os.environ, TERM="xterm-256color")
        for key in ("REX_POPUP_BG", "REX_POPUP_FG", "REX_POPUP_MARGIN"):
            env.pop(key, None)
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
            script = 'value=$("$1" "$2" worktree/green-cloud-04cb /tmp/worktrees/repo); status=$?; printf "\\nFORM_RESULT:%s:%s\\n" "$status" "$value"'
            os.execve("/bin/bash", ["bash", "-c", script, "test", sys.executable, str(FORM)], env)
        output, sent, status = bytearray(), False, None
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if not select.select([fd], [], [], 0.1)[0]:
                    continue
                try:
                    data = os.read(fd, 65536)
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
                    break
                if not data:
                    break
                output.extend(data)
                if not sent and b"create and open" in output:
                    os.write(fd, keys)
                    sent = True
            else:
                self.fail("form timed out")
            _, status = os.waitpid(pid, 0)
            self.assertTrue(sent, output.decode(errors="replace"))
            self.assertEqual(os.waitstatus_to_exitcode(status), 0)
        finally:
            os.close(fd)
            if status is None:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
        return output.decode(errors="replace")

    def test_typing_replaces_suggestion_with_exact_name(self):
        self.assertIn("FORM_RESULT:0:fail", self.run_form(b"fail\r"))

    def test_enter_accepts_suggestion(self):
        self.assertIn("FORM_RESULT:0:worktree/green-cloud-04cb", self.run_form(b"\r"))

    def test_escape_cancels_without_a_branch(self):
        self.assertIn("FORM_RESULT:130:\r\n", self.run_form(b"\x1b"))

    def test_validation_and_checkout_preview(self):
        self.assertFalse(module.valid_branch("bad name"))
        self.assertFalse(module.valid_branch("-option"))
        self.assertFalse(module.valid_branch("@{-1}"))
        self.assertTrue(module.valid_branch("feature/fail"))
        self.assertEqual(module.checkout_path("/tmp/worktrees/repo", "Feature/Fail"),
                         "/tmp/worktrees/repo/feature-fail")
