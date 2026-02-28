#!/usr/bin/env bash
set -euo pipefail

wt_data_dir() {
  echo "${WINDOW_TAGGING_DATA_DIR:-$HOME/.caches/window-tagging}"
}

wt_session_name() {
  if [[ -n "${WINDOW_TAGGING_SESSION:-}" ]]; then
    echo "$WINDOW_TAGGING_SESSION"
    return 0
  fi

  local session_file="${WINDOW_TAGGING_SESSION_FILE:-$(wt_data_dir)/session_name}"
  if [[ -f "$session_file" ]]; then
    tr -d '\n' < "$session_file"
  else
    echo "default"
  fi
}

wt_tag_dir() {
  echo "$(wt_data_dir)/sessions/$(wt_session_name)"
}

wt_tag_file() {
  echo "$(wt_tag_dir)/window_id_$1"
}

wt_debug_log_file() {
  echo "$(wt_data_dir)/debug.log"
}

wt_debug() {
  local msg="$1"
  mkdir -p "$(wt_data_dir)"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >> "$(wt_debug_log_file)"
}

wt_notify() {
  if [[ "${WINDOW_TAGGING_NOTIFICATIONS:-1}" != "1" ]]; then
    return 0
  fi
  if command -v osascript >/dev/null 2>&1; then
    local message="${1//$'\n'/ }"
    message="${message//\"/\'}"
    osascript -e "display notification \"$message\" with title \"window tagging\""
  fi
}

wt_require_backend() {
  if [[ -z "${WINDOW_TAGGING_BACKEND:-}" ]]; then
    echo "WINDOW_TAGGING_BACKEND is not set" >&2
    return 1
  fi
  if [[ ! -f "$WINDOW_TAGGING_BACKEND" ]]; then
    echo "WINDOW_TAGGING_BACKEND not found: $WINDOW_TAGGING_BACKEND" >&2
    return 1
  fi

  # shellcheck disable=SC1090
  source "$WINDOW_TAGGING_BACKEND"
  wt_debug "loaded backend path=$WINDOW_TAGGING_BACKEND name=${WT_BACKEND_NAME:-unset}"

  : "${WT_BACKEND_NAME:?WT_BACKEND_NAME must be set in backend}"
  command -v wt_get_focused_window_id >/dev/null 2>&1 || { echo "backend missing wt_get_focused_window_id" >&2; return 1; }
  command -v wt_focus_window_id >/dev/null 2>&1 || { echo "backend missing wt_focus_window_id" >&2; return 1; }
  command -v wt_list_window_ids >/dev/null 2>&1 || { echo "backend missing wt_list_window_ids" >&2; return 1; }
  command -v wt_focus_workspace >/dev/null 2>&1 || { echo "backend missing wt_focus_workspace" >&2; return 1; }
}
