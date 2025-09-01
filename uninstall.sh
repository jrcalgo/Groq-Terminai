#!/usr/bin/env bash

# uninstall.sh — Uninstaller for terminai (Groq CLI)
#
# Removes the installed binary. Defaults to /usr/local/bin/terminai.
# Options:
#   --prefix DIR     Prefix used at install (default: /usr/local)
#   --dest-bin PATH  Exact installed path
#   --name NAME      Binary name (default: terminai)
#   --dry-run        Show actions without executing
#   -h, --help       Show help

set -euo pipefail
IFS=$'\n\t'

PREFIX="/usr/local"
DEST_BIN=""
BINARY_NAME="groq-terminai"
DRY_RUN=0

print_help() {
  cat <<EOF
terminai uninstaller

Options:
  --prefix DIR     Prefix used at install (default: /usr/local)
  --dest-bin PATH  Exact installed path
  --name NAME      Binary name (default: terminai)
  --dry-run        Show actions without executing
  -h, --help       Show this help
EOF
}

err() { echo "[error] $*" >&2; }
info() { echo "[info] $*"; }

need_sudo() {
  local path="$1"
  [[ -w "$path" ]] && return 1 || return 0
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
  local target
  if [[ -n "$DEST_BIN" ]]; then
    target="$DEST_BIN"
  else
    target="$PREFIX/bin/$BINARY_NAME"
  fi

  if [[ ! -e "$target" ]]; then
    info "Nothing to remove at $target"
    exit 0
  fi

  if need_sudo "$target"; then
    run_cmd sudo rm -f "$target"
  else
    run_cmd rm -f "$target"
  fi

  info "Removed $target"
}

main "$@"


