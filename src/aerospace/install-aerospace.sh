#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${WINDOW_TAGGING_REPO:-https://github.com/Exr0n/window-tagging.git}"
ROOT="${WINDOW_TAGGING_ROOT:-$HOME/.config/window-tagging}"
BINDS_CONFIG="${WINDOW_TAGGING_BINDS_CONFIG:-$HOME/.config/window-tagging/window-tagging-binds.toml}"

if [[ -n "${AEROSPACE_CONFIG:-}" ]]; then
  CONFIG="$AEROSPACE_CONFIG"
else
  if [[ -f "$HOME/.aerospace.toml" ]]; then
    CONFIG="$HOME/.aerospace.toml"
  elif [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/aerospace/aerospace.toml" ]]; then
    CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/aerospace/aerospace.toml"
  else
    CONFIG="$HOME/.aerospace.toml"
  fi
fi

MARK_BEGIN="# window-tagging (begin)"
MARK_END="# window-tagging (end)"

BACKEND="$ROOT/src/aerospace/backend.sh"
SWITCH="$ROOT/src/switch_to_window_or_workspace.sh"
SET="$ROOT/src/set_window_tag.sh"

fail() {
  echo "window-tagging install (aerospace): $1" >&2
  exit 1
}

ensure_repo() {
  if [[ -d "$ROOT/.git" ]]; then
    return 0
  fi
  if [[ -d "$ROOT" && ! -d "$ROOT/.git" ]]; then
    fail "target exists but is not a git repo: $ROOT"
  fi
  command -v git >/dev/null 2>&1 || fail "git not found; clone the repo manually"
  git clone "$REPO_URL" "$ROOT"
}

ensure_binds_config() {
  if [[ -f "$BINDS_CONFIG" ]]; then
    return 0
  fi
  local default_config="$ROOT/config/window-tagging-binds.toml"
  if [[ ! -f "$default_config" ]]; then
    fail "default binds config not found at $default_config"
  fi
  mkdir -p "$(dirname "$BINDS_CONFIG")"
  cp "$default_config" "$BINDS_CONFIG"
}

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

parse_keys_from_config() {
  local line values
  line="$(grep -E '^[[:space:]]*keys[[:space:]]*=' "$BINDS_CONFIG" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    echo "1 2 3 4 5 6 7 q w e r"
    return 0
  fi
  values="$(printf '%s' "$line" | sed -E 's/^[^[]*\[//; s/\].*$//')"

  local out=()
  local part
  IFS=',' read -r -a parts <<< "$values"
  for part in "${parts[@]}"; do
    part="$(trim "$part")"
    part="${part#\"}"
    part="${part%\"}"
    part="${part#\'}"
    part="${part%\'}"
    if [[ -n "$part" ]]; then
      out+=("$part")
    fi
  done

  if (( ${#out[@]} == 0 )); then
    echo "1 2 3 4 5 6 7 q w e r"
    return 0
  fi

  printf '%s ' "${out[@]}"
}

expand_keys() {
  local out=()
  local token
  for token in "$@"; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}"
      local end="${BASH_REMATCH[2]}"
      local i
      if (( start <= end )); then
        for ((i=start; i<=end; i++)); do out+=("$i"); done
      else
        for ((i=start; i>=end; i--)); do out+=("$i"); done
      fi
    elif [[ "$token" =~ ^[A-Za-z]+$ && ${#token} -gt 1 ]]; then
      local i
      for ((i=0; i<${#token}; i++)); do
        out+=("${token:i:1}")
      done
    else
      out+=("$token")
    fi
  done
  printf '%s ' "${out[@]}"
}

dedupe_keys() {
  local out=()
  local seen=""
  local key
  for key in "$@"; do
    if [[ " $seen " == *" $key "* ]]; then
      continue
    fi
    out+=("$key")
    seen+=" $key"
  done
  printf '%s ' "${out[@]}"
}

select_keys() {
  local defaults="$1"
  local keys="${WINDOW_TAGGING_KEYS:-}"

  if [[ -z "$keys" ]]; then
    if [[ -t 0 ]]; then
      if command -v gum >/dev/null 2>&1 && [[ "${WINDOW_TAGGING_USE_GUM:-1}" == "1" ]]; then
        local chosen
        chosen="$(printf '%s\n' $defaults | gum choose --no-limit --header 'Select window-tagging keys (enter to accept)')"
        if [[ -n "$chosen" ]]; then
          keys="$chosen"
        fi
      fi
      if [[ -z "$keys" ]]; then
        printf 'Window-tagging keys (space-separated) [default: %s]: ' "$defaults"
        read -r keys || true
      fi
    fi
  fi

  if [[ -z "$keys" ]]; then
    keys="$defaults"
  fi

  local expanded
  expanded="$(expand_keys $keys)"
  dedupe_keys $expanded
}

escape_regex() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//./\\.}"
  s="${s//^/\\^}"
  s="${s//\$/\\$}"
  s="${s//*/\\*}"
  s="${s//+/\\+}"
  s="${s//?/\\?}"
  s="${s//|/\\|}"
  s="${s//(/\\(}"
  s="${s//)/\\)}"
  s="${s//[/\\[}"
  s="${s//]/\\]}"
  printf '%s' "$s"
}

has_conflict() {
  local file="$1"
  local conflicts=()
  local key

  for key in $KEYS; do
    local re_key
    re_key="$(escape_regex "$key")"
    if grep -Eq "^[[:space:]]*[^#].*alt-$re_key[[:space:]]*=" "$file"; then
      conflicts+=("alt-$key")
    fi
    if grep -Eq "^[[:space:]]*[^#].*alt-shift-$re_key[[:space:]]*=" "$file"; then
      conflicts+=("alt-shift-$key")
    fi
  done

  if (( ${#conflicts[@]} )); then
    echo "Conflicting keybinds in $file:" >&2
    printf '  %s\n' "${conflicts[@]}" >&2
    return 0
  fi
  return 1
}

generate_block() {
  local out=""
  local key
  for key in $KEYS; do
    out+="alt-$key = 'exec-and-forget WINDOW_TAGGING_BACKEND=\"$BACKEND\" $SWITCH $key'\n"
    out+="alt-shift-$key = 'exec-and-forget WINDOW_TAGGING_BACKEND=\"$BACKEND\" $SET $key'\n"
  done
  printf '%b' "$out"
}

append_block() {
  local file="$1"
  local block
  block="$(generate_block)"

  if grep -Eq '^[[:space:]]*\[mode\.main\.binding\]' "$file"; then
    local tmp
    tmp="$(mktemp)"
    awk -v block="$block" -v mark_begin="$MARK_BEGIN" -v mark_end="$MARK_END" '
      BEGIN { inserted=0 }
      /^[[:space:]]*\[mode\.main\.binding\]/ && !inserted {
        print $0
        print mark_begin
        printf "%s", block
        print mark_end
        inserted=1
        next
      }
      { print $0 }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    {
      echo
      echo "[mode.main.binding]"
      echo "$MARK_BEGIN"
      printf "%s" "$block"
      echo "$MARK_END"
    } >> "$file"
  fi
}

ensure_repo
ensure_binds_config

DEFAULT_KEYS="$(parse_keys_from_config)"
KEYS="$(select_keys "$DEFAULT_KEYS")"

mkdir -p "$(dirname "$CONFIG")"
if [[ ! -f "$CONFIG" ]]; then
  touch "$CONFIG"
fi

if grep -q "$MARK_BEGIN" "$CONFIG"; then
  echo "window-tagging already installed in $CONFIG"
  exit 0
fi

if has_conflict "$CONFIG"; then
  fail "resolve conflicts and re-run"
fi

append_block "$CONFIG"

echo "window-tagging installed to $CONFIG"
