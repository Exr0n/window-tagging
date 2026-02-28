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
