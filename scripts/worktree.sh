#!/usr/bin/env bash
# Git worktree helper for Rex, mirroring herdr's new/open/remove_worktree.
# Runs inside a Rex floating popup (see rex/init.lua) or from any shell.
#
# Usage:
#   worktree.sh new    [SRC_DIR] [BRANCH]   create/open a worktree tab in this session
#   worktree.sh open   [SRC_DIR]            pick an existing worktree, open its tab
#   worktree.sh remove [SRC_DIR]            pick and delete a worktree
#
# SRC_DIR is any directory inside the repository (defaults to $PWD).
# Worktrees live in $REX_WORKTREE_DIR/<repo>/<slug> (default ~/.rex/worktrees),
# the same layout herdr uses: the slug is the branch lowercased with every run
# of non-alphanumerics replaced by "-". New branches start from the HEAD of the
# checkout you ran this in, exactly like herdr.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/popup-lib.sh"

cmd="${1:-new}"
src="${2:-$PWD}"
branch_arg="${3:-}"

die() { printf 'worktree: %s\n' "$*" >&2; sleep 2; exit 1; }
[[ -d "$src" ]] || die "directory does not exist: $src"

# ── repo discovery ──────────────────────────────────────────────────────
main_root() {
  local common
  common=$(git -C "$src" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || die "worktree actions require a directory inside a Git work tree ($src)"
  dirname "$common"
}
root=$(main_root)
repo=$(basename "$root")
src_top=$(git -C "$src" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$root")
wt_root="${REX_WORKTREE_DIR:-$HOME/.rex/worktrees}/$repo"

# herdr's branch_to_path_slug: lowercase, non-alphanumeric runs -> "-", trimmed
branch_slug() {
  local slug
  slug=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  printf '%s' "${slug:-worktree}"
}
branch_dir() { printf '%s/%s' "$wt_root" "$(branch_slug "$1")"; }

# herdr's generated_branch_slug: worktree/<adjective>-<noun>-<hex4>
generated_branch() {
  local adjectives=(brave calm clear green lucky quiet rapid silver)
  local nouns=(river cloud field forest harbor meadow stone valley)
  local seed=$(( $(date +%s) * 32768 + RANDOM ))
  printf 'worktree/%s-%s-%04x' "${adjectives[seed % 8]}" "${nouns[(seed / 8) % 8]}" "$((seed & 0xffff))"
}

# path of the worktree already checked out for BRANCH, if any
worktree_for_branch() {
  worktree_rows | while IFS=$'\t' read -r path branch; do
    if [[ "$branch" == "$1" ]]; then printf '%s\n' "$path"; fi
  done
}

# Parse Git's NUL-delimited records without splitting paths on spaces or quotes.
worktree_rows() {
  local record path="" branch=""
  git -C "$root" worktree list --porcelain -z | while IFS= read -r -d '' record; do
    case "$record" in
      'worktree '*) path=${record#worktree } ;;
      'branch refs/heads/'*) branch=${record#branch refs/heads/} ;;
      detached) branch="(detached)" ;;
      '')
        if [[ -n "$path" ]]; then
          case "$path" in *$'\t'*|*$'\n'*) die "tabs and newlines in worktree paths are unsupported" ;; esac
          printf '%s\t%s\n' "$path" "$branch"
        fi
        path=""; branch="" ;;
    esac
  done
}

# "path<TAB>branch" lines for every worktree except the main checkout.
list_worktrees() {
  worktree_rows | while IFS=$'\t' read -r path branch; do
    if [[ "$path" != "$root" ]]; then printf '%s\t%s\n' "$path" "$branch"; fi
  done
}

# ── Rex session helpers ─────────────────────────────────────────────────
session_id_for_label() {
  rex ls --json | jq -r --arg l "$1" '.sessions[] | select(.label==$l) | .session_id' | head -1
}

# Ask the app to show SESSION. Needs Remote Control enabled in Rex settings.
switch_to() {
  if ! show_in_app "$1" "${3:-}"; then
    printf 'worktree ready: %s\n(enable Remote Control in Rex settings for auto-switch)\n' "$2"
    sleep 2
  fi
}

open_session() {   # open_session DIR LABEL
  local dir="$1" label="$2" sid wid
  if [[ -n "${REX_SESSION:-}" && "${REX_WORKTREE_TARGET:-tab}" != session ]]; then
    sid="$REX_SESSION"
    wid=$(rex window ls -s "$sid" --json | jq -r --arg l "$label" \
      '[.windows[] | select(.label==$l) | .window_id][0] // empty')
    if [[ -z "$wid" ]]; then
      wid=$(rex window new -s "$sid" "$label" --cwd "$dir" --json | jq -er .window_id)
    fi
    switch_to "$sid" "$label" "$wid"
    return
  fi
  # Outside Rex (or with an explicit opt-in), retain standalone sessions.
  sid=$(session_id_for_label "$label")
  if [[ -z "$sid" ]]; then
    sid=$(rex new "$label" --cwd "$dir" --json | jq -r .session_id)
  fi
  switch_to "$sid" "$label"
}

pick() {   # pick PROMPT  (stdin: "path<TAB>branch")
  fzf ${fzf_colors[@]+"${fzf_colors[@]}"} --prompt "$1" --height 100% --layout reverse --delimiter '\t' \
      --with-nth 2,1 --tabstop 4 || true
  paint >/dev/tty 2>/dev/null || true
}

# ── commands ────────────────────────────────────────────────────────────
cmd_new() {
  local branch="$branch_arg"
  if [[ -z "$branch" ]]; then
    local suggested
    suggested=$(generated_branch)
    branch=$(python3 "$(dirname "${BASH_SOURCE[0]}")/worktree-form.py" "$suggested" "$wt_root") || exit 0
    paint
  fi
  [[ -n "$branch" ]] || exit 0

  local dir
  dir=$(worktree_for_branch "$branch")
  if [[ -z "$dir" ]]; then
    dir=$(branch_dir "$branch")
    mkdir -p "$(dirname "$dir")"
    if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$root" worktree add "$dir" "$branch"
    else
      # new branch from the HEAD of the checkout this was started in (herdr behavior)
      git -C "$src_top" worktree add -b "$branch" "$dir" HEAD
    fi
  fi
  open_session "$dir" "$repo/$branch"
}

cmd_open() {
  local line
  line=$(list_worktrees | pick "open worktree ($repo) > ")
  [[ -n "$line" ]] || exit 0
  local dir branch
  dir=${line%%$'\t'*}; branch=${line#*$'\t'}
  open_session "$dir" "$repo/$branch"
}

cmd_remove() {
  local line
  line=$(list_worktrees | pick "remove worktree ($repo) > ")
  [[ -n "$line" ]] || exit 0
  local dir branch
  dir=${line%%$'\t'*}; branch=${line#*$'\t'}
  printf 'Delete checkout %s\n  (%s)? [y/N] ' "$dir" "$branch"
  local ans; read -r ans
  [[ "$ans" == [yY] ]] || exit 0
  local err
  if ! err=$(git -C "$root" worktree remove "$dir" 2>&1); then
    # herdr asks again before forcing a dirty checkout away
    printf '%s\n\nForce delete, discarding uncommitted changes? [y/N] ' "$err"
    read -r ans
    [[ "$ans" == [yY] ]] || exit 0
    git -C "$root" worktree remove --force "$dir"
  fi
  local sid
  sid=$(session_id_for_label "$repo/$branch")
  # Legacy standalone sessions can be closed, but never kill the session
  # containing this picker and the user's other tabs. Shared tabs stay open.
  if [[ -n "$sid" && "$sid" != "${REX_SESSION:-}" ]]; then rex kill "$sid" >/dev/null; fi
  printf 'removed %s (branch %s kept)\n' "$dir" "$branch"
  sleep 1
}

# Sourced for tests with WORKTREE_SH_LIB=1: define functions only.
[[ "${WORKTREE_SH_LIB:-}" == 1 ]] && return 0

case "$cmd" in
  new) cmd_new ;;
  open) cmd_open ;;
  remove) cmd_remove ;;
  *) die "unknown command: $cmd (new|open|remove)" ;;
esac
