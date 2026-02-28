#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/window-tagging.sh"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tag>" >&2
  exit 2
fi

wt_require_backend

TAG="$1"
wt_debug "set start tag=$TAG"

if ! WINDOW_ID="$(wt_get_focused_window_id 2>&1)"; then
  wt_debug "set failed tag=$TAG error=$WINDOW_ID"
  printf '%s\n' "$WINDOW_ID" >&2
  exit 1
fi
wt_debug "set focused-window tag=$TAG window_id=$WINDOW_ID"

if [[ -z "$WINDOW_ID" ]]; then
  wt_debug "set no-focused-window tag=$TAG"
  wt_notify "no focused window"
  exit 1
fi

TAG_DIR="$(wt_tag_dir)"
mkdir -p "$TAG_DIR"

printf '%s\n' "$WINDOW_ID" > "$(wt_tag_file "$TAG")"
wt_debug "set wrote tag=$TAG file=$(wt_tag_file "$TAG")"
wt_notify "$(wt_session_name): set $TAG"
