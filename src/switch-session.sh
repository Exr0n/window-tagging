#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/window-tagging.sh"

if [[ -z "${1:-}" ]]; then
    echo "usage: $0 <session-name>" >&2
    exit 2
fi

if [[ -z "${WINDOW_TAGGING_BACKEND:-}" ]]; then
    if command -v yabai >/dev/null 2>&1 && [[ -f "$SCRIPT_DIR/yabai-skhd/backend.sh" ]]; then
        WINDOW_TAGGING_BACKEND="$SCRIPT_DIR/yabai-skhd/backend.sh"
    elif command -v aerospace >/dev/null 2>&1 && [[ -f "$SCRIPT_DIR/aerospace/backend.sh" ]]; then
        WINDOW_TAGGING_BACKEND="$SCRIPT_DIR/aerospace/backend.sh"
    fi
fi

wt_require_backend

BASE_DIR="${WINDOW_TAGGING_DATA_DIR:-$HOME/.caches/window-tagging}"
SESSION_FILE="${WINDOW_TAGGING_SESSION_FILE:-$BASE_DIR/session_name}"
EXCLUDED_APPS_REGEX="${WINDOW_TAGGING_EXCLUDED_APPS_REGEX:-^(Arc|ChatGPT|Toggl Track|Notes|Discord|Mail|Messages|Fantastical)$}"

mkdir -p "$BASE_DIR"
if [[ -f "$SESSION_FILE" ]]; then
    CURRENT_SESSION="$(< "$SESSION_FILE")"
else
    CURRENT_SESSION="default"
    echo "$CURRENT_SESSION" > "$SESSION_FILE"
fi

CURRENT_SESSION_DIR="$BASE_DIR/sessions/$CURRENT_SESSION"
TARGET_SESSION_DIR="$BASE_DIR/sessions/$1"

mkdir -p "$CURRENT_SESSION_DIR" "$TARGET_SESSION_DIR"

find_window_files() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f -name 'window_id_*' 2>/dev/null
}

collect_ids() {
    local files=("$@")
    if ((${#files[@]})); then
        cat "${files[@]}" 2>/dev/null
    fi
}

MINIMIZE_SUPPORTED=0
if wt_has_fn wt_list_windows_with_app && wt_has_fn wt_minimize_window && wt_has_fn wt_deminimize_window; then
    MINIMIZE_SUPPORTED=1
fi

PSEUDO_MINIMIZE_SUPPORTED=0
if wt_has_fn wt_list_windows_with_app_and_workspace && wt_has_fn wt_move_window_to_workspace && wt_has_fn wt_get_focused_workspace; then
    PSEUDO_MINIMIZE_SUPPORTED=1
fi

if (( MINIMIZE_SUPPORTED )); then
    TAGGED_FILES=($(find_window_files "$CURRENT_SESSION_DIR"))
    TAGGED_IDS="$(collect_ids "${TAGGED_FILES[@]}" | sed '/^$/d')"
    TAGGED_JSON="$(printf '%s\n' $TAGGED_IDS | jq -R . | jq -s 'map(select(length>0))')"

    CURRENT_WINDOWS="$(wt_list_windows_with_app | jq -R -s -r \
        --arg re "$EXCLUDED_APPS_REGEX" \
        --argjson tagged "${TAGGED_JSON:-[]}" '
            split("\n") | map(select(length>0)) | map(split("\t"))
            | map({id: .[0], app: .[1], minimized: (.[2] // "0")})
            | ($tagged | map(tostring)) as $t
            | map(
                select(
                    (.app | test($re) | not)
                    and ((.minimized | tonumber) == 0)
                    and ((.id | tostring) as $id | ($t | index($id)) | not)
                )
            ) | .[].id
        ')"
    printf "%s\n" "$CURRENT_WINDOWS" | sed '/^$/d' | sort -u > "$CURRENT_SESSION_DIR/all_windows"
elif (( PSEUDO_MINIMIZE_SUPPORTED )); then
    TAGGED_FILES=($(find_window_files "$CURRENT_SESSION_DIR"))
    TAGGED_IDS_RAW="$(collect_ids "${TAGGED_FILES[@]}" | sed '/^$/d')"

    IFS=$'\n' read -r -d '' -a TAGGED_IDS < <(printf "%s\n" "$TAGGED_IDS_RAW" | sed '/^$/d' && printf '\0')

    CURRENT_IDS=()
    WORKSPACE_MAP_TMP="$(mktemp)"
    while IFS=$'\t' read -r window_id window_app window_ws || [[ -n "${window_id:-}" ]]; do
        [[ -z "$window_id" ]] && continue

        if [[ "$window_app" =~ $EXCLUDED_APPS_REGEX ]]; then
            continue
        fi

        if ! in_list "$window_id" "${TAGGED_IDS[@]}"; then
            CURRENT_IDS+=("$window_id")
        fi

        printf "%s\t%s\n" "$window_id" "$window_ws" >> "$WORKSPACE_MAP_TMP"
    done < <(wt_list_windows_with_app_and_workspace)

    printf "%s\n" "${CURRENT_IDS[@]}" | sed '/^$/d' | sort -u > "$CURRENT_SESSION_DIR/all_windows"
    sort -u "$WORKSPACE_MAP_TMP" > "$CURRENT_SESSION_DIR/workspace_map"
    rm -f "$WORKSPACE_MAP_TMP"
fi

MINIMIZE_FILES=($(find_window_files "$CURRENT_SESSION_DIR"))
FOCUS_FILES=($(find_window_files "$TARGET_SESSION_DIR"))

[[ -f "$CURRENT_SESSION_DIR/all_windows" ]] && MINIMIZE_FILES+=("$CURRENT_SESSION_DIR/all_windows")
[[ -f "$TARGET_SESSION_DIR/all_windows" ]] && FOCUS_FILES+=("$TARGET_SESSION_DIR/all_windows")

MINIMIZE="$(collect_ids "${MINIMIZE_FILES[@]}" | sort -u)"
FOCUS="$(collect_ids "${FOCUS_FILES[@]}" | sort -u)"

IFS=$'\n' read -r -d '' -a MINIMIZE_IDS < <(printf "%s\n" "$MINIMIZE" | sed '/^$/d' && printf '\0')
IFS=$'\n' read -r -d '' -a FOCUS_IDS < <(printf "%s\n" "$FOCUS" | sed '/^$/d' && printf '\0')

in_list() {
    local needle="$1"
    shift
    for candidate in "$@"; do
        [[ "$candidate" == "$needle" ]] && return 0
    done
    return 1
}

echo "$1" > "$SESSION_FILE"

TIMESTAMP="$(date +%s)"
MRU_FILE="$BASE_DIR/session_mru"
TMP_MRU="$(mktemp)"
{
    printf "%s\t%s\n" "$TIMESTAMP" "$1"
    if [[ -f "$MRU_FILE" ]]; then
        awk -F '\t' -v name="$1" '$2 != name' "$MRU_FILE"
    fi
} | sort -r -n -k1,1 | uniq -f1 > "$TMP_MRU"
mv "$TMP_MRU" "$MRU_FILE"
printf "%s\n" "$TIMESTAMP" > "$TARGET_SESSION_DIR/last_used"

FOCUS_TARGET="${FOCUS_IDS[0]:-}"

for window_id in "${FOCUS_IDS[@]}"; do
    if (( MINIMIZE_SUPPORTED )); then
        wt_deminimize_window "$window_id" > /dev/null 2>&1 &
    fi
    if [[ -z "$FOCUS_TARGET" ]]; then
        FOCUS_TARGET="$window_id"
    fi
    
    :
done

wait || true

if (( PSEUDO_MINIMIZE_SUPPORTED )); then
    HIDDEN_WORKSPACE="${WINDOW_TAGGING_HIDDEN_WORKSPACE:-__wt_hidden}"
    FOCUSED_WORKSPACE="$(wt_get_focused_workspace || true)"
    if [[ -z "$FOCUSED_WORKSPACE" ]]; then
        FOCUSED_WORKSPACE="1"
    fi

    WORKSPACE_MAP_FILE="$TARGET_SESSION_DIR/workspace_map"
    WINDOW_IDS_RAW="$(wt_list_window_ids)"
    IFS=$'\n' read -r -d '' -a EXISTING_IDS < <(printf "%s\n" "$WINDOW_IDS_RAW" | sed '/^$/d' && printf '\0')

    for window_id in "${FOCUS_IDS[@]}"; do
        if ! in_list "$window_id" "${EXISTING_IDS[@]}"; then
            continue
        fi

        target_ws="$FOCUSED_WORKSPACE"
        if [[ -f "$WORKSPACE_MAP_FILE" ]]; then
            mapped_ws="$(awk -F '\t' -v id="$window_id" '$1 == id {print $2; exit}' "$WORKSPACE_MAP_FILE")"
            if [[ -n "$mapped_ws" ]]; then
                target_ws="$mapped_ws"
            fi
        fi

        wt_move_window_to_workspace "$window_id" "$target_ws" > /dev/null 2>&1 || true
    done
fi

if [[ -n "$FOCUS_TARGET" ]]; then
    wt_focus_window_id "$FOCUS_TARGET" > /dev/null 2>&1 || true
fi

if (( MINIMIZE_SUPPORTED )); then
    WINDOWS_INFO="$(wt_list_windows_with_app)"

    while IFS=$'\t' read -r window_id window_app window_minimized; do
        [[ -z "$window_id" ]] && continue

        if in_list "$window_id" "${FOCUS_IDS[@]}"; then
            continue
        fi

        if [[ "$window_app" =~ $EXCLUDED_APPS_REGEX ]]; then
            continue
        fi

        wt_minimize_window "$window_id" > /dev/null 2>&1 &
    done <<< "$WINDOWS_INFO"
elif (( PSEUDO_MINIMIZE_SUPPORTED )); then
    while IFS=$'\t' read -r window_id window_app window_ws || [[ -n "${window_id:-}" ]]; do
        [[ -z "$window_id" ]] && continue

        if in_list "$window_id" "${FOCUS_IDS[@]}"; then
            continue
        fi

        if [[ "$window_app" =~ $EXCLUDED_APPS_REGEX ]]; then
            continue
        fi

        wt_move_window_to_workspace "$window_id" "$HIDDEN_WORKSPACE" > /dev/null 2>&1 || true
    done < <(wt_list_windows_with_app_and_workspace)
fi

shopt -s nullglob
SESSION_FILES=("$BASE_DIR/sessions/$1/window_id_*")
WINDOW_COUNT="${#SESSION_FILES[@]}"

echo "Focused session $1 with $WINDOW_COUNT windows"
