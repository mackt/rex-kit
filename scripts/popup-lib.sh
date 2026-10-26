# Shared by the popup scripts (goto.sh, worktree.sh). Source it.
#
# In a Rex floating layer only cells with an explicit background are opaque.
# When init.lua opens a "layer" popup it passes REX_POPUP_BG / REX_POPUP_FG
# and REX_POPUP_MARGIN (the layer's terminal is larger than its visible area,
# see init.lua). fzf_colors makes fzf paint every cell and stay inside the
# visible part; paint does the same for anything we print ourselves.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

fzf_colors=()
paint() { :; }
if [[ -n "${REX_POPUP_BG:-}" ]]; then
  popup_fg="${REX_POPUP_FG:-#888888}"
  fzf_colors=(--color "bg:${REX_POPUP_BG},gutter:${REX_POPUP_BG},bg+:${popup_fg},fg+:${REX_POPUP_BG},fg:${popup_fg},border:${popup_fg}" --border)
  [[ -n "${REX_POPUP_MARGIN:-}" ]] && fzf_colors+=(--margin "$REX_POPUP_MARGIN")
  rgb() { printf '%d;%d;%d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
  paint() { printf '\e[48;2;%sm\e[38;2;%sm\e[H\e[2J' "$(rgb "$REX_POPUP_BG")" "$(rgb "$popup_fg")"; }
  paint
fi

# Rex session helpers --------------------------------------------------------
app_client_id() {
  if [[ -n "${REX_CLIENT:-}" ]]; then printf '%s\n' "$REX_CLIENT"; return; fi
  rex client ls --json | jq -er '[.clients[] | select(.info.kind=="app")] |
    if length == 1 then .[0].client_id else error("set REX_CLIENT when multiple Rex apps are connected") end'
}

# Ask the app to show SESSION (and WINDOW). Needs Remote Control enabled in
# Rex's settings; without it the server-side focus still applies.
show_in_app() {   # show_in_app SESSION_ID [WINDOW_ID]
  local app; app=$(app_client_id) || true
  [[ -n "$app" ]] || return 1
  local args=("session_id=$1"); [[ -n "${2:-}" ]] && args+=("window_id=$2")
  rex -C "$app" do session.select "${args[@]}" >/dev/null 2>&1
}
