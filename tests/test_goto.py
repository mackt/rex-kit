"""Run the actual navigator and fzf in a disposable pseudo-terminal."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
FZF = shutil.which("fzf")
MODERN_FZF = FZF and "--ghost" in subprocess.check_output([FZF, "--help"], text=True)


@unittest.skipUnless(MODERN_FZF, "requires fzf with --ghost support")
class NavigatorTests(unittest.TestCase):
    def pick(self, here):
        # Collector order: each session follows its children. Window and pane
        # deliberately share the current block ID; only the pane should win.
        rows = ("window\ts1\tw1\tb1\t\tFirst tab\tdetail\n"
                "pane\ts1\tw1\tb1\t\tFirst pane\tdetail\n"
                "session\ts1\tw1\t\t\tFirst session\tdetail\n"
                "window\ts2\tw2\tb2\t\tCurrent tab\tdetail\n"
                "pane\ts2\tw2\tb2\t\tCurrent pane\tdetail\n"
                "session\ts2\tw2\t\t\tCurrent session\tdetail\n")
        with tempfile.TemporaryDirectory(prefix="rex-goto-test-") as tmp:
            fixture = Path(tmp) / "rows"
            fixture.write_text(rows)
            env = dict(os.environ, TERM="xterm-256color", GOTO_TEST="1",
                       FIXTURE=str(fixture), FZF_BIN=FZF, FZF_DEFAULT_OPTS="")
            for key in ("FZF_DEFAULT_OPTS_FILE", "REX_POPUP_BG", "REX_POPUP_MARGIN"):
                env.pop(key, None)
            # Mock the collector, not the picker. Accept only after the real
            # fzf has loaded its list and run the production load handler.
            wrapper = '''rex() { cat "$FIXTURE"; }
fzf() { "$FZF_BIN" "$@" --bind 'load:+accept'; }
export -f rex fzf
exec bash "$1" "$2"
'''
            pid, fd = pty.fork()
            if pid == 0:
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
                os.execve("/bin/bash", ["bash", "-c", wrapper, "test",
                                       str(ROOT / "scripts/goto.sh"), here], env)
            output = bytearray()
            status = None
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if select.select([fd], [], [], 0.1)[0]:
                        try:
                            data = os.read(fd, 65536)
                        except OSError as exc:
                            if exc.errno != errno.EIO:
                                raise
                            break
                        if not data:
                            break
                        output.extend(data)
                else:
                    self.fail("navigator timed out: " + output.decode(errors="replace"))
                _, status = os.waitpid(pid, 0)
                self.assertEqual(os.waitstatus_to_exitcode(status), 0,
                                 output.decode(errors="replace"))
            finally:
                os.close(fd)
                if status is None:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
            return output.decode(errors="replace")

    def test_initial_selection_is_current_pane(self):
        self.assertIn("PICKED:pane Current pane", self.pick("b2"))

    def test_missing_current_pane_falls_back_to_first_row(self):
        self.assertIn("PICKED:session First session", self.pick("missing"))

    def test_empty_context_falls_back_to_first_row(self):
        self.assertIn("PICKED:session First session", self.pick(""))
