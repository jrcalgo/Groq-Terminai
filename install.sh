#!/usr/bin/env bash

# install.sh — Installer for terminai (Groq CLI)
#
# Installs the CLI as /usr/local/bin/terminai by default.
# Options:
#   --prefix DIR        Install under DIR (default: /usr/local)
#   --dest-bin PATH     Install to exact PATH (overrides --prefix)
#   --mode copy|symlink Copy the script or create a symlink (default: copy)
#   --name NAME         Binary name (default: terminai)
#   --dry-run           Show actions without executing
#   -h, --help          Show help
#
# Usage:
#   bash install.sh
#   bash install.sh --mode symlink
#   bash install.sh --prefix "$HOME/.local"

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/groq_cli.sh"
GLOBAL_DEFAULTS="/etc/groq-terminai/defaults.json"

PREFIX="/usr/local"
DEST_BIN=""
BINARY_NAME="groq-terminai"
MODE="copy"
DRY_RUN=0

print_help() {
  cat <<EOF
terminai installer

Options:
  --prefix DIR        Install under DIR (default: /usr/local)
  --dest-bin PATH     Install to exact PATH (overrides --prefix)
  --mode copy|symlink Copy the script or create a symlink (default: copy)
  --name NAME         Binary name (default: terminai)
  --dry-run           Show actions without executing
  -h, --help          Show this help

Examples:
  bash install.sh
  bash install.sh --mode symlink
  bash install.sh --prefix "$HOME/.local"
EOF
}

err() { echo "[error] $*" >&2; }
info() { echo "[info] $*"; }

need_sudo() {
  local target_dir="$1"
  [[ -w "$target_dir" ]] && return 1 || return 0
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ $*"
  else
    eval "$@"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix)
        PREFIX="$2"; shift 2 ;;
      --dest-bin)
        DEST_BIN="$2"; shift 2 ;;
      --mode)
        MODE="$2"; shift 2 ;;
      --name)
        BINARY_NAME="$2"; shift 2 ;;
      --dry-run)
        DRY_RUN=1; shift ;;
      -h|--help)
        print_help; exit 0 ;;
      *)
        err "Unknown option: $1"; exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"

  [[ -f "$SOURCE_FILE" ]] || { err "Cannot find $SOURCE_FILE"; exit 1; }
  [[ "$MODE" == "copy" || "$MODE" == "symlink" ]] || { err "--mode must be copy or symlink"; exit 1; }

  local dest
  if [[ -n "$DEST_BIN" ]]; then
    dest="$DEST_BIN"
  else
    dest="$PREFIX/bin/$BINARY_NAME"
  fi

  local dest_dir
  dest_dir="$(dirname "$dest")"
  [[ "$DRY_RUN" -eq 1 ]] || mkdir -p "$dest_dir"

  if need_sudo "$dest_dir"; then
    info "Installing to $dest (requires sudo)"
    if [[ "$MODE" == "copy" ]]; then
      run_cmd sudo install -Dm755 "$SOURCE_FILE" "$dest"
    else
      run_cmd sudo ln -sf "$SOURCE_FILE" "$dest"
      run_cmd sudo chmod +x "$SOURCE_FILE"
    fi
    # Initialize global defaults with first available model if possible
    if command -v jq >/dev/null 2>&1; then
      if [[ -n "${GROQ_API_KEY:-}" ]]; then
        local api first_model tmp
        api="${API_BASE_URL:-https://api.groq.com/openai/v1}"
        first_model=$(curl -sS -X GET "$api/models" \
          -H "Authorization: Bearer ${GROQ_API_KEY}" \
          -H "Content-Type: application/json" \
          --max-time 15 | jq -r '.data[]? | .id // empty' | head -n1 || true)
        if [[ -n "$first_model" ]]; then
          run_cmd sudo mkdir -p /etc/groq-terminai
          tmp=$(mktemp)
          printf '{"model":"%s","temperature":"0.7","timeout":300,"stream":false}' "$first_model" > "$tmp"
          run_cmd sudo mv "$tmp" "$GLOBAL_DEFAULTS"
          run_cmd sudo chmod 644 "$GLOBAL_DEFAULTS"
          info "Default model set to: $first_model (global)"
        fi
      fi
    fi
  else
    info "Installing to $dest"
    if [[ "$MODE" == "copy" ]]; then
      run_cmd install -Dm755 "$SOURCE_FILE" "$dest"
    else
      run_cmd ln -sf "$SOURCE_FILE" "$dest"
      run_cmd chmod +x "$SOURCE_FILE"
    fi
    # Initialize user config with first available model if possible
    if command -v jq >/dev/null 2>&1; then
      if [[ -n "${GROQ_API_KEY:-}" ]]; then
        local api first_model user_cfg_dir user_cfg tmp
        api="${API_BASE_URL:-https://api.groq.com/openai/v1}"
        first_model=$(curl -sS -X GET "$api/models" \
          -H "Authorization: Bearer ${GROQ_API_KEY}" \
          -H "Content-Type: application/json" \
          --max-time 15 | jq -r '.data[]? | .id // empty' | head -n1 || true)
        if [[ -n "$first_model" ]]; then
          user_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/groq-terminai"
          user_cfg="$user_cfg_dir/config.json"
          run_cmd mkdir -p "$user_cfg_dir"
          tmp=$(mktemp)
          printf '{"model":"%s","temperature":"0.7","timeout":300,"stream":false}' "$first_model" > "$tmp"
          run_cmd mv "$tmp" "$user_cfg"
          info "Default model set to: $first_model (user)"
        fi
      fi
    fi
  fi

  info "Installed $BINARY_NAME → $dest"
  echo "Try: $BINARY_NAME --help"
}

main "$@"


