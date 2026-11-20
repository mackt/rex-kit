"""Run lua/navigator.lua's pure parts (items, pane_state) with a plain Lua."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")

# Prints items(sessions, here, only) as JSON lines: id, title, detail.
HARNESS = r'''
local nav = assert(loadfile(arg[1]))(nil, {})
local function quote(s) return s and ('"' .. s:gsub('[\\"]', '\\%0') .. '"') or "null" end
local spec = arg[2]
local sessions = assert(loadstring("return " .. spec))()
for _, it in ipairs(nav.items(sessions, arg[3] ~= "" and arg[3] or nil, arg[4] ~= "" and arg[4] or nil)) do
  print("[" .. quote(it.id) .. "," .. quote(it.title) .. "," .. quote(it.detail) .. "]")
end
'''

SESSIONS = '''{
  { session_id = "s1", label = "work", active_window_id = "w1", windows = {
    { window_id = "w1", label = "Window 1a2b", panes = {
      { block_id = "b1", label = "shell", name = "zsh", cwd = "/tmp" },
      { block_id = "b2", label = "shell", name = "node", state = { state = "blocked", app = "claude" } },
    } },
    { window_id = "w2", label = "repo/feature", panes = {
      { block_id = "b3", label = "build", name = "make", state = { state = "working" } },
    } },
  } },
  { session_id = "s2", label = "notes", active_window_id = "w3", windows = {
    { window_id = "w3", panes = { { block_id = "b4", name = "vim" } } },
  } },
}'''


@unittest.skipUnless(LUA, "requires a Lua 5.1 interpreter (luajit or lua5.1)")
class NavigatorTests(unittest.TestCase):
    def items(self, here="", only=""):
        args = [str(ROOT / "lua/navigator.lua"), SESSIONS, here, only]
        script = "arg = {" + ",".join("[[" + a + "]]" for a in args) + "}\n" + HARNESS
        out = subprocess.check_output([LUA, "-"], input=script, text=True)
        return [json.loads(line) for line in out.splitlines()]

    def test_tree_order_and_titles(self):
        items = self.items()
        self.assertEqual([i[0].split("|")[0] for i in items],
                         ["session", "window", "pane", "pane", "window", "pane", "session", "window", "pane"])
        titles = [i[1] for i in items]
        self.assertEqual(titles[:6], ["work", "tab 1", "zsh", "claude", "repo/feature", "build · make"])
        self.assertEqual(titles[7], "tab 1")

    def test_state_summaries(self):
        items = {i[0]: i for i in self.items()}
        self.assertEqual(items["session|s1|w1|"][2], "● 1  ◐ 1")
        self.assertEqual(items["pane|s1|w1|b2"][2], "● blocked")
        self.assertIsNone(items["pane|s1|w1|b1"][2])

    def test_current_pane_marked(self):
        items = {i[0]: i for i in self.items(here="b1")}
        self.assertEqual(items["pane|s1|w1|b1"][2], "◆ here")
        items = {i[0]: i for i in self.items(here="b2")}
        self.assertEqual(items["pane|s1|w1|b2"][2], "● blocked  ◆")

    def test_state_filter_lists_matching_panes_only(self):
        self.assertEqual([i[0] for i in self.items(only="working")], ["pane|s1|w2|b3"])
        self.assertEqual(self.items(only="idle"), [])
        self.assertEqual(len(self.items(only="all")), 9)

    def test_unread_when_done_after_last_seen(self):
        script = (f"local nav = assert(loadfile([[{ROOT / 'lua/navigator.lua'}]]))(nil, {{}})\n"
                  "local r = { { state = 'done', updated_at = '2026-10-28T14:55:55.12+08:00' } }\n"
                  "local t = nav.epoch(r[1].updated_at)\n"
                  "print(t, nav.pane_state(r, t - 1, false).state, nav.pane_state(r, t + 1, false).state,"
                  " nav.pane_state(r, t - 1, true).state)\n")
        out = subprocess.check_output([LUA, "-"], input=script, text=True).split()
        self.assertEqual(out, ["1793170555", "unread", "done", "done"])


if __name__ == "__main__":
    unittest.main()
