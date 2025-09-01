## Groq-Terminai — Groq API Terminal CLI

Groq-Terminai is a fast, ergonomic Bash CLI for Groq's OpenAI-compatible API. It supports prompts from flags or files, model selection, streaming, caching, and a lightweight conversation memory layer.

### Highlights
- Simple: single portable Bash script (`groq_cli.sh`) driven by `curl` + `jq`
- Ergonomic flags for model, temperature, max tokens, stop sequences, system prompt
- Streaming or non-streaming responses
- Persistent defaults (model, temperature, timeout, stream) via config
- Model discovery from Groq (`--model-list`) grouped by Production vs Preview
- Caching of responses and replay
- Optional conversation memory (can be disabled)

---

## Requirements
- Linux or macOS
- bash, curl, jq
- Groq API key in `GROQ_API_KEY`

Install dependencies (Ubuntu/Debian):
```bash
sudo apt update && sudo apt install -y curl jq
```

---

## Installation

### Option A: System-wide (recommended)
```bash
cd /home/ai/Documents/TerminAI
sudo bash install.sh            # copies a binary named `groq-terminai` to /usr/local/bin
```
Or install as a symlink:
```bash
sudo bash install.sh --mode symlink
```

### Option B: User-local
```bash
bash install.sh --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"   # add to your shell profile
```

### Option C: Manual link
```bash
sudo ln -sf "$(pwd)/groq_cli.sh" /usr/local/bin/groq-terminai
```

### Uninstall
```bash
sudo bash uninstall.sh
```

---

## Configure
Set your API key:
```bash
export GROQ_API_KEY="sk_..."
```

Optional: override endpoint (defaults to `https://api.groq.com/openai/v1`):
```bash
export API_BASE_URL="https://api.groq.com/openai/v1"
```

Persistent defaults are stored in config files:
- User: `~/.config/groq-cli/config.json`
- Global: `/etc/groq-cli/defaults.json` (if present)

Set defaults via flags (persisted to user config):
```bash
groq-terminai --set-model llama-3.1-70b-versatile
groq-terminai --set-temperature 0.7
groq-terminai --set-timeout 300
groq-terminai --set-stream off   # streaming default is OFF
groq-terminai --set-system "You are concise and pragmatic."
groq-terminai --show-config
```

---

## Quick Start
```bash
groq-terminai --prompt "Explain quantum computing simply."
groq-terminai --file prompt.txt
groq-terminai --model-list
```

You can also pass the prompt positionally:
```bash
groq-terminai what are you doing right now
```

---

## Usage (common flags)
```bash
groq-terminai [--prompt TEXT | --file FILE]
         [--model NAME]
         [--temperature VAL]
         [--max-tokens N]
         [--stop "a,b,c"]
         [--system "text"]
         [--stream | --no-stream]
         [--save out.txt] [--json]
         [--no-color] [--timeout SECONDS]
         [--no-memory] [--clear]
```

- **--prompt TEXT**: provide the prompt inline
- **--file FILE**: read a prompt from a file
- **--model NAME**: select the Groq model (see `--model-list`)
- **--temperature VAL**: randomness (0.0–2.0)
- **--max-tokens N**: cap response length (optional)
- **--stop "a,b,c"**: comma-separated stop sequences
- **--system TEXT**: optional system message
- **--stream**: stream tokens live; **--no-stream** for non-streaming
- **--save FILE**: save response text to a file
- **--json**: print raw JSON (non-streaming only)
- **--no-memory**: ignore conversation memory for this call
- **--clear**: clear conversation memory buffer
- **--model-list**: fetch and display models grouped by Production/Preview

Configuration flags (persist defaults):
```bash
groq-terminai --set-model NAME
groq-terminai --set-temperature VAL
groq-terminai --set-timeout SECONDS
groq-terminai --set-stream on|off
groq-terminai --set-system "text"
groq-terminai --show-config
groq-terminai --reset-config
```

Notes:
- Streaming is OFF by default. Enable per-call with `--stream` or persist with `--set-stream on`.
- The CLI does not echo your full prompt for privacy; it only confirms a prompt was received.

---

## Conversation Memory (optional)
TerminAI stores a rolling conversation history (user + assistant turns) and can prepend the transcript to your new prompt, providing context.

- Stored at: `~/.local/state/groq-cli/memory.json`
- Disable per call: `--no-memory`
- Clear memory: `--clear`
- If a default system message is set via `--set-system`, it is prefixed to the concatenated transcript used for context.

Examples:
```bash
groq-terminai --prompt "Outline a Python script to parse logs"
groq-terminai --prompt "Now add unit tests"           # will include the previous conversation by default
groq-terminai --no-memory --prompt "Ignore prior and summarize log formats"
groq-terminai --clear  # starts a fresh memory buffer
```

---

## Models
Discover models and see which are Production vs Preview:
```bash
groq-terminai --model-list
```
The current default model is marked with an asterisk. You can set a new default model with `--set-model`.

---

## Caching
TerminAI caches non-stream and stream results in:
- `~/.cache/groq-cli/`

Commands:
```bash
groq-terminai --list-cache
groq-terminai --replay <cache_key>
groq-terminai --no-cache --prompt "..."    # disable cache for this call
```

---

## Examples
```bash
# Non-streaming with parameters
groq-terminai --prompt "Explain trees vs graphs" --model llama-3.1-70b-versatile --temperature 0.3 --max-tokens 300

# Streaming
groq-terminai --stream --prompt "Write a haiku about CLIs"

# Read prompt from file and save output
groq-terminai --file question.txt --save answer.txt

# Provide a system message
groq-terminai --system "You are concise and pragmatic" --prompt "Refactor this shell script"
```

---

## Troubleshooting

- **Missing API key**: set `export GROQ_API_KEY="sk_..."`.
- **Missing jq**: `sudo apt install -y jq` (Debian/Ubuntu) or `brew install jq` (macOS).
- **Tokens printing on new lines during streaming**:
  - Ensure the installed `groq-terminai` uses `jq -rj` in the streaming path:
    ```bash
    grep -n "jq -rj" $(which groq-terminai)
    ```
  - If not, reinstall/symlink to the latest script and `hash -r` to clear the shell cache.
  - Try non-streaming: `groq-terminai --no-stream --prompt "..."`.
- **403/401 errors**: verify your API key and model permissions.
- **Terminal soft-wrap**: pipe to `less -S` to avoid soft wrapping.

---

## Packaging

Debian/Ubuntu maintainer scripts are under `debian/` (postinst/prerm/postrm). Arch PKGBUILD is under `arch/`.

Builds are out of scope here, but you can use the provided files as a starting point for packaging.

---

## Uninstall & Cleanup
```bash
sudo bash uninstall.sh
rm -rf ~/.config/groq-cli ~/.cache/groq-cli ~/.local/state/groq-cli
```

---

## Security
- Keep your `GROQ_API_KEY` secret (store in your shell profile or a credential manager).
- Avoid committing keys to source control.

---

## License
MIT-like usage intended. Use at your own discretion.


