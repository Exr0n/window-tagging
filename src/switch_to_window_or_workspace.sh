#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/window-tagging.sh"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tag-or-workspace>" >&2
  exit 2
fi

wt_require_backend

TAG="$1"
TAG_FILE="$(wt_tag_file "$TAG")"
wt_debug "switch start tag=$TAG tag_file=$TAG_FILE"

if [[ -s "$TAG_FILE" ]]; then
  WINDOW_ID="$(< "$TAG_FILE")"
  wt_debug "switch found tag tag=$TAG window_id=$WINDOW_ID"

  wt_debug "switch focusing-window tag=$TAG window_id=$WINDOW_ID"
  if FOCUS_OUT="$(wt_focus_window_id "$WINDOW_ID" 2>&1)"; then
    wt_debug "switch focus-succeeded tag=$TAG window_id=$WINDOW_ID"
    exit 0
  fi

  wt_debug "switch focus-failed tag=$TAG window_id=$WINDOW_ID error=$FOCUS_OUT"

  if ! WINDOW_IDS="$(wt_list_window_ids 2>&1)"; then
    wt_debug "switch list-windows-failed tag=$TAG error=$WINDOW_IDS"
    printf '%s\n' "$FOCUS_OUT" >&2
    printf '%s\n' "$WINDOW_IDS" >&2
    exit 1
  fi

  if printf '%s\n' "$WINDOW_IDS" | grep -qx "$WINDOW_ID"; then
    wt_debug "switch focus-failed-but-window-still-listed tag=$TAG window_id=$WINDOW_ID"
  else
    wt_debug "switch stale-tag tag=$TAG window_id=$WINDOW_ID windows=$(printf '%s' "$WINDOW_IDS" | tr '\n' ',' | sed 's/,$//')"
    rm -f "$TAG_FILE"
    wt_notify "$(wt_session_name): window not found, cleared $TAG"
  fi
fi

wt_debug "switch fallback-workspace tag=$TAG"
wt_focus_workspace "$TAG"
