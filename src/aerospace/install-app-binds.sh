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

MARK_BEGIN="# window-tagging apps (begin)"
MARK_END="# window-tagging apps (end)"

fail() {
  echo "window-tagging app binds (aerospace): $1" >&2
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

parse_value() {
  local v="${1#*=}"
  v="$(trim "$v")"
  if [[ "$v" =~ ^".*"$ ]]; then
    v="${v#\"}"
    v="${v%\"}"
    v="${v//\\\"/\"}"
    v="${v//\\\\/\\}"
    printf '%s' "$v"
    return 0
  fi
  if [[ "$v" =~ ^\'.*\'$ ]]; then
    v="${v#\'}"
    v="${v%\'}"
    printf '%s' "$v"
    return 0
  fi
  printf '%s' "$v"
}

parse_app_binds() {
  local in_bind=0
  local key="" mods="" action="" app="" label="" command=""

  emit() {
    if [[ -z "$key" ]]; then
      return 0
    fi
    if [[ -z "$command" && -z "$app" ]]; then
      return 0
    fi
    if [[ -z "$mods" ]]; then
      mods="lalt"
    fi
    if [[ -z "$action" ]]; then
      action="open"
    fi
    if [[ -z "$label" ]]; then
      label="$app"
    fi
    printf '%s|%s|%s|%s|%s|%s\n' "$key" "$mods" "$action" "$app" "$label" "$command"
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue

    if [[ "$line" == "[[app_tagging.bind]]" ]]; then
      if (( in_bind )); then
        emit
      fi
      in_bind=1
      key=""; mods=""; action=""; app=""; label=""; command=""
      continue
    fi

    if (( in_bind )); then
      case "$line" in
        key\ *=*) key="$(parse_value "$line")" ;;
        mods\ *=*) mods="$(parse_value "$line")" ;;
        action\ *=*) action="$(parse_value "$line")" ;;
        app\ *=*) app="$(parse_value "$line")" ;;
        label\ *=*) label="$(parse_value "$line")" ;;
        command\ *=*) command="$(parse_value "$line")" ;;
      esac
    fi
  done < "$BINDS_CONFIG"

  if (( in_bind )); then
    emit
  fi
}

mods_to_aero() {
  local mods="$1"
  mods="${mods// /}"
  local out=""
  local part
  IFS='+' read -r -a parts <<< "$mods"
  for part in "${parts[@]}"; do
    case "$part" in
      alt|lalt) part="alt" ;;
      shift|lshift) part="shift" ;;
      ctrl|control|lctrl) part="ctrl" ;;
      cmd|command|lcmd) part="cmd" ;;
    esac
    if [[ -z "$out" ]]; then
      out="$part"
    else
      out="$out-$part"
    fi
  done
  printf '%s' "$out"
}

build_command() {
  local action="$1"
  local app="$2"
  local command="$3"

  if [[ -n "$command" ]]; then
    printf '%s' "$command"
    return 0
  fi

  case "$action" in
    open)
      printf 'open -a "%s"' "$app"
      ;;
    open_if_running)
      printf 'APP="%s"; if [[ "$(osascript -e "application \\"%s\\" is running")" == "true" ]]; then open -a "%s"; fi' "$app" "$app" "$app"
      ;;
    *)
      printf 'open -a "%s"' "$app"
      ;;
  esac
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

collect_binds() {
  mapfile -t BINDS < <(parse_app_binds)
  if (( ${#BINDS[@]} == 0 )); then
    fail "no app_tagging.bind entries found in $BINDS_CONFIG"
  fi
}

select_binds() {
  local selection="${WINDOW_TAGGING_APP_SELECTION:-}"

  if [[ -z "$selection" && -t 0 ]]; then
    if command -v gum >/dev/null 2>&1 && [[ "${WINDOW_TAGGING_USE_GUM:-1}" == "1" ]]; then
      local choices=()
      local i=1
      local bind
      for bind in "${BINDS[@]}"; do
        IFS='|' read -r key mods action app label command <<< "$bind"
        choices+=("$i) $mods-$key  $label")
        i=$((i+1))
      done
      local chosen
      chosen="$(printf '%s\n' "${choices[@]}" | gum choose --no-limit --header 'Select app binds (enter to accept)')"
      if [[ -n "$chosen" ]]; then
        selection="$(printf '%s\n' "$chosen" | sed -E 's/^([0-9]+).*/\\1/' | tr '\n' ' ')"
      fi
    fi
    if [[ -z "$selection" ]]; then
      echo "App binds available:" >&2
      local i=1
      local bind
      for bind in "${BINDS[@]}"; do
        IFS='|' read -r key mods action app label command <<< "$bind"
        printf '  %d) %s-%s  %s\n' "$i" "$mods" "$key" "$label" >&2
        i=$((i+1))
      done
      printf 'Select binds (space-separated numbers) [default: all]: ' >&2
      read -r selection || true
    fi
  fi

  if [[ -z "$selection" || "$selection" == "all" ]]; then
    SELECTED_BINDS=("${BINDS[@]}")
    return 0
  fi

  local selected=()
  local idx
  for idx in $selection; do
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#BINDS[@]} )); then
      selected+=("${BINDS[$((idx-1))]}")
    fi
  done

  if (( ${#selected[@]} == 0 )); then
    fail "no valid selections"
  fi

  SELECTED_BINDS=("${selected[@]}")
}

has_conflict() {
  local file="$1"
  local conflicts=()
  local bind

  for bind in "${SELECTED_BINDS[@]}"; do
    IFS='|' read -r key mods action app label command <<< "$bind"
    local re_key
    re_key="$(escape_regex "$key")"
    local mod_re="$(escape_regex "$(mods_to_aero "$mods")")"
    if grep -Eq "^[[:space:]]*[^#].*$mod_re-$re_key[[:space:]]*=" "$file"; then
      conflicts+=("$mod_re-$key")
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
  local bind
  for bind in "${SELECTED_BINDS[@]}"; do
    IFS='|' read -r key mods action app label command <<< "$bind"
    local aero_mods cmd
    aero_mods="$(mods_to_aero "$mods")"
    cmd="$(build_command "$action" "$app" "$command")"
    out+="$aero_mods-$key = 'exec-and-forget $cmd'\n"
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
collect_binds
select_binds

mkdir -p "$(dirname "$CONFIG")"
if [[ ! -f "$CONFIG" ]]; then
  touch "$CONFIG"
fi

if grep -q "$MARK_BEGIN" "$CONFIG"; then
  echo "window-tagging app binds already installed in $CONFIG"
  exit 0
fi

if has_conflict "$CONFIG"; then
  fail "resolve conflicts and re-run"
fi

append_block "$CONFIG"

echo "window-tagging app binds installed to $CONFIG"
