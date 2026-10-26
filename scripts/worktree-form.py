#!/usr/bin/env python3
"""A branch-name form. stdout contains only the confirmed name."""
import curses
import os
from pathlib import Path
import re
import subprocess
import sys


def checkout_path(root, branch):
    lower = branch.translate(str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"))
    slug = re.sub("[^a-z0-9]+", "-", lower).strip("-") or "worktree"
    return str(Path(root) / slug)


def valid_branch(branch):
    return bool(branch and not branch.startswith("-") and subprocess.run(
        ["git", "check-ref-format", "refs/heads/" + branch],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0)


def form(screen, suggested, root):
    curses.curs_set(1)
    screen.keypad(True)
    if hasattr(curses, "set_escdelay"):
        curses.set_escdelay(25)
    field_style, button_style, border_style = curses.A_REVERSE, curses.A_REVERSE, curses.A_DIM
    if curses.has_colors():
        bg, fg, accent, field = 0, 7, 4, 0
        if curses.can_change_color() and curses.COLORS >= 20:
            colors = [os.environ.get("REX_POPUP_BG", "#181825"),
                      os.environ.get("REX_POPUP_FG", "#cdd6f4"), "#89b4fa", "#313244"]
            for index, color in enumerate(colors, 16):
                rgb = [round(int(color[i:i + 2], 16) * 1000 / 255) for i in (1, 3, 5)]
                curses.init_color(index, *rgb)
            bg, fg, accent, field = 16, 17, 18, 19
        curses.init_pair(1, fg, bg)
        curses.init_pair(2, fg, field)
        curses.init_pair(3, bg, accent)
        curses.init_pair(4, accent, bg)
        screen.bkgd(" ", curses.color_pair(1))
        field_style, button_style, border_style = map(curses.color_pair, (2, 3, 4))
    branch, cursor, error = suggested, len(suggested), ""
    selected = True  # Typing replaces the suggestion; arrows begin editing it.
    while True:
        screen.erase()
        rows, cols = screen.getmaxyx()
        # The existing Rex layer needs the same edge compensation as fzf.
        margin = os.environ.get("REX_POPUP_MARGIN", "").split(",")
        if len(margin) == 4:
            try:
                cols -= int(cols * float(margin[1].rstrip("%")) / 100)
                rows -= int(rows * float(margin[2].rstrip("%")) / 100)
            except ValueError:
                pass
        width = max(1, cols - 3)

        def put(y, x, text, style=0):
            if y >= rows or x >= cols:
                return
            try:
                screen.addnstr(y, x, text, max(0, cols - x - 1), style)
            except curses.error:
                pass

        if rows < 12 or cols < 32:
            put(0, 0, "Enlarge the panel; Esc cancels.")
        else:
            put(0, 0, "┌" + "─" * width + "┐", border_style)
            for y in range(1, rows - 1):
                put(y, 0, "│", border_style)
                put(y, cols - 2, "│", border_style)
            put(rows - 1, 0, "└" + "─" * width + "┘", border_style)
            put(2, 2, "new worktree", curses.A_BOLD)
            put(4, 3, "branch", curses.A_DIM)
            available = max(1, cols - 7)
            start = max(0, cursor - available + 1)
            field = branch[start:start + available].ljust(available)
            put(5, 3, field, field_style | (curses.A_BOLD if selected else 0))
            put(7, 3, "checkout", curses.A_DIM)
            path = checkout_path(root, branch)
            # Wrap long paths so the directory remains inspectable.
            for offset in range(0, len(path), available):
                y = 8 + offset // available
                if y >= rows - 4:
                    break
                put(y, 3, path[offset:offset + available])
            put(rows - 4, 3, error, curses.A_BOLD)
            put(rows - 2, 3, " ↵ create and open ", button_style | curses.A_BOLD)
            put(rows - 2, 25, " esc cancel ", field_style)
            try:
                screen.move(5, min(cols - 4, 3 + cursor - start))
            except curses.error:
                pass
        screen.refresh()
        key = screen.get_wch()
        if key in ("\x1b", "\x03"):
            return None
        if key in ("\n", "\r", curses.KEY_ENTER):
            if valid_branch(branch):
                return branch
            error = "Enter a valid Git branch name."
            continue
        error = ""
        if key in (curses.KEY_LEFT, curses.KEY_RIGHT, curses.KEY_HOME, curses.KEY_END,
                   "\x01", "\x05"):
            selected = False
            if key == curses.KEY_LEFT:
                cursor = max(0, cursor - 1)
            elif key == curses.KEY_RIGHT:
                cursor = min(len(branch), cursor + 1)
            elif key in (curses.KEY_HOME, "\x01"):
                cursor = 0
            else:
                cursor = len(branch)
        elif key in (curses.KEY_BACKSPACE, "\x7f", "\b", curses.KEY_DC, "\x15"):
            if selected or key == "\x15":
                branch, cursor = "", 0
            elif key == curses.KEY_DC:
                branch = branch[:cursor] + branch[cursor + 1:]
            elif cursor:
                branch = branch[:cursor - 1] + branch[cursor:]
                cursor -= 1
            selected = False
        elif isinstance(key, str) and key.isprintable():
            if selected:
                branch, cursor = "", 0
            branch = branch[:cursor] + key + branch[cursor:]
            cursor += len(key)
            selected = False


def main():
    saved_stdout = os.dup(1)
    try:
        # The shell captures the answer; curses must render to the terminal.
        with open("/dev/tty", "w") as tty:
            os.dup2(tty.fileno(), 1)
            value = curses.wrapper(form, sys.argv[1], sys.argv[2])
    finally:
        os.dup2(saved_stdout, 1)
        os.close(saved_stdout)
    if value is None:
        return 130
    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
