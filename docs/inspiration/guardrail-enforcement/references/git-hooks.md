# Git Hooks Reference

Git integration is what turns the signed loop log from an advisory record into an
enforced gate: with hooks installed, a commit is rejected unless the log verifies
and carries a fresh PASS entry. Hooks are installed by the tool
(`install_hooks.py`), never shipped inside the skill archive.

## Installed Hooks

| Hook | Blocks? | Behaviour |
|---|---|---|
| `pre-commit` | yes | Rejects the commit if `verify_log.py --recent <freshness>` fails — i.e. the log is missing, tampered, or has no valid PASS entry within the window. |
| `post-commit` | no | Advisory: notes the commit hash against the log. Never blocks. |
| `pre-push` | yes | Re-verifies the full chain before anything leaves the machine. |

## Installing

```bash
# From inside the repo (auto-detected via git rev-parse)
python3 scripts/install_hooks.py

# Explicit repo + tighter freshness window (30 min)
python3 scripts/install_hooks.py --repo /path/to/repo --freshness 1800

# Custom secret / log filename
python3 scripts/install_hooks.py --secret ~/.config/gate/hmac.key --log-name .loop-log.jsonl
```

The installed hooks are portable POSIX `sh`: they resolve the repo with
`git rev-parse --show-toplevel` at run time and call `verify_log.py` by the
absolute path it had at install time. Moving or cloning the repo keeps the hooks
working as long as that scripts directory is still present; re-run the installer
if you relocate the skill itself.

## Safety and Reversibility

- **Existing hooks are preserved.** If a repo already has a `pre-commit` (etc.)
  that is not guardrail-managed, it is copied to `<hook>.pre-guardrail` before the
  guardrail hook is written. Nothing is overwritten silently.
- **Clean uninstall.** `install_hooks.py --uninstall` removes the guardrail hooks
  and restores any `.pre-guardrail` backups.
- **Idempotent.** Re-installing over a guardrail-managed hook does not stack
  backups — only genuinely foreign hooks are backed up.

## Bypassing

A single commit can bypass the gate with:

```bash
git commit --no-verify
```

This is intentional — the gate is a guardrail, not a lock. Bypassing leaves no
PASS entry in the log, so the audit trail records the absence: a later
`verify_log.py --recent` over that commit range will show no covering entry. Use
`--no-verify` only when you genuinely mean to, and expect the gap to be visible.

## Relationship to `pre-commit-hook.sh`

`scripts/pre-commit-hook.sh` is a **stricter, skills-specific** example hook that
runs `validate.py --basic` on every staged skill directory. It predates the
generalized installer and is kept as a template for projects that want structural
skill validation on commit in addition to (or instead of) log verification. The
generalized `install_hooks.py` is the default path; use the shell template only
when you specifically want per-skill structural gating.
