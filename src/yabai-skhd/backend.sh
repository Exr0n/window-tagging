#!/usr/bin/env bash
set -euo pipefail

WT_BACKEND_NAME="yabai"

wt_get_focused_window_id() {
  yabai -m query --windows --window | jq -r '.id'
}

wt_focus_window_id() {
  yabai -m window --focus "$1"
}

wt_list_window_ids() {
  yabai -m query --windows | jq -r '.[].id'
}

wt_focus_workspace() {
  yabai -m space --focus "$1"
}
