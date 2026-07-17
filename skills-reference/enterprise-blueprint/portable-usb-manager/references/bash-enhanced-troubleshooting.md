# Bash Enhanced Script Troubleshooting Guide

## Overview
This document captures the debugging path and fixes applied to `bash_enhanced.sh` during the Hemlock integration. These issues are common when working with complex bash scripts containing heredocs, PS1 prompts, and color codes.

---

## Issue 1: Stray EOF Delimiter at File End

### Symptoms
```
/tmp/hemlock-minimal/usb-compute-automation/bash_enhanced.sh: line 142: EOF: command not found
```

### Root Cause
The script used multiple heredoc delimiters (`INFOEOF`, `HELPEOF`, `EXPEOF`) but had a stray `EOF` at the very end of the file (line 142). Bash tried to execute this as a command instead of treating it as a heredoc terminator.

### Fix
1. Use unique heredoc delimiters for each heredoc block:
   - `HELPEOF` for syshelp heredoc
   - `INFOEOF` for sysinfo heredoc
   - `EXPEOF` for exportinfo heredoc
2. Remove any stray `EOF` at the end of the file
3. Ensure every heredoc uses `<<'DELIMITER'` (quoted) to prevent variable expansion within the heredoc

### Prevention
- Always use unique, descriptive heredoc delimiters
- Never leave bare `EOF` at file end
- Use `bash -n` to validate syntax before sourcing

---

## Issue 2: PS1 Prompt Command Substitution Not Evaluating

### Symptoms
Prompt shows literal `_git_branch` and `_exit_code` instead of executing them:
```
drdeek@DrDeeks-ThinkPad:~
▶ _git_branch
drdeek@DrDeeks-ThinkPad:~
▶ _exit_code
```

### Root Cause
The PS1 was defined with single quotes, preventing command substitution:
```bash
# WRONG - single quotes prevent expansion
PS1='${BOLD}${BLUE}\u${NC}@${CYAN}\h${NC}:${GREEN}\w${YELLOW}$(_git_branch)${NC}$(_exit_code)\n${CYAN}▶${NC} '
```

### Fix
Use `PROMPT_COMMAND` with a double-quoted string to enable dynamic evaluation:
```bash
# CORRECT - PROMPT_COMMAND evaluates on each prompt
_git_branch() {
    git branch 2>/dev/null | awk '/\*/{print " ("$2")"}'
}

_exit_code() {
    local code=$?
    [ $code -ne 0 ] && echo -e " ${RED}[${code}]${NC}"
}

PROMPT_COMMAND='PS1="${BOLD}${BLUE}\u${NC}@${CYAN}\h${NC}:${GREEN}\w${YELLOW}$(_git_branch)${NC}$(_exit_code)\n${CYAN}▶${NC} "'
```

### Key Points
- Define functions (`_git_branch`, `_exit_code`) before `PROMPT_COMMAND`
- Use double quotes around the entire PS1 string in PROMPT_COMMAND
- Escape `$` for variables you want evaluated later (`\u`, `\h`, `\w`) but NOT for function calls (`$(_git_branch)`)
- Use `bash -n` to validate syntax

---

## Issue 3: Heredoc Delimiter Conflicts

### Symptoms
Multiple heredocs using the same delimiter (`EOF`) caused parsing errors.

### Fix
Use unique, descriptive delimiters per heredoc:
```bash
# Help heredoc
cat <<'HELPEOF'
...
HELPEOF

# System info heredoc
cat <<'INFOEOF'
...
INFOEOF

# Export info heredoc
cat <<'EXPEOF'
...
EXPEOF
```

### Best Practice
Always suffix `EOF` with a descriptive prefix matching the section:
- `HELPEOF` → Help text
- `INFOEOF` → System info
- `EXPEOF` → Export info
- `SYSEOF` → System resources
- `DISKEOF` → Disk info

---

## Issue 4: Function Order Dependency

### Problem
Functions referenced in `PROMPT_COMMAND` must be defined before `PROMPT_COMMAND` is set.

### Solution
Order in file:
1. Color constants
2. Helper functions (`_git_branch`, `_exit_code`, `_esm_banner`)
3. `PROMPT_COMMAND` assignment
4. Main functions (`syshelp`, `sysinfo`, etc.)
5. Aliases and completion

---

## Validation Checklist

Before committing changes to `bash_enhanced.sh`:
- [ ] `bash -n bash_enhanced.sh` passes (syntax check)
- [ ] `source bash_enhanced.sh` loads without errors
- [ ] `syshelp` displays correctly
- [ ] `sysinfo` shows system info
- [ ] Prompt shows git branch and exit code dynamically
- [ ] No stray `EOF` at file end
- [ ] All heredocs use unique, quoted delimiters
- [ ] Functions defined before use in PROMPT_COMMAND

---

## Related Files
- `references/phase-7-8-9-integration.md` — PHASE-7/8/9 integration details
- `references/testing-framework.md` — Testing framework with safety wrapper
- `references/setup-wizard-hemlock.md` — Hemlock deployment via setup wizard

---

## Version History
| Date | Version | Changes |
|------|---------|---------|
| 2026-06-14 | 1.0 | Initial troubleshooting guide for bash_enhanced.sh fixes |