# Monitor Cross-Check Reference

`guardrail-enforcement` is the **gate** half of a two-part guardrail. The other
half is an optional **monitor** (a generalization of the `autowatch` daemon — a
directory-agnostic "condition → action" trigger). The gate can be configured to
verify its paired monitor is running before it proceeds, forming a bidirectional
guardrail. Neither half is required; either runs standalone.

## What the Gate Checks

If `.gate.json` sets `paired_monitor_service`, `gate.py` verifies that service is
active before running any stage:

- **Linux / systemd** — `systemctl --user is-active <name>` must return `active`.
- **macOS / launchd** — `<name>` must appear in `launchctl list`.
- **Neither present** — the cross-check is skipped (best-effort, never a hard
  failure on a system with no service manager).

If the service is configured but not active, the gate refuses with status
`blocked` and exit code 1 — the loop never runs, nothing is logged. This prevents
running the gated workflow when the automation that is supposed to be watching the
directory is down.

```json
{
  "loop_command": ["python3", "build.py"],
  "hmac_secret_path": "~/.config/gate/hmac.key",
  "paired_monitor_service": "autowatch-curated"
}
```

## The Reverse Check (monitor → gate)

The monitor side (when present) can mirror the relationship: before firing its
action it can verify the target directory is under a gate config and has a
matching recent PASS entry in the loop log. If the directory has changed without a
covering gate run, the monitor holds its action until the gate has run. That check
is implemented in the monitor tool, not here; this skill only performs the gate →
monitor direction.

## Why Pair Them

| Alone | Paired |
|---|---|
| **Gate** enforces a loop + signed audit on demand. | Gate refuses to run if the watcher is down — no silent, unwatched changes. |
| **Monitor** auto-triggers actions on a condition. | Monitor holds off firing until a valid gate entry exists — no acting on unvalidated state. |

Together they close the loop: nothing changes without being watched, and nothing
is acted on without being gated. See [proposed-design.md](proposed-design.md) for
the full three-skill architecture (monitor + gate + pure skill-creator) this skill
was factored out of.
