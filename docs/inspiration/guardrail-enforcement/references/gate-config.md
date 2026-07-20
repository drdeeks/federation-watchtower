# Gate Configuration Reference

The gate is driven entirely by a `.gate.json` file in the gated directory (or a
path passed via `gate.py --config`). The same engine gates skills authoring, a
Kubernetes deploy, or a batch pipeline — only the config differs.

## Schema

| Field | Type | Required | Meaning |
|---|---|---|---|
| `pre_checks` | array of command-arrays | no | Commands run **before** the loop. Any non-zero exit aborts the gate. |
| `loop_command` | command-array | yes | The actual work. A single command; non-zero exit aborts. |
| `post_checks` | array of command-arrays | no | Commands run **after** the loop. Any non-zero exit aborts. |
| `hmac_secret_path` | string | yes | Path to the HMAC key used to sign the log. `~` is expanded. |
| `log_path` | string | no | Loop-log path (default `.loop-log.jsonl`, relative to the gated dir). |
| `git_integration` | bool | no | Whether git hooks are expected (informational for `setup.py`/`install_hooks.py`). |
| `paired_monitor_service` | string | no | If set, the gate verifies this service is active before running (see [monitor-crosscheck.md](monitor-crosscheck.md)). |

A "command-array" is a list of argv tokens, e.g. `["python3", "validate.py", "{path}"]`.

## Variable Substitution

`{path}` and any `--var NAME=VALUE` passed to `gate.py` are substituted into every
command token before execution. This keeps configs reusable across targets:

```bash
python3 scripts/gate.py --path ./output/my-project --var env=staging
```

## Worked Configs

**Skills-authoring gate** — validate, enhance, re-validate:
```json
{
  "pre_checks":   [["python3", "skill-creator/scripts/validate.py", "{path}", "--basic"]],
  "loop_command": ["python3", "skill-creator/scripts/skill_enhance.py", "update", "--path", "{path}"],
  "post_checks":  [["python3", "skill-creator/scripts/validate.py", "{path}"]],
  "hmac_secret_path": "~/.config/gate/hmac.key",
  "log_path": ".loop-log.jsonl",
  "git_integration": true
}
```

**Kubernetes deploy gate** — dry-run, deploy, health-check:
```json
{
  "pre_checks":   [["kubectl", "apply", "--dry-run=client", "-f", "{path}"]],
  "loop_command": ["./deploy.sh", "{path}"],
  "post_checks":  [["./health-check.sh"]],
  "hmac_secret_path": "~/.config/gate/hmac.key",
  "git_integration": true
}
```

**Batch pipeline gate (no git)** — space check, run, grep for SUCCESS:
```json
{
  "pre_checks":   [["df", "--output=avail", "."]],
  "loop_command": ["python3", "pipeline.py"],
  "post_checks":  [["grep", "-q", "^SUCCESS", "pipeline.log"]],
  "hmac_secret_path": "~/.config/gate/hmac.key",
  "git_integration": false
}
```
With `git_integration: false`, no hooks are installed — the signed log still
accrues as a tamper-evident audit trail.

## Creating a Config

Use `setup.py` rather than hand-editing:

```bash
# Interactive
python3 scripts/setup.py /path/to/dir

# Non-interactive (CI-safe)
python3 scripts/setup.py /path/to/dir --yes \
  --pre-check "python3 validate.py {path}" \
  --loop-command "python3 build.py {path}" \
  --post-check "python3 validate.py {path}" \
  --no-git
```

`setup.py` also generates the HMAC secret at `hmac_secret_path` with mode `0600`
if it does not already exist.
