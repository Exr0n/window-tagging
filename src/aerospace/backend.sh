#!/usr/bin/env bash
set -euo pipefail

WT_BACKEND_NAME="aerospace"

wt_get_focused_window_id() {
  aerospace list-windows --focused --format '%{window-id}'
}

wt_focus_window_id() {
  aerospace focus --window-id "$1"
}

wt_list_window_ids() {
  aerospace list-windows --all --format '%{window-id}'
}

wt_focus_workspace() {
  aerospace workspace "$1"
}

wt_list_windows_with_app_and_workspace() {
  aerospace list-windows --all --format '%{window-id}%{tab}%{app-name}%{tab}%{workspace}'
}

wt_move_window_to_workspace() {
  aerospace move-node-to-workspace --window-id "$1" "$2"
}

wt_get_focused_workspace() {
  aerospace list-workspaces --focused --format '%{workspace}'
}
