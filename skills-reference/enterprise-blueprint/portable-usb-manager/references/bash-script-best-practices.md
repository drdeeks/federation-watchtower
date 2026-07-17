# Bash Script Best Practices & Troubleshooting

> Collected from Hemlock Agent Framework integration session — consolidated troubleshooting for bash script robustness, terminal input handling, and idempotent sourcing.

---

## Terminal Input Handling Best Practices

### The Problem
Complex `PROMPT_COMMAND` + dynamic `PS1` + functions outputting to stdout = broken terminal state.
Symptoms: "stuck" prompts, inability to backspace past cursor, paste eating characters, Ctrl+C needed to escape.

### The Fix: Simplify Prompt System

**Bad:** Dynamic `PROMPT_COMMAND` rebuilding `PS1` with function calls that echo to stdout
```bash
# BAD - causes terminal issues
_exit_code() { [ $? -ne 0 ] && echo -e " ${RED}[${code}]${NC}"; }
PROMPT_COMMAND='PS1="${BOLD}${BLUE}\u${NC}@${CYAN}\h${NC}:${GREEN}\w${YELLOW}$(_git_branch)${NC}$(_exit_code)\n${CYAN}▶${NC} "'
```

**Good:** Static `PS1` with `printf` in functions (no stdout pollution)
```bash
# GOOD - static prompt, printf in functions
shopt -s expand_aliases  # enable aliases in non-interactive shells

_git_branch() {
    git branch 2>/dev/null | awk '/\*/{print " ("$2")"}'
}

_exit_code() {
    local code=$?
    [ $code -ne 0 ] && printf " \[\033[0;31m\][%d]\033[0m" $code
}

# Static prompt - no PROMPT_COMMAND rebuilding
PS1='\[\033[1m\]\[\033[0;34m\]\u\[\033[0m\]@\[\033[0;36m\]\h\[\033[0m\]:\[\033[0;32m\]\w\[\033[1;33m\]$(_git_branch)\[\033[0m\] $(_exit_code)\n\[\033[0;36m\]▶\[\033[0m\] '
```

### Input Handling: The Right Way

**Bad:** `read -p` with escape sequences
```bash
read -p "$(echo -e \"${YELLOW}Prompt: ${NC}\")" var
```

**Good:** Separate prompt from read, use readline
```bash
echo -ne "${YELLOW}Prompt: ${NC}"
read -e -r var  # -e enables readline (history, arrows, paste)
```

**Always:**
```bash
shopt -s expand_aliases  # at top of script for alias expansion in non-interactive shells
echo -ne "${YELLOW}Prompt: ${NC}"  # -n no newline, -e interprets escapes
read -e -r var              # -e readline, -r raw (no backslash escaping)
```

---

## Idempotent Script Sourcing

### The Problem
`readonly` variables throw "readonly variable" error on re-source.

**Bad:**
```bash
readonly NC='\033[0m'  # fails on 2nd source
```

**Good: Idempotent parameter expansion**
```bash
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}"
: "${CYAN:=\033[0;36m}"
: "${WHITE:=\033[1;37m}"
: "${DIM:=\033[2m}"
: "${BOLD:=\033[1m}"
: "${NC:=\033[0m}"
```
The `: "${VAR:=value}"` syntax only sets if unset, safe for multiple sourced.

---

## CLI Argument Parsing

### The Problem
Commands fall through to interactive menu instead of exiting.

**Fix:** Explicit `exit 0` after each command
```bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list|-l)
            init_alias_file
            list_aliases "${2:-table}"
            exit 0  # <-- CRITICAL
            ;;
        --add|-a)
            init_alias_file
            add_alias "$2" "$3" "${4:-}"
            exit 0
            ;;
        # ... all commands end with exit 0
    esac
done

# Only run interactive if NO args
[[ $# -eq 0 ]] && interactive_menu
```

---

## Quote Escaping in Bash

### The Problem
Nested quotes in `bash -c` with `echo` break on special characters.

**Bad:**
```bash
run_or_dry bash -c "echo \"$line\" >> \"${ALIAS_FILE}\""
```

**Good: Use `printf` with proper escaping**
```bash
run_or_dry bash -c "printf '%s\n' \"$line\" >> \"${ALIAS_FILE}\""
```

**Even better: Use `printf` with explicit format**
```bash
run_or_dry bash -c "printf \"%s\n\" \"$line\" >> \"${ALIAS_FILE}\""
```

---

## Tilde Expansion

### The Problem
`~/.bashrc` not expanded when passed as argument.

**Fix: Parameter expansion at use site**
```bash
source_file="${1:-$HOME/.bashrc}"
source_file="${source_file/#~/$HOME}"  # expands ~ to $HOME
```

---

## Heredoc Delimiter Safety

### The Problem
`EOF` delimiter conflicts with content containing "EOF".

**Fix: Unique, descriptive delimiters**
```bash
cat > file << 'INFOEOF'  # quoted = no expansion
content
INFOEOF

# vs
cat > file << 'EXPEOF'
export content
EXPEOF
```

---

## Robust Script Sourcing Pattern

### Complete Template
```bash
#!/usr/bin/env bash
set -euo pipefail

# Idempotent color constants
: "${RED:=\033[0;31m}"; : "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"; : "${BLUE:=\033[0;34m}"
: "${CYAN:=\033[0;36m}"; : "${NC:=\033[0m}"
: "${BOLD:=\033[1m}"; : "${DIM:=\033[2m}"

log()   { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Enable readline for all reads
shopt -s expand_aliases

# ... rest of script
```

---

## Quick Reference Card

| Issue | Solution |
|-------|----------|
| `readonly` error on re-source | `: "${VAR:=value}"` |
| Prompt stuck / can't backspace | Static PS1, `_exit_code` uses `printf`, simple `PROMPT_COMMAND="history -a"` |
| Paste eats chars / arrow keys broken | `read -e -r` + `echo -ne` prompts |
| Ctrl+C to exit prompt | Separate prompt from read: `echo -ne "prompt"; read -e -r var` |
| Tilde not expanded | `${var/#~/$HOME}` |
| CLI falls to menu | `exit 0` after each command case |
| Nested quote hell | `printf "%s\n" "$var"` not `echo "$var"` |
| Heredoc EOF conflict | Unique delimiters: `INFOEOF`, `EXPEOF` |
| Script re-source fails | `: "${VAR:=value}"` instead of `readonly` |
| Colors as readonly | Remove `readonly`, use parameter expansion |

---

## Debugging Checklist

When terminal acts up:
1. `shopt -s expand_aliases` at top of script
2. Check `_exit_code()` uses `printf`, not `echo -e`
3. `PROMPT_COMMAND` only does `history -a` (no PS1 rebuild)
4. `PS1` is static string with `$_git_branch` and `$(_exit_code)`
5. All `read` use `read -e -r`
6. Prompts use `echo -ne` + separate `read`
7. All CLI commands end with `exit 0`
8. `set -euo pipefail` at top
9. Colors use parameter expansion, not `readonly`
10. Tilde expansion at point of use

---

*Last updated: 2026-06-15 — Hemlock Agent Framework integration session*