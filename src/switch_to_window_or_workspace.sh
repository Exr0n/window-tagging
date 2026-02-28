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

if [[ -s "$TAG_FILE" ]]; then
  WINDOW_ID="$(< "$TAG_FILE")"
  if wt_list_window_ids | grep -qx "$WINDOW_ID"; then
    wt_focus_window_id "$WINDOW_ID"
    exit 0
  fi

  rm -f "$TAG_FILE"
  wt_notify "$(wt_session_name): window not found, cleared $TAG"
fi

wt_focus_workspace "$TAG"
