#!/usr/bin/env bash

# groq_cli.sh - Bash CLI for interacting with the Groq API (OpenAI-compatible)
#
# Requirements:
#   - bash, curl, jq
#   - Set GROQ_API_KEY in your environment (export GROQ_API_KEY="..." )
#
# Basic usage examples:
#   bash groq_cli.sh --prompt "Explain quantum computing in simple terms." --model llama-3.1-70b-versatile --temperature 0.7 --max-tokens 300
#   bash groq_cli.sh --file question.txt --model llama-3.1-70b-versatile
#   bash groq_cli.sh --prompt "Hello" --stream
#   bash groq_cli.sh --prompt "Hello" --save out.txt
#
# Notes:
#   - Default API endpoint is https://api.groq.com/openai/v1/chat/completions
#   - Supports streaming output with --stream
#   - Caches requests/responses in XDG_CACHE_HOME or ~/.cache/groq-cli (disable via --no-cache)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
BRAND_NAME="Groq-Terminai"
CMD_DISPLAY="groq-terminai"
VERSION="0.1.0"

# ------------ Colors & Formatting ------------
USE_COLOR=1
BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; RESET=""

color_setup() {
  if [[ "${NO_COLOR:-0}" -eq 1 ]]; then
    USE_COLOR=0
  fi
  if [[ $USE_COLOR -eq 1 && -t 1 ]] && command -v tput >/dev/null 2>&1; then
    local ncolors
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if [[ "$ncolors" -ge 8 ]]; then
      BOLD=$(tput bold)
      RED=$(tput setaf 1)
      GREEN=$(tput setaf 2)
      YELLOW=$(tput setaf 3)
      BLUE=$(tput setaf 4)
      MAGENTA=$(tput setaf 5)
      CYAN=$(tput setaf 6)
      RESET=$(tput sgr0)
    fi
  fi
}

log() { echo -e "$*"; }
info() { log "${CYAN}[info]${RESET} $*"; }
warn() { log "${YELLOW}[warn]${RESET} $*"; }
err() { log "${RED}[error]${RESET} $*"; }
die() { err "$*"; exit 1; }

# ------------ Defaults & Globals ------------
API_BASE_URL_DEFAULT="https://api.groq.com/openai/v1"
API_BASE_URL="${API_BASE_URL:-$API_BASE_URL_DEFAULT}"

# Config file for persistent settings (new brand)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/groq-terminai"
CONFIG_FILE="$CONFIG_DIR/config.json"
GLOBAL_CONFIG_FILE="/etc/groq-terminai/defaults.json"
# Backward-compat old paths
ALT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/groq-cli"
ALT_GLOBAL_CONFIG_FILE="/etc/groq-cli/defaults.json"

# Default values (can be overridden by config file)
MODEL_DEFAULT="llama-3.1-70b-versatile"
TEMPERATURE_DEFAULT="0.7"
TIMEOUT_DEFAULT=300

# Runtime values (loaded from config or defaults)
MODEL="$MODEL_DEFAULT"
TEMPERATURE="$TEMPERATURE_DEFAULT"
MAX_TOKENS=""                     # Change via --max-tokens (optional)
STOP_SEQS=""                      # Comma-separated list via --stop
SYSTEM_PROMPT=""                  # Optional system message via --system
PROMPT_TEXT=""                    # From --prompt or positional args
PROMPT_FILE=""                    # From --file
STREAM=0                           # --stream to enable
SAVE_FILE=""                      # --save file.txt
RAW_JSON=0                         # --json to print raw JSON
NO_COLOR=0                         # --no-color to disable
TIMEOUT="$TIMEOUT_DEFAULT"         # --timeout seconds
CLEAR_MEMORY=0                      # --clear conversation memory
PROMPT_EFFECTIVE=""                # Computed prompt with memory context
MEM_SCRIPT_PATH=""                 # Path to memory.sh if available
USE_MEMORY=1                        # Include memory by default

# Admin flags
SET_MODEL=""                       # --set-model to save default model
SET_TEMPERATURE=""                 # --set-temperature to save default temperature
SET_TIMEOUT=""                     # --set-timeout to save default timeout
SHOW_CONFIG=0                      # --show-config to display current settings
RESET_CONFIG=0                     # --reset-config to restore defaults
SET_STREAM=""                      # --set-stream on|off to save default streaming
SHOW_HELP=0                        # -h/--help to display after config load
SET_SYSTEM=""                      # --set-system to save default system message

# Caching
XDG_CACHE_HOME_DEF="$HOME/.cache"
CACHE_DIR="${XDG_CACHE_HOME:-$XDG_CACHE_HOME_DEF}/groq-terminai"
CACHE_ENABLED=1                     # --no-cache to disable
LIST_CACHE=0                        # --list-cache to show available cached entries
REPLAY_KEY=""                      # --replay <hash> to print cached response

# ------------ Help / Usage ------------
usage() {
  cat <<EOF
${BOLD}${BRAND_NAME}${RESET} v${VERSION} — Groq API CLI (OpenAI-compatible)

Usage:
  ${CMD_DISPLAY} [options]

Input options (choose one):
  --prompt "text"            Prompt input directly
  --file path.txt            Read prompt from file

Model & parameters:
  --model NAME               Groq model (default: ${MODEL})
  --temperature VAL          Randomness, 0.0–2.0 (default: ${TEMPERATURE})
  --max-tokens N             Max tokens in response (optional)
  --stop "a,b,c"             Comma-separated stop sequences
  --system "text"            Optional system message

Behavior & output:
  --stream                   Stream output tokens as they arrive
  --no-stream                Disable streaming for this call
  --save out.txt             Save final response text to file
  --json                     Print raw JSON (non-streaming only)
  --timeout SECONDS          Request timeout (default: ${TIMEOUT})
  --no-color                 Disable terminal colors
  --clear                    Clear conversation memory before request
  --no-memory                Do not include conversation memory in this call

Caching (optional):
  --no-cache                 Disable on-disk caching
  --cache-dir DIR            Set cache directory (default: ${CACHE_DIR})
  --list-cache               List cached requests
  --replay HASH              Print cached response by hash

Misc:
  --model-list               Show a few example Groq models
  --show-config              Display current configuration
  --reset-config             Reset configuration to defaults
  -h, --help                 Show this help

Configuration:
  --set-model NAME           Set and save default model
  --set-temperature VAL      Set and save default temperature
  --set-timeout SECONDS      Set and save default timeout
  --set-stream on|off        Set and save default streaming
  --set-system TEXT          Set and save default system message

Environment:
  GROQ_API_KEY               Your Groq API key (required)
  API_BASE_URL               Override API base (default: ${API_BASE_URL_DEFAULT})

Examples (default model: ${MODEL}):
  ${CMD_DISPLAY} --prompt "Explain quantum computing simply." --model ${MODEL} --temperature 0.7 --max-tokens 300
  ${CMD_DISPLAY} --file question.txt --model ${MODEL}
  ${CMD_DISPLAY} --prompt "Hello" --stream
  ${CMD_DISPLAY} --prompt "Hello" --save out.txt
EOF
}

fetch_models() {
  if [[ -z "${GROQ_API_KEY:-}" ]]; then
    err "GROQ_API_KEY is required to fetch model list."
    return 1
  fi
  require_cmd curl
  require_cmd jq
  local tmp
  tmp=$(mktemp)
  curl -sS -X GET "$API_BASE_URL/models" \
    -H "Authorization: Bearer ${GROQ_API_KEY}" \
    -H "Content-Type: application/json" \
    --max-time "$TIMEOUT" -o "$tmp"
  # Output TSV: CATEGORY<TAB>ID
  jq -r '
    .data[]? as $m
    | $m.id as $id
    | (($m.status // $m.lifecycle // $m.tier) // (if ($id|test("(preview|beta|alpha|maverick|scout|dev|test)"; "i")) then "preview" else "production" end)) as $cat
    | ($cat // "production") + "\t" + ($id // "")
  ' "$tmp" 2>/dev/null || true
  rm -f "$tmp" || true
}

model_list() {
  # Try to load config to know current default
  if command -v jq >/dev/null 2>&1; then
    load_config || true
  fi
  local tsv
  tsv=$(fetch_models 2>/dev/null || true)
  if [[ -z "$tsv" ]]; then
    echo "Unable to fetch model list. Check GROQ_API_KEY or network."
    echo "Current default model: ${MODEL}"
    return 1
  fi
  echo "Available Groq models (default marked with *):"
  echo "Production:"
  echo "$tsv" | awk -F '\t' '$1=="production" && $2!="" {print $2}' | while read -r id; do
    if [[ "$id" == "$MODEL" ]]; then
      echo "  * $id"
    else
      echo "    $id"
    fi
  done
  echo "Preview:"
  echo "$tsv" | awk -F '\t' '$1=="preview" && $2!="" {print $2}' | while read -r id; do
    if [[ "$id" == "$MODEL" ]]; then
      echo "  * $id"
    else
      echo "    $id"
    fi
  done
}

# ------------ Utilities ------------
require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

read_prompt_from_file() {
  local f="$1"
  [[ -f "$f" ]] || die "File not found: $f"
  PROMPT_TEXT="$(<"$f")"
}

trim() { sed -e 's/^\s\+//' -e 's/\s\+$//'; }

is_number() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

ensure_cache_dir() {
  if [[ "$CACHE_ENABLED" -eq 1 ]]; then
    mkdir -p "$CACHE_DIR" || true
  fi
}

ensure_config_dir() {
  mkdir -p "$CONFIG_DIR" || true
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local config_model config_temp config_timeout config_stream config_system
    config_model=$(jq -r '.model // empty' "$CONFIG_FILE" 2>/dev/null || true)
    config_temp=$(jq -r '.temperature // empty' "$CONFIG_FILE" 2>/dev/null || true)
    config_timeout=$(jq -r '.timeout // empty' "$CONFIG_FILE" 2>/dev/null || true)
    config_system=$(jq -r '.system // empty' "$CONFIG_FILE" 2>/dev/null || true)
    config_stream=$(jq -r '.stream // empty' "$CONFIG_FILE" 2>/dev/null || true)
    
    [[ -n "$config_model" ]] && MODEL="$config_model"
    [[ -n "$config_temp" ]] && TEMPERATURE="$config_temp"
    [[ -n "$config_timeout" ]] && TIMEOUT="$config_timeout"
    [[ -n "$config_system" ]] && SYSTEM_PROMPT="$config_system"
    if [[ -n "$config_stream" ]]; then
      if [[ "$config_stream" == "true" || "$config_stream" == "1" ]]; then
        STREAM=1
      else
        STREAM=0
      fi
    fi
    return
  fi
  # Fallback to old global defaults
  if [[ ! -f "$CONFIG_FILE" && -f "$ALT_GLOBAL_CONFIG_FILE" ]]; then
    local g_model g_temp g_timeout g_stream g_system
    g_model=$(jq -r '.model // empty' "$ALT_GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    g_temp=$(jq -r '.temperature // empty' "$ALT_GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    g_timeout=$(jq -r '.timeout // empty' "$ALT_GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    g_stream=$(jq -r '.stream // empty' "$ALT_GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    g_system=$(jq -r '.system // empty' "$ALT_GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$g_model" ]] && MODEL="$g_model"
    [[ -n "$g_temp" ]] && TEMPERATURE="$g_temp"
    [[ -n "$g_timeout" ]] && TIMEOUT="$g_timeout"
    [[ -n "$g_system" ]] && SYSTEM_PROMPT="$g_system"
    if [[ -n "$g_stream" ]]; then
      if [[ "$g_stream" == "true" || "$g_stream" == "1" ]]; then
        STREAM=1
      else
        STREAM=0
      fi
    fi
  fi
  # User config missing; try global defaults
  if [[ -f "$GLOBAL_CONFIG_FILE" ]]; then
    local g_model g_temp g_timeout g_stream
    g_model=$(jq -r '.model // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    g_temp=$(jq -r '.temperature // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    g_timeout=$(jq -r '.timeout // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    g_stream=$(jq -r '.stream // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$g_model" ]] && MODEL="$g_model"
    [[ -n "$g_temp" ]] && TEMPERATURE="$g_temp"
    [[ -n "$g_timeout" ]] && TIMEOUT="$g_timeout"
    if [[ -n "$g_stream" ]]; then
      if [[ "$g_stream" == "true" || "$g_stream" == "1" ]]; then
        STREAM=1
      else
        STREAM=0
      fi
    fi
    return
  fi
  # No config anywhere; if key present, auto-discover first model and save
  if [[ -n "${GROQ_API_KEY:-}" ]] && command -v jq >/dev/null 2>&1; then
    local first
    first=$(fetch_models | head -n1 || true)
    if [[ -n "$first" ]]; then
      MODEL="$first"
      save_config
    fi
  fi
}

save_config() {
  ensure_config_dir
  local stream_json="false"
  if [[ "$STREAM" -eq 1 ]]; then stream_json="true"; fi
  jq -n \
    --arg model "$MODEL" \
    --arg temperature "$TEMPERATURE" \
    --arg timeout "$TIMEOUT" \
    --argjson stream $stream_json \
    --arg system "$SYSTEM_PROMPT" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      model: $model,
      temperature: $temperature,
      timeout: ($timeout|tonumber),
      stream: $stream,
      system: (if ($system|length)>0 then $system else null end),
      updated_at: $updated
    }' > "$CONFIG_FILE"
}

show_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    echo -ne "${BOLD}${BLUE}Current Configuration:${RESET}\n"
    jq -r 'to_entries[] | "  \(.key): \(.value)"' "$CONFIG_FILE" | grep -v "updated_at"
    echo -ne "${BOLD}${BLUE}Default values:${RESET}\n"
    echo -ne "  model: ${MODEL_DEFAULT}\n"
    echo -ne "  temperature: ${TEMPERATURE_DEFAULT}\n"
    echo -ne "  timeout: ${TIMEOUT_DEFAULT}\n"
  else
    echo -ne "${BOLD}${BLUE}No configuration file found. Using defaults:${RESET}\n"
    echo -ne "  model: ${MODEL_DEFAULT}\n"
    echo -ne "  temperature: ${TEMPERATURE_DEFAULT}\n"
    echo -ne "  timeout: ${TIMEOUT_DEFAULT}\n"
  fi
}

reset_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    rm -f "$CONFIG_FILE"
    MODEL="$MODEL_DEFAULT"
    TEMPERATURE="$TEMPERATURE_DEFAULT"
    TIMEOUT="$TIMEOUT_DEFAULT"
    echo -ne "${BOLD}${GREEN}Configuration reset to defaults.${RESET}\n"
  else
    echo -ne "${BOLD}${YELLOW}No configuration file to reset.${RESET}\n"
  fi
}

stop_to_json_array() {
  local s="$1"
  if [[ -z "$s" ]]; then
    echo '[]'
  else
    jq -Rn --arg s "$s" '$s | split(",") | map(gsub("^\\s+|\\s+$"; ""))'
  fi
}

canonical_request_json() {
  # Produce a canonical (non-streaming) JSON for cache key
  local stop_json
  stop_json=$(stop_to_json_array "$STOP_SEQS")

  jq -n \
    --arg model "$MODEL" \
    --arg prompt "$PROMPT_TEXT" \
    --arg system "$SYSTEM_PROMPT" \
    --arg temperature "$TEMPERATURE" \
    --arg max_tokens "$MAX_TOKENS" \
    --argjson stop "$stop_json" \
    '
    (
      {
        model: $model,
        messages: ([ ( ($system|length>0 and ($system != "")) as $hasSys | if $hasSys then {role:"system", content:$system} else empty end ) ] + [{role:"user", content:$prompt}]),
        temperature: ($temperature|tonumber)
      }
      | if ($stop|length>0) and ($stop != []) then . + {stop: $stop} else . end
      | if ($max_tokens|length>0) and ($max_tokens != "") then . + {max_tokens: ($max_tokens|tonumber)} else . end
    )
    '
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    die "No sha256sum or shasum available for hashing"
  fi
}

cache_key() {
  canonical_request_json | sha256
}

list_cache() {
  ensure_cache_dir
  [[ -d "$CACHE_DIR" ]] || die "Cache dir not found: $CACHE_DIR"
  local count=0
  for f in "$CACHE_DIR"/*.json; do
    [[ -e "$f" ]] || { echo "No cache entries."; return; }
    local key created model summary
    key="$(basename "$f" .json)"
    created=$(jq -r '.meta.created_at_iso // ""' "$f" 2>/dev/null || true)
    model=$(jq -r '.request.model // ""' "$f" 2>/dev/null || true)
    summary=$(jq -r '.request.messages[] | select(.role=="user") | .content | .[0:80] + (length>80?"...":"")' "$f" 2>/dev/null | head -n1 || true)
    printf "%s  %s  [%s]\n    %s\n" "$key" "${created:-}" "${model:-}" "${summary:-}"
    count=$((count+1))
  done
  [[ "$count" -gt 0 ]] || echo "No cache entries."
}

replay_cache() {
  local key="$1"
  local f="$CACHE_DIR/$key.json"
  [[ -f "$f" ]] || die "Cache not found for key: $key"
  local text
  text=$(jq -r '.response.text // empty' "$f" 2>/dev/null || true)
  if [[ -n "$text" ]]; then
    echo -ne "$text\n"
  else
    # As fallback, print raw JSON response
    jq '.' "$f"
  fi
}

# Build request payload (streaming or non-streaming)
build_request_json() {
  local stream_flag="$1" # true|false
  local stop_json
  stop_json=$(stop_to_json_array "$STOP_SEQS")

  jq -n \
    --arg model "$MODEL" \
    --arg prompt "${PROMPT_EFFECTIVE:-$PROMPT_TEXT}" \
    --arg system "$SYSTEM_PROMPT" \
    --arg temperature "$TEMPERATURE" \
    --arg max_tokens "$MAX_TOKENS" \
    --argjson stop "$stop_json" \
    --argjson stream "$stream_flag" \
    '
    (
      {
        model: $model,
        messages: ([ ( ($system|length>0 and ($system != "")) as $hasSys | if $hasSys then {role:"system", content:$system} else empty end ) ] + [{role:"user", content:$prompt}]),
        temperature: ($temperature|tonumber),
        stream: $stream
      }
      | if ($stop|length>0) and ($stop != []) then . + {stop: $stop} else . end
      | if ($max_tokens|length>0) and ($max_tokens != "") then . + {max_tokens: ($max_tokens|tonumber)} else . end
    )
    '
}

# ------------ Argument Parsing ------------
parse_args() {
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prompt|-p)
        [[ $# -ge 2 ]] || die "--prompt requires an argument"
        PROMPT_TEXT+="$2"
        shift 2
        ;;
      --file|-f)
        [[ $# -ge 2 ]] || die "--file requires a path"
        PROMPT_FILE="$2"
        shift 2
        ;;
      --model|-m)
        [[ $# -ge 2 ]] || die "--model requires a name"
        MODEL="$2"
        shift 2
        ;;
      --temperature|--temp)
        [[ $# -ge 2 ]] || die "--temperature requires a value"
        TEMPERATURE="$2"
        shift 2
        ;;
      --max-tokens|--max_tokens)
        [[ $# -ge 2 ]] || die "--max-tokens requires a number"
        MAX_TOKENS="$2"
        shift 2
        ;;
      --stop)
        [[ $# -ge 2 ]] || die "--stop requires a comma-separated list"
        STOP_SEQS="$2"
        shift 2
        ;;
      --system)
        [[ $# -ge 2 ]] || die "--system requires text"
        SYSTEM_PROMPT="$2"
        shift 2
        ;;
      --stream)
        STREAM=1
        shift
        ;;
      --no-stream)
        STREAM=0
        shift
        ;;
      --save)
        [[ $# -ge 2 ]] || die "--save requires a path"
        SAVE_FILE="$2"
        shift 2
        ;;
      --json|--raw-json)
        RAW_JSON=1
        shift
        ;;
      --clear)
        CLEAR_MEMORY=1
        shift
        ;;
      --no-memory)
        USE_MEMORY=0
        shift
        ;;
      --no-color)
        NO_COLOR=1
        shift
        ;;
      --timeout)
        [[ $# -ge 2 ]] || die "--timeout requires seconds"
        TIMEOUT="$2"
        shift 2
        ;;
      --no-cache)
        CACHE_ENABLED=0
        shift
        ;;
      --cache-dir)
        [[ $# -ge 2 ]] || die "--cache-dir requires a path"
        CACHE_DIR="$2"
        shift 2
        ;;
      --list-cache)
        LIST_CACHE=1
        shift
        ;;
      --replay)
        [[ $# -ge 2 ]] || die "--replay requires a key"
        REPLAY_KEY="$2"
        shift 2
        ;;
      --set-model)
        [[ $# -ge 2 ]] || die "--set-model requires a model name"
        SET_MODEL="$2"
        shift 2
        ;;
      --set-temperature)
        [[ $# -ge 2 ]] || die "--set-temperature requires a value"
        SET_TEMPERATURE="$2"
        shift 2
        ;;
      --set-timeout)
        [[ $# -ge 2 ]] || die "--set-timeout requires seconds"
        SET_TIMEOUT="$2"
        shift 2
        ;;
      --set-system)
        [[ $# -ge 2 ]] || die "--set-system requires text"
        SET_SYSTEM="$2"
        shift 2
        ;;
      --set-stream)
        [[ $# -ge 2 ]] || die "--set-stream requires on|off"
        case "$2" in
          on|ON|true|1) SET_STREAM="on" ;;
          off|OFF|false|0) SET_STREAM="off" ;;
          *) die "--set-stream must be on or off" ;;
        esac
        shift 2
        ;;
      --show-config)
        SHOW_CONFIG=1
        shift
        ;;
      --reset-config)
        RESET_CONFIG=1
        shift
        ;;
      --model-list)
        model_list; exit 0
        ;;
      -h|--help)
        usage; exit 0
        ;;
      --)
        shift; break
        ;;
      -* )
        die "Unknown option: $1"
        ;;
      * )
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#positional[@]} -gt 0 ]]; then
    # Treat remaining positional args as prompt text (space-joined)
    local rest
    rest="${positional[*]}"
    PROMPT_TEXT+=" ${rest}"
    PROMPT_TEXT="$(echo -n "$PROMPT_TEXT" | sed 's/^ *//')"
  fi
}

validate_args() {
  # Dependencies
  require_cmd curl
  require_cmd jq

  # Colors
  color_setup

  # Load configuration first
  load_config
  
  # Handle configuration commands
  if [[ "$SHOW_CONFIG" -eq 1 ]]; then
    show_config
    exit 0
  fi
  if [[ "$RESET_CONFIG" -eq 1 ]]; then
    reset_config
    exit 0
  fi
  if [[ -n "$SET_MODEL" ]]; then
    MODEL="$SET_MODEL"
    save_config
    echo -ne "${BOLD}${GREEN}Default model set to: ${MODEL}${RESET}\n"
    exit 0
  fi
  if [[ -n "$SET_TEMPERATURE" ]]; then
    TEMPERATURE="$SET_TEMPERATURE"
    save_config
    echo -ne "${BOLD}${GREEN}Default temperature set to: ${TEMPERATURE}${RESET}\n"
    exit 0
  fi
  if [[ -n "$SET_TIMEOUT" ]]; then
    TIMEOUT="$SET_TIMEOUT"
    save_config
    echo -ne "${BOLD}${GREEN}Default timeout set to: ${TIMEOUT}${RESET}\n"
    exit 0
  fi
  if [[ -n "$SET_STREAM" ]]; then
    if [[ "$SET_STREAM" == "on" ]]; then
      STREAM=1
    else
      STREAM=0
    fi
    save_config
    exit 0
  fi
  if [[ -n "$SET_SYSTEM" ]]; then
    SYSTEM_PROMPT="$SET_SYSTEM"
    save_config
    exit 0
  fi
  
  # Cache dir
  ensure_cache_dir

  # Quick admin options
  if [[ "$LIST_CACHE" -eq 1 ]]; then
    list_cache
    exit 0
  fi
  if [[ -n "$REPLAY_KEY" ]]; then
    replay_cache "$REPLAY_KEY"
    exit 0
  fi

  # API key
  if [[ -z "${GROQ_API_KEY:-}" ]]; then
    err "GROQ_API_KEY is not set. Export your API key first."
    echo ""
    echo "  export GROQ_API_KEY=\"sk_...\""
    echo "  bash ${SCRIPT_NAME} --prompt \"Hello\""
    exit 1
  fi

  # Prompt vs file
  if [[ -n "$PROMPT_FILE" && -n "$PROMPT_TEXT" ]]; then
    die "Please provide --prompt or --file, not both."
  fi
  if [[ -n "$PROMPT_FILE" ]]; then
    read_prompt_from_file "$PROMPT_FILE"
  fi
  if [[ -z "$PROMPT_TEXT" ]]; then
    die "No prompt provided. Use --prompt, --file, or positional text."
  fi

  # Temperature number
  is_number "$TEMPERATURE" || die "--temperature must be a number"
  # Optional max tokens
  if [[ -n "$MAX_TOKENS" ]]; then
    is_integer "$MAX_TOKENS" || die "--max-tokens must be an integer"
  fi
  # Timeout integer
  is_integer "$TIMEOUT" || die "--timeout must be an integer"
}

# ------------ API Interaction ------------
send_non_streaming() {
  local payload
  payload=$(build_request_json false)

  local resp tmp_file
  tmp_file=$(mktemp)

  # shellcheck disable=SC2086
  curl -sS \
    -X POST "$API_BASE_URL/chat/completions" \
    -H "Authorization: Bearer ${GROQ_API_KEY}" \
    -H "Content-Type: application/json" \
    --max-time "$TIMEOUT" \
    -d "$payload" \
    -o "$tmp_file"

  if [[ "$RAW_JSON" -eq 1 ]]; then
    cat "$tmp_file"
    echo
  else
    local content
    content=$(jq -r '.choices[0].message.content // empty' "$tmp_file" 2>/dev/null || true)
    if [[ -z "$content" ]]; then
      err "No content in response. Printing raw JSON:"
      cat "$tmp_file"
      echo
    else
      echo -ne "${BOLD}${GREEN}Response:${RESET}\n"
      echo -ne "$content\n"
    fi

    if [[ -n "$SAVE_FILE" ]]; then
      printf "%s\n" "$content" > "$SAVE_FILE"
      info "Saved response to $SAVE_FILE"
    fi

    if [[ "$CACHE_ENABLED" -eq 1 ]]; then
      local key
      key=$(cache_key)
      jq -n \
        --slurpfile request <(canonical_request_json) \
        --slurpfile raw "$tmp_file" \
        --arg text "$content" \
        --arg model "$MODEL" \
        --arg now_iso "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
          key: "'"$key"'",
          request: $request[0],
          response: { text: $text, raw: $raw[0] },
          meta: { created_at_iso: $now_iso, model: $model }
        }' > "$CACHE_DIR/$key.json"
      info "Cached under key: $key"
    fi
  fi

  rm -f "$tmp_file" || true
}

send_streaming() {
  local payload
  payload=$(build_request_json true)

  echo -ne "${BOLD}${GREEN}Response (streaming):${RESET}\n"

  local tmp_text
  tmp_text=$(mktemp)

  # We parse SSE lines: data: {...}, stopping at [DONE]
  # shellcheck disable=SC2086
  curl -sS -N \
    -X POST "$API_BASE_URL/chat/completions" \
    -H "Authorization: Bearer ${GROQ_API_KEY}" \
    -H "Content-Type: application/json" \
    --max-time "$TIMEOUT" \
    -d "$payload" \
  | sed -u 's/^data: //; /^[[:space:]]*$/d' \
  | grep -v '^\[DONE\]$' \
  | jq -r 'try .choices[0].delta.content // empty' \
  | tee -a "$tmp_text"

  echo

  local content
  content=$(<"$tmp_text")

  if [[ -n "$SAVE_FILE" ]]; then
    printf "%s\n" "$content" > "$SAVE_FILE"
    info "Saved response to $SAVE_FILE"
  fi

  if [[ "$CACHE_ENABLED" -eq 1 ]]; then
    local key
    key=$(cache_key)
    jq -n \
      --slurpfile request <(canonical_request_json) \
      --arg text "$content" \
      --arg model "$MODEL" \
      --arg now_iso "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{
        key: "'"$key"'",
        request: $request[0],
        response: { text: $text },
        meta: { created_at_iso: $now_iso, model: $model }
      }' > "$CACHE_DIR/$key.json"
    info "Cached under key: $key"
  fi

  rm -f "$tmp_text" || true
}

# ------------ Main ------------
main() {
  parse_args "$@"
  validate_args

  # memory integration: locate memory.sh
  if [[ -x "$(dirname "$0")/memory.sh" ]]; then
    MEM_SCRIPT_PATH="$(dirname "$0")/memory.sh"
  elif [[ -x "/usr/local/lib/terminai/memory.sh" ]]; then
    MEM_SCRIPT_PATH="/usr/local/lib/terminai/memory.sh"
  elif [[ -x "/usr/lib/terminai/memory.sh" ]]; then
    MEM_SCRIPT_PATH="/usr/lib/terminai/memory.sh"
  else
    MEM_SCRIPT_PATH=""
  fi

  # Clear memory if requested
  if [[ "$CLEAR_MEMORY" -eq 1 && -n "$MEM_SCRIPT_PATH" ]]; then
    "$MEM_SCRIPT_PATH" clear || true
    info "Cleared conversation memory."
  fi

  # Build effective prompt with memory context if available
  PROMPT_EFFECTIVE="$PROMPT_TEXT"
  if [[ -n "$MEM_SCRIPT_PATH" && "$USE_MEMORY" -eq 1 ]]; then
    local preface
    preface=""
    if [[ -n "$SYSTEM_PROMPT" ]]; then
      preface="System: ${SYSTEM_PROMPT}\n"
    fi
    convo=$("$MEM_SCRIPT_PATH" join --max 8 --with "$PROMPT_TEXT" 2>/dev/null || true)
    if [[ -n "$convo" ]]; then
      PROMPT_EFFECTIVE="${preface}${convo}"
    fi
  fi

  echo -ne "${BOLD}${BLUE}Model:${RESET} ${MODEL}\n"
  if [[ -n "$SYSTEM_PROMPT" ]]; then
    echo -ne "${BOLD}${BLUE}System:${RESET} ${SYSTEM_PROMPT}\n"
  fi
  # Do not echo the full prompt for privacy/UX
  echo -ne "${BOLD}${BLUE}Prompt received.${RESET}\n\n"
  if [[ "$STREAM" -eq 1 ]]; then
    info "Streaming is enabled"
  fi

  if [[ "$STREAM" -eq 1 ]]; then
    send_streaming
  else
    send_non_streaming
  fi

  # Append to memory store for future context
  if [[ -n "$MEM_SCRIPT_PATH" ]]; then
    "$MEM_SCRIPT_PATH" append --prompt "$PROMPT_TEXT" || true
  fi
}

main "$@"


