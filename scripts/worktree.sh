#!/usr/bin/env bash
# Git side of rex-kit's worktree actions. It never prompts: the questions are
# asked in Rex's command palette by lua/worktree.lua, which calls these
# subcommands with rex.exec. Usable from any shell as well.
#
# Usage:
#   worktree.sh info     SRC_DIR            repo<TAB>main checkout<TAB>worktree base
#   worktree.sh list     SRC_DIR            path<TAB>branch, every worktree but the main one
#   worktree.sh branches SRC_DIR            local branches, most recent commit first
#   worktree.sh suggest                     a generated branch name
#   worktree.sh path     SRC_DIR BRANCH     where BRANCH is (or would be) checked out
#   worktree.sh new      SRC_DIR BRANCH     create the worktree if needed; print its path
#   worktree.sh remove   SRC_DIR PATH [--force]
#                                           delete a worktree; the branch is kept
#
# SRC_DIR is any directory inside the repository.
# Worktrees live in $REX_WORKTREE_DIR/<repo>/<slug> (default ~/.rex/worktrees),
# the same layout herdr uses: the slug is the branch lowercased with every run
# of non-alphanumerics replaced by "-". New branches start from the HEAD of the
# checkout SRC_DIR belongs to, exactly like herdr.
#
# Exit status 2 means bad input (not a repository, invalid branch name, the
# main checkout); stderr says why. `remove` exits 3 when Git refuses to delete
# a checkout with changes, so the caller can offer --force.
set -euo pipefail

die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

# ── repo discovery ──────────────────────────────────────────────────────
discover() {   # discover SRC_DIR: sets root, repo, src_top, wt_root
  local src="$1" common
  [[ -d "$src" ]] || die "directory does not exist: $src"
  common=$(git -C "$src" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || die "not inside a Git work tree: $src"
  root=$(dirname "$common")
  repo=$(basename "$root")
  src_top=$(git -C "$src" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$root")
  wt_root="${REX_WORKTREE_DIR:-$HOME/.rex/worktrees}/$repo"
}

# herdr's branch_to_path_slug: lowercase, non-alphanumeric runs -> "-", trimmed
branch_slug() {
  local slug
  slug=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  printf '%s' "${slug:-worktree}"
}
branch_dir() { printf '%s/%s' "$wt_root" "$(branch_slug "$1")"; }

valid_branch() {
  [[ -n "$1" && "$1" != -* ]] && git check-ref-format "refs/heads/$1" 2>/dev/null
}

# herdr's generated_branch_slug: worktree/<adjective>-<noun>-<hex4>
generated_branch() {
  local adjectives=(brave calm clear green lucky quiet rapid silver)
  local nouns=(river cloud field forest harbor meadow stone valley)
  local seed=$(( $(date +%s) * 32768 + RANDOM ))
  printf 'worktree/%s-%s-%04x\n' "${adjectives[seed % 8]}" "${nouns[(seed / 8) % 8]}" "$((seed & 0xffff))"
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

# path of the worktree already checked out for BRANCH, if any
worktree_for_branch() {
  worktree_rows | while IFS=$'\t' read -r path branch; do
    if [[ "$branch" == "$1" ]]; then printf '%s\n' "$path"; fi
  done
}

# "path<TAB>branch" lines for every worktree except the main checkout.
list_worktrees() {
  worktree_rows | while IFS=$'\t' read -r path branch; do
    if [[ "$path" != "$root" ]]; then printf '%s\t%s\n' "$path" "$branch"; fi
  done
}

# ── commands ────────────────────────────────────────────────────────────
cmd_info() { discover "$1"; printf '%s\t%s\t%s\n' "$repo" "$root" "$wt_root"; }
cmd_list() { discover "$1"; list_worktrees; }

cmd_branches() {
  discover "$1"
  git -C "$root" for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads
}

cmd_path() {
  discover "$1"
  local dir; dir=$(worktree_for_branch "$2")
  printf '%s\n' "${dir:-$(branch_dir "$2")}"
}

cmd_new() {
  discover "$1"
  local branch="$2" dir
  valid_branch "$branch" || die "not a valid branch name: $branch"
  dir=$(worktree_for_branch "$branch")
  if [[ -z "$dir" ]]; then
    dir=$(branch_dir "$branch")
    mkdir -p "$(dirname "$dir")"
    if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$root" worktree add -q "$dir" "$branch" >&2
    else
      # new branch from the HEAD of the checkout this was started in (herdr behavior)
      git -C "$src_top" worktree add -q -b "$branch" "$dir" HEAD >&2
    fi
  fi
  printf '%s\n' "$dir"
}

cmd_remove() {
  discover "$1"
  local dir="$2" force="${3:-}" known="" path
  [[ "$dir" != "$root" ]] || die "refusing to remove the main checkout: $dir"
  while IFS=$'\t' read -r path _; do
    if [[ "$path" == "$dir" ]]; then known=1; fi
  done < <(list_worktrees)
  [[ -n "$known" ]] || die "not a worktree of $repo: $dir"
  if [[ "$force" == --force ]]; then
    git -C "$root" worktree remove --force "$dir"
  else
    git -C "$root" worktree remove "$dir" || exit 3
  fi
}

# Sourced for tests with WORKTREE_SH_LIB=1: define functions only.
[[ "${WORKTREE_SH_LIB:-}" == 1 ]] && return 0

cmd="${1:-}"
case "$cmd" in
  info|list|branches) [[ $# -eq 2 ]] || die "usage: worktree.sh $cmd SRC_DIR"; "cmd_$cmd" "$2" ;;
  path|new) [[ $# -eq 3 ]] || die "usage: worktree.sh $cmd SRC_DIR BRANCH"; "cmd_$cmd" "$2" "$3" ;;
  remove) [[ $# -ge 3 ]] || die "usage: worktree.sh remove SRC_DIR PATH [--force]"; cmd_remove "$2" "$3" "${4:-}" ;;
  suggest) generated_branch ;;
  *) die "unknown command: ${cmd:-(none)} (info|list|branches|suggest|path|new|remove)" ;;
esac
