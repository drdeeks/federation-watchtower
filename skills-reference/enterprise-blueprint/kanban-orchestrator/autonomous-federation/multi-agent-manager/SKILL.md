---
name: multi-agent-manager
description: Build and maintain bash scripts for managing multi-agent systems with OpenClaw gateway + Hermes cognitive engine. Covers agent profile management, skill linking, config generation, and safe operations.
version: 1.2.0
author: Hermes Agent
metadata:
  hermes:
    tags: [devops, multi-agent, openclaw, hermes, bash, infrastructure]
    related_skills: [agent-bootstrap-manager, skill-scanner, agent-workspace-enforcement]
---

# Multi-Agent Manager

Build bash toolkits for managing OpenClaw + Hermes multi-agent systems.

## When to Use

- Setting up multiple agents with OpenClaw as gateway and Hermes as brain
- Managing agent profiles, configs, and skills across a fleet
- Creating safe automation scripts that never overwrite without backup

## Architecture

```
OpenClaw = gateway, routing, Telegram bots, workspace (body)
Hermes   = cognitive engine, memory, skills, tool use (brain)
Scripts  = bridge between them (this skill)
```

Agent directory: `~/.openclaw/agents/<agent>/` (OpenClaw mode) or `~/.hermes/profiles/<agent>/` (Hermes mode).

## Key Patterns

### 1. Global flag parsing (position-independent)

Parse all flags before any command dispatch. Collect non-flag args separately.
NEVER use `shift` inside the flag loop — it changes indices mid-iteration.

```bash
DRY_RUN=false; FORCE=false; OPENCLAW_MODE=false; NO_CONFIRM=false
_args=()
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        --force|-f)   FORCE=true ;;
        --openclaw|-o) OPENCLAW_MODE=true ;;
        --yes|-y)     NO_CONFIRM=true ;;
        *)            _args+=("$arg") ;;
    esac
done
set -- "${_args[@]}"
```

### 2. Dry-run wrapper for all mutating commands

```bash
run() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]${NC} $*"
        return 0
    fi
    "$@"
}

# Usage: run mkdir -p "$dir", run rm -f "$file", run ln -sf "$src" "$dst"
```

Heredoc file writes need explicit guards:
```bash
if [ "$DRY_RUN" = false ]; then
    { echo "..."; } > "$file"
else
    echo "[dry-run] Write $file"
fi
```

### 3. Full directory backup (not just files)

```bash
backup_file() {
    local src="$1" backup_dir="$2"
    [ -e "$src" ] || [ -L "$src" ] || return 0
    run mkdir -p "$backup_dir"
    local fname="$(basename "$src")" ts="$(timestamp)"
    local dest="${backup_dir}/${fname}.${ts}.bak"

    if [ -d "$src" ] && [ ! -L "$src" ]; then
        # rsync excludes node_modules, __pycache__, .git
        # cp -a fallback preserves hidden files (.env, .secrets/)
        if command -v rsync &>/dev/null; then
            run rsync -a --exclude='node_modules' --exclude='__pycache__' --exclude='.git' "$src/" "$dest/"
        else
            run mkdir -p "$dest"
            run cp -a "$src/." "$dest/"
            run find "$dest" -type d \( -name 'node_modules' -o -name '__pycache__' -o -name '.git' \) -exec rm -rf {} + 2>/dev/null
        fi
    elif [ -L "$src" ]; then
        run cp -P "$src" "$dest"
    else
        run cp "$src" "$dest"
    fi
}
```

### 4. Agent discovery (deduplicated across sources)

```bash
declare -A seen_agents
local agent_list=()

for source_dir in "$OPENCLAW_AGENTS" "$PROFILES_ROOT"; do
    [ -d "$source_dir" ] || continue
    for d in "$source_dir"/*/; do
        [ -d "$d" ] || continue
        local name="$(basename "$d")"
        [ "$name" = "templates" ] && continue
        if [ -z "${seen_agents[$name]:-}" ]; then
            seen_agents["$name"]=1
            agent_list+=("$name")
        fi
    done
done
```

ALWAYS check `seen_agents` before adding. Missing this check = duplicate processing.

### 5. Incomplete config detection (not just missing)

Don't check `[ ! -f "$file" ]` alone. Check for REQUIRED content:

```bash
# .env: needs actual bot token, not just a stub
local env_has_token=false
if [ -f "$ENV_FILE" ]; then
    grep -qE "^TELEGRAM_BOT_TOKEN=.{10,}" "$ENV_FILE" 2>/dev/null && env_has_token=true
fi
if [ ! -f "$ENV_FILE" ] || [ "$env_has_token" = false ]; then
    # regenerate
fi

# config.yaml: needs model section
local conf_has_model=false
if [ -f "$CONF_FILE" ]; then
    grep -q "^model:" "$CONF_FILE" 2>/dev/null && conf_has_model=true
fi
if [ ! -f "$CONF_FILE" ] || [ "$conf_has_model" = false ]; then
    # regenerate
fi
```

### 6. Safe prompt with --yes bypass

```bash
safe_prompt_yn() {
    if [ "$NO_CONFIRM" = true ]; then return 0; fi
    prompt_yn "$@"
}
```

### 7. OpenClaw mode (no symlinks)

In OpenClaw mode, config/env live directly in agent dir. Skip symlink creation to avoid self-referencing links:

```bash
if [ "$OPENCLAW_MODE" != true ]; then
    _safe_link "$CONF_FILE" "${HH}/config.yaml" "$BK_DIR"
    _safe_link "$ENV_FILE" "${HH}/.env" "$BK_DIR"
fi
```

### 8. Identity file copy from profiles

During sync, copy SOUL.md etc. from `~/.hermes/profiles/<agent>/` into OpenClaw dir if missing:

```bash
if [ "$OPENCLAW_MODE" = true ]; then
    local profile_src="${PROFILES_ROOT}/${agent}"
    if [ -d "$profile_src" ]; then
        for f in SOUL.md USER.md MEMORY.md TOOLS.md AGENTS.md HEARTBEAT.md IDENTITY.md README.md; do
            if [ -f "${profile_src}/${f}" ] && [ ! -f "${HH}/${f}" ]; then
                run cp "${profile_src}/${f}" "${HH}/${f}"
            elif [ -f "${profile_src}/${f}" ] && [ -f "${HH}/${f}" ]; then
                if ! diff -q "${profile_src}/${f}" "${HH}/${f}" &>/dev/null; then
                    warn "${f} differs: profiles vs OpenClaw (OpenClaw kept)"
                fi
            fi
        done
    fi
fi
```

### 9. Comprehensive .env generation (not stubs)

Never generate `# TODO` stubs. Generate full structured files with all providers
documented, clear instructions, and exact variable names:

```bash
cat << ENVEOF
# Agent: ${agent}
# REQUIRED: At least one provider key and TELEGRAM_BOT_TOKEN
#
# ── Telegram ──
# Get your token from @BotFather. Format: 123456789:ABCdefGHI...
#
# TELEGRAM_BOT_TOKEN=<your-bot-token-from-botfather>
TELEGRAM_ALLOWED_USERS=6537959619
TELEGRAM_HOME_CHANNEL=6537959619

# ── Model Provider (uncomment ONE) ──
# --- Nous Portal ---
# NOUS_API_KEY=<your-nous-key>
# --- OpenRouter ---
# OPENROUTER_API_KEY=<your-openrouter-key>
# --- OpenAI ---
# OPENAI_API_KEY=sk-<your-key>
# --- Local Ollama (no key needed) ---
# OLLAMA_API_KEY=ollama
ENVEOF
```

User should uncomment ONE provider block. Each shows the exact key variable name.

### 10. Comprehensive config.yaml generation

Generate full config matching the working reference, with commented alternatives:

```bash
cat << CONFEOF
model:
  default: xiaomi/mimo-v2-pro
  provider: nous
  base_url: https://inference-api.nousresearch.com/v1
  api_mode: chat_completions
# --- For OpenRouter: ---
# model:
#   default: meta-llama/llama-3.1-70b-instruct
#   provider: openrouter
#   base_url: https://openrouter.ai/api/v1

providers: {}
fallback_providers: []
toolsets: [hermes-cli]
agent:
  max_turns: 60
  gateway_timeout: 1800
terminal:
  backend: local
  cwd: ${HH}
memory:
  memory_enabled: true
  memory_char_limit: 2200
compression:
  enabled: true
  threshold: 0.77
  target_ratio: 0.2
_config_version: 14
CONFEOF
```

Include all sections: agent, terminal, memory, compression, skills, approvals,
security, logging, session_reset, display. User can change active provider by
swapping which model block is uncommented.

### 11. config command that always outputs JSON

The `config` command generates openclaw.json entries. It must ALWAYS output
JSON even when no tokens are found:

```bash
cmd_config() {
    # Discover agents (dedup pattern)
    # Collect tokens from .env files
    # ALWAYS output JSON — use placeholders when no token:
    local token="${bot_tokens[$agent]:-YOUR_${agent^^}_BOT_TOKEN}"
    
    # Only prompt if interactive:
    if [ "$DRY_RUN" = false ] && [ -t 0 ]; then
        read -rsp "Bot token for ${agent}: " input
    fi
    
    # Output three blocks: agents.list, channels.telegram.accounts, bindings
    echo '{ "agents": { "list": [...] }, ... }'
}
```

The `[ -t 0 ]` check prevents blocking in pipes/non-interactive mode.

### 12. Identity file copy from profiles

During sync in OpenClaw mode, copy identity files from `~/.hermes/profiles/<agent>/`:

```bash
if [ "$OPENCLAW_MODE" = true ]; then
    local profile_src="${PROFILES_ROOT}/${agent}"
    if [ -d "$profile_src" ]; then
        for f in SOUL.md USER.md MEMORY.md TOOLS.md AGENTS.md HEARTBEAT.md; do
            if [ -f "${profile_src}/${f}" ] && [ ! -f "${HH}/${f}" ]; then
                run cp "${profile_src}/${f}" "${HH}/${f}"
            elif [ -f "${profile_src}/${f}" ] && [ -f "${HH}/${f}" ]; then
                if ! diff -q "${profile_src}/${f}" "${HH}/${f}" &>/dev/null; then
                    warn "${f} differs: profiles vs OpenClaw (OpenClaw kept)"
                fi
            fi
        done
    fi
fi
```

## Pitfalls

- **Self-referencing symlinks**: When `CONF_FILE` == `${HH}/config.yaml` (same path), `_safe_link` creates a symlink to itself. Guard with `if [ \"$OPENCLAW_MODE\" != true ]`.
- **Duplicate agent processing**: Multiple discovery sources (OpenClaw, profiles, legacy, systemd) can find the same agent. Always deduplicate with `seen_agents` associative array.
- **Stub files preserved**: A file with `# TODO` content is non-empty, so `[ ! -s "$file" ]` skips it. Must check for actual required content.
- **`run` with heredocs**: `run cat > file << EOF` doesn't work — `run` passes `>` and `file` as args. Use `if [ "$DRY_RUN" = false ]; then { ... } > file; fi` instead.
- **`set -euo pipefail`**: Causes script to exit on any error. Wrap uncertain operations with `|| true` or `2>/dev/null`.
- **ARGUMENT SHIFT**: When parsing global flags, use `_args` array + `set -- "${_args[@]}"` instead of `shift` inside the loop (shift changes indices during iteration).

## Commands Pattern

Standard command set for agent management:

| Command | Mutating? | Prompt? | Backup? |
|---------|-----------|---------|---------|
| init | Yes | Yes | Full dir |
| scan | No | No | N/A |
| sync | Yes | Yes | Full dir |
| config | No | Token prompt | N/A |
| link | Yes | Yes | Individual |
| unlink | Yes | Yes | Individual |
| repair | Yes | Yes | Full dir |
| list | No | No | N/A |
| delete | Yes | Double confirm | Full dir |

### 9. Generating openclaw.json entries

A `config` command that discovers all agents and outputs paste-ready JSON:

```bash
cmd_config() {
    # Discover agents (same dedup pattern as scan/sync)
    # Read TELEGRAM_BOT_TOKEN from each .env
    # Output three JSON blocks: agents.list, channels.telegram.accounts, bindings
    
    # Key: always output JSON even if no tokens found
    # Use placeholders: YOUR_${agent^^}_BOT_TOKEN
    # Only prompt for tokens if interactive:
    if [ -t 0 ]; then
        read -rsp "Bot token for ${agent}: " input
    fi
}
```

The `[ -t 0 ]` check prevents blocking when stdin isn't a terminal (pipes, cron, scripts).

### 10. Identity file sync from profiles

During sync in OpenClaw mode, copy identity files from `~/.hermes/profiles/<agent>/`:

```bash
if [ "$OPENCLAW_MODE" = true ]; then
    local profile_src="${PROFILES_ROOT}/${agent}"
    if [ -d "$profile_src" ]; then
        for f in SOUL.md USER.md MEMORY.md TOOLS.md AGENTS.md HEARTBEAT.md IDENTITY.md README.md; do
            if [ -f "${profile_src}/${f}" ] && [ ! -f "${HH}/${f}" ]; then
                run cp "${profile_src}/${f}" "${HH}/${f}"
            elif [ -f "${profile_src}/${f}" ] && [ -f "${HH}/${f}" ]; then
                if ! diff -q "${profile_src}/${f}" "${HH}/${f}" &>/dev/null; then
                    warn "${f} differs: profiles vs OpenClaw (OpenClaw kept)"
                fi
            fi
        done
    fi
fi
```

Warn when files differ but keep the OpenClaw version (it's the canonical location).

## Pitfalls (additions)

- **Corrupted grep patterns from token redaction**: The terminal tool masks tokens as `***`. When you copy-paste script output containing `grep "^TELEGRAM_BOT_TOKEN=***`, the `***` becomes literal in the script and breaks the grep. Always use `grep -E "^TELEGRAM_BOT_TOKEN="` WITHOUT any value match after `=`. Verify with `xxd` hex dump — the display may show `***` but the actual bytes might be correct (or not). The safest pattern: `grep -E "^TELEGRAM_BOT_TOKEN=" | cut -d= -f2-`.
- **`--yes` doesn't bypass raw `read`**: `safe_prompt_yn` checks `NO_CONFIRM`, but raw `read -rsp` in config commands doesn't. Add `[ -t 0 ]` check to skip prompts in non-interactive mode.
- **Config command silent exit**: If the token loop uses `read` without `[ -t 0 ]`, piped/non-interactive invocations block or exit before reaching the output section. Always guard interactive reads.

## OpenClaw + Hermes Integration Steps

The canonical setup flow for a fresh system:

```bash
# 1. Verify core skills exist
ls ~/.hermes/skills/ | wc -l

# 2. Create identity files in profiles if not already there
mkdir -p ~/.hermes/profiles/{agent1,agent2}

# 3. Preview what sync will do
./agent-bootstrap.sh --dry-run --openclaw sync

# 4. Create agent dirs, copy identity, generate full config.yaml + .env
./agent-bootstrap.sh --openclaw --yes sync

# 5. Fill in bot tokens if not auto-imported from legacy
grep "your-bot-token" ~/.openclaw/agents/*/.env

# 6. Link core skills into each agent
./skill-scanner.sh --openclaw --yes sync

# 7. Generate openclaw.json entries (always outputs JSON)
./agent-bootstrap.sh config

# 8. Paste into openclaw.json
nano ~/.openclaw/openclaw.json

# 9. Restart gateway
sudo systemctl restart openclaw-gateway.service

# 10. Verify
./agent-bootstrap.sh --openclaw scan
```

Key: sync auto-generates FULL configs (not stubs). .env has all providers documented
with exact variable names. config.yaml has all sections with commented alternatives.
The only manual step is uncommenting the right provider and adding bot tokens.

## Test Checklist

Before releasing:

1. `bash -n script.sh` — syntax check
2. `--dry-run` on every mutating command — no files created
3. System state unchanged after all dry-runs
4. Error handling: no command, unknown command, missing args, missing agent
5. Dedup: each agent processed exactly once (check `seen_agents` in ALL discovery loops)
6. Incomplete configs regenerated, valid ones preserved (check for `model:` and `TELEGRAM_BOT_TOKEN=.{10,}`)
7. `--yes` skips all prompts (both `safe_prompt_yn` and raw `read`)
8. Backup created before every mutation
9. Hidden files included in backups, node_modules excluded
10. `config` command outputs JSON even with no tokens, even piped/non-interactively
11. No self-referencing symlinks in OpenClaw mode
12. Grep patterns don't contain literal `***` from redaction — verify with `xxd`
13. Generated .env has all providers documented with exact variable names (no "TODO")
14. Generated config.yaml has all sections (model, terminal, memory, compression, etc.)
15. `[ -t 0 ]` guards all raw `read` calls to prevent blocking in pipes
