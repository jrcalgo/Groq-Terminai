#!/usr/bin/env bash

# memory.sh — Lightweight conversational memory for terminai/groq_cli.sh
# Stores rolling JSON memory and synthesizes a compact context string.
#
# Commands:
#   get [--max N] [--with "prompt"]     Print memory context (optionally append prompt at end, not stored)
#   append --prompt "text" [--response "text"]   Append entry to memory
#   clear                                  Clear memory file
#
# Location:
#   Uses $XDG_STATE_HOME/groq-cli or ~/.local/state/groq-cli
#
set -euo pipefail
IFS=$'\n\t'

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "[error] Missing dependency: $1" >&2; exit 1; }; }
require_cmd jq

STATE_DIR_DEFAULT="${XDG_STATE_HOME:-$HOME/.local/state}/groq-cli"
STATE_DIR="${STATE_DIR:-$STATE_DIR_DEFAULT}"
MEMORY_FILE="$STATE_DIR/memory.json"
MAX_KEEP="${MAX_KEEP:-100}"

ensure_state_dir() { mkdir -p "$STATE_DIR" || true; }

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

init_if_missing() {
  ensure_state_dir
  if [[ ! -f "$MEMORY_FILE" ]]; then
    printf '{"items":[]}\n' > "$MEMORY_FILE"
  fi
}

analyze_text() {
  # Input via $1 text; output JSON array of sentence analyses
  local text="$1"
  jq -Rn --arg t "$text" '
    def clean: gsub("\r";"") | gsub("\n";" ");
    def toks: ascii_downcase | gsub("[^a-z0-9 ]";" ") | split(" ") | map(select(length>2));
    def sent_split: gsub("[.!?]";"$0\n") | split("\n") | map(.|gsub("^\\s+|\\s+$";"")) | map(select(length>0));
    ($t|clean|sent_split) as $S
    | $S
    | map(
        . as $s
        | ( $s|toks ) as $k
        | {
            text: $s,
            tree: ("(S " + ($k|join(" ")) + ")"),
            keywords: $k[0:6],
            pair: ($k[0:2])
          }
      )
  '
}

cmd_get() {
  local max_items=8 with_prompt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max) max_items="$2"; shift 2;;
      --with) with_prompt="$2"; shift 2;;
      *) echo "[error] Unknown get option: $1" >&2; exit 1;;
    esac
  done
  init_if_missing
  local ctx
  ctx=$(jq -r --argjson n "${max_items}" '
    (.items // []) as $all
    | ($all | (if ($all|length) > $n then .[length-$n:] else . end))
    | map(
        "- " + (
          ((.summary // []) | map(tostring) | .[0:4] | join(", ")) //
          ((.pairs // []) | map(join(" ")) | .[0:2] | join(", ")) //
          ((.analysis[0].keywords // []) | .[0:3] | join(", "))
        )
      )
    | join("\n")
  ' "$MEMORY_FILE" 2>/dev/null || true)
  if [[ -n "$ctx" ]]; then
    echo -e "Recent context:\n$ctx"
  fi
  if [[ -n "$with_prompt" ]]; then
    echo -e "\nCurrent prompt:\n- $with_prompt"
  fi
}

cmd_append() {
  local prompt="" response=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prompt) prompt="$2"; shift 2;;
      --response) response="$2"; shift 2;;
      *) echo "[error] Unknown append option: $1" >&2; exit 1;;
    esac
  done
  [[ -n "$prompt" ]] || { echo "[error] append requires --prompt" >&2; exit 1; }
  init_if_missing
  local analysis item tmp
  analysis=$(analyze_text "$prompt")
  item=$(jq -n --arg p "$prompt" --arg r "$response" --arg ts "$(iso_now)" --argjson a "$analysis" '
    {
      ts: $ts,
      prompt: $p,
      response: (if ($r|length)>0 then $r else null end),
      analysis: $a,
      pairs: ($a | map(.pair) | add | unique)[0:8],
      summary: ($a | map(.keywords) | add | unique | .[0:8])
    }
  ')
  tmp=$(mktemp)
  jq --argjson it "$item" --argjson keep "$MAX_KEEP" '
    (.items // []) as $xs
    | { items: ($xs + [$it]) }
    | .items as $ys
    | if ($ys|length) > $keep then { items: ($ys | .[length-$keep:]) } else . end
  ' "$MEMORY_FILE" > "$tmp" && mv "$tmp" "$MEMORY_FILE"
}

cmd_clear() {
  ensure_state_dir
  rm -f "$MEMORY_FILE" || true
}

case "${1:-}" in
  get) shift; cmd_get "$@" ;;
  join)
    shift
    # join last N items into a conversation transcript; optional --max, --with
    max_items=8
    with_prompt=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --max) max_items="$2"; shift 2;;
        --with) with_prompt="$2"; shift 2;;
        *) echo "[error] Unknown join option: $1" >&2; exit 1;;
      esac
    done
    init_if_missing
    jq -r --argjson n "${max_items}" --arg with "$with_prompt" '
      (.items // []) as $all
      | (if ($all|length) > $n then ($all | .[length-$n:]) else $all end) as $last
      | $last
      | map(["User: " + ((.prompt // "")|tostring)] + (if .response then ["Assistant: " + ((.response)//""|tostring)] else [] end))
      | flatten as $lines
      | ($lines + (if ($with|length)>0 then ["User: " + $with] else [] end))
      | join("\n")
    ' "$MEMORY_FILE"
    ;;
  append) shift; cmd_append "$@" ;;
  clear) cmd_clear ;;
  *) echo "Usage: $0 {get|append|clear} ..." >&2; exit 1 ;;
esac


