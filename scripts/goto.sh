#!/usr/bin/env bash
# Session navigator for Rex, modelled on herdr's (prefix+g): every session,
# tab and pane on this server as a tree; Enter jumps there. Two modes, as in
# herdr. Runs in the popup init.lua's goto action opens.
#
#   goto.sh [HERE_BLOCK_ID]      HERE_BLOCK_ID marks the pane you came from
#
#   list mode (initial)   j/k ↑↓ move   enter switch   / search
#                         b/u/w/i/d blocked/unread/working/idle/done   a all
#                         ctrl-d/ctrl-u half page   G/end last   home first
#                         esc close
#   search mode           type to filter   ↑↓ ctrl-n/p move   enter switch
#                         ctrl-u clear   esc back to list mode
set -euo pipefail
here_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here_dir/popup-lib.sh"

# --filter STATE FILE: the rows of FILE whose pane is in STATE, with their
# session and tab rows kept as (dimmed) context, as herdr's state filter shows.
if [[ "${1:-}" == "--filter" ]]; then
  state="$2"; file="$3"
  if [[ "$state" == all ]]; then cat "$file"; exit 0; fi
  awk -F'\t' -v OFS='\t' -v want="$state" '
    function matches(states,  n, i, a) { n = split(states, a, ","); for (i = 1; i <= n; i++) if (a[i] == want) return 1; return 0 }
    { if ($1 == "pane") { if ($5 == want) print; }
      else if (matches($5)) { $6 = "\033[2m" $6; print } }' "$file"
  exit 0
fi

here="${1:-}"
seen_file="${REX_KIT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rex-kit}/seen.tsv"
rows_file=$(mktemp "${TMPDIR:-/tmp}/rex-goto.XXXXXX")
trap 'rm -f "$rows_file"' EXIT

# Rows come out with each session's row last; put it first again (the
# collector numbers nothing, so order by: session rows before their children).
rex do "$here_dir/goto-rows.lua" here="$here" seen="$seen_file" \
  | awk -F'\t' '{ buf[NR] = $0; kind[NR] = $1 }
      END { start = 1
            for (i = 1; i <= NR; i++) if (kind[i] == "session") { print buf[i]; for (j = start; j < i; j++) print buf[j]; start = i + 1 } }' \
  > "$rows_file" || { printf "goto: failed to collect sessions\n" >&2; exit 1; }
[[ -s "$rows_file" ]] || { printf 'goto: no sessions\n'; sleep 1; exit 1; }

# The current pane is marked in the tree; also put the cursor on that row.
# Match pane rows only: the parent window can carry the same block ID.
initial_row=$(awk -F'\t' -v here="$here" '
  $1 == "pane" && here != "" && $4 == here { print NR; found = 1; exit }
  END { if (!found) print 1 }' "$rows_file")

jump() {   # jump "kind<TAB>sid<TAB>wid<TAB>bid<TAB>..."
  local kind sid wid bid
  IFS=$'\t' read -r kind sid wid bid _ <<<"$1"
  if [[ "${GOTO_TEST:-}" == 1 ]]; then printf 'PICKED:%s %s\n' "$kind" "$(cut -f6 <<<"$1" | sed 's/\x1b\[[0-9;]*m//g')"; return 0; fi
  case "$kind" in
    pane)    rex api call -s "$sid" session.focus_block "{\"block_id\":\"$bid\"}" >/dev/null ;;
    window)  rex api call -s "$sid" session.focus_window "{\"window_id\":\"$wid\"}" >/dev/null ;;
  esac
  show_in_app "$sid" "$wid" || true
}
[[ "${GOTO_SH_LIB:-}" == 1 ]] && return 0

export REX_KIT_GOTO_SELF="$here_dir/goto.sh"
export REX_KIT_GOTO_ROWS="$rows_file"
list_footer=' enter switch   / search   b/u/w/i/d/a states   j/k/↑↓ move   esc close'
search_footer=' enter switch   ↑↓ move   ctrl-u clear   esc back'
list_prompt='  '
ghost='search panes'   # placeholder in the empty search box, as herdr shows
# Keys that mean something only in list mode; search mode types them.
list_keys='j,k,b,u,w,i,d,a,G,/'
# Back from search keeps the query and its matches (as herdr does); only the
# key meanings change. Search stays enabled: disabling it would leave the
# list filtered by a query nobody can edit.
to_list="rebind($list_keys)+change-footer($list_footer)"
to_search="enable-search+change-prompt(/ )+change-ghost($ghost)+unbind($list_keys)+change-footer($search_footer)"
# Entering search drops an active state filter (herdr does the same); only
# then is the list reloaded, so a quick "/word" never races a reload.
enter_search="[[ \$FZF_PROMPT == '$list_prompt' || \$FZF_PROMPT == '/ ' ]] && echo '$to_search' || echo 'reload(\"\$REX_KIT_GOTO_SELF\" --filter all \"\$REX_KIT_GOTO_ROWS\")+$to_search'"
filter() {
  local g; [[ "$1" == all ]] && g="$ghost" || g=""
  printf 'clear-query+reload("$REX_KIT_GOTO_SELF" --filter %s "$REX_KIT_GOTO_ROWS")+change-prompt(%s)+change-ghost(%s)+first' "$1" "$2" "$g"
}

# --exact: substring matching, so a query finds the first row in tree order
# that contains it, rather than the first row a fuzzy match happens to hit.
pick=$(fzf ${fzf_colors[@]+"${fzf_colors[@]}"} --ansi --disabled --exact --delimiter '\t' --with-nth 6 \
  --layout reverse --height 100% --no-sort --tabstop 2 --info inline-right \
  --prompt "$list_prompt" --ghost "$ghost" --footer "$list_footer" \
  --bind "load:pos($initial_row)+unbind(load)" \
  --preview 'printf "%s" {7}' --preview-window 'down,1,border-top,wrap' \
  --bind 'j:down,k:up,G:last,home:first,end:last,ctrl-d:half-page-down' \
  --bind "/:transform:$enter_search" \
  --bind "b:$(filter blocked '● blocked  ')" --bind "u:$(filter unread '◉ unread  ')" --bind "w:$(filter working '◐ working  ')" \
  --bind "i:$(filter idle '○ idle  ')" --bind "d:$(filter done '✔ done  ')" \
  --bind "a:$(filter all "$list_prompt")" \
  --bind "esc:transform:[[ \$FZF_PROMPT == '/ ' ]] && echo 'change-prompt($list_prompt)+$to_list' || echo abort" \
  --bind "ctrl-u:transform:[[ \$FZF_PROMPT == '/ ' ]] && echo clear-query || echo half-page-up" \
  --bind "backspace:transform:[[ \$FZF_PROMPT == '/ ' ]] && echo backward-delete-char || echo '$(filter all "$list_prompt")'" \
  < "$rows_file") || exit 0
[[ -n "$pick" ]] && jump "$pick"
