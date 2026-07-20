# Design Principles

## 1. Additive Only

The chain enforces that work is additive. No step may delete, overwrite, or destroy work from a previous step. If a step needs to modify something a previous step created, it must be done through append or augmentation, not replacement.

## 2. Verification Before Progression

No step completes without verification. Even without a validator script, the act of running `verify` creates an explicit confirmation gate. This prevents "fire and forget" where an agent writes a file and moves on without checking.

## 3. Atomic State

State writes use atomic file replacement (write to tmp, then rename). This prevents corruption if the process crashes mid-write. The state file is always either fully old or fully new, never half-written.

## 4. Full Audit Trail

Every state change is logged with a timestamp. The log is append-only. This provides a complete history of what happened, when, and in what order.

## 5. Agent-Agnostic

The chain doesn't care which agent is working. It's a file-based coordination mechanism. Any process that can read/write files and run shell commands can participate.

## 6. Fail-Safe Defaults

- Step 0 is always immediately active (no chicken-and-egg problem)
- If no validator is set, verification auto-passes (with a warning)
- Locked steps return clear error messages, not silent failures
- State is JSON (human-readable, debuggable)
