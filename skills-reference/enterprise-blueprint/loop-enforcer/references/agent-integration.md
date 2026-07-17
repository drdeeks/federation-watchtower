# Agent Integration Guide

## Rules for Agents

1. **ALWAYS check before writing.** Before touching any file in a chain:
   ```bash
   python3 scripts/chain.py check <project-dir> <chain-name> <file-path>
   ```

2. **If state is `locked` → STOP.** Do not write. Do not read-modify-write. Do not rename. Do not delete.

3. **If state is `active` → Write the file.** Then verify and complete.

4. **Never destroy.** The chain enforces additive-only builds. If a step requires deleting or overwriting completed work, the validator should fail.

5. **Log everything.** Every file write, every verification, every completion should have a log entry.

## Agent Loop Pattern

```
for each file in chain:
    status = chain.py check(project, chain, file)
    if status.state == "locked":
        WAIT — prior step not done
        continue
    if status.state == "active":
        write_file(file)
        result = chain.py verify(project, chain, file)
        if result.ok:
            chain.py complete(project, chain, file)
        else:
            fix the file and retry
    if status.state == "complete":
        skip — already done
```

## Multi-Agent Coordination

When multiple agents work on the same chain:

- Each agent MUST check the chain before writing
- Only the agent holding the `active` step may write
- Other agents wait or work on different chains
- State is persisted to disk — no in-memory coordination needed

## Error Recovery

If a verification fails:
1. The step returns to `active` state
2. The agent can fix the file and retry
3. Attempt count increments (logged)
4. No limit on retries — keep fixing until it passes

If state gets corrupted:
- Delete the `.chain/<name>.json` file
- Re-create the chain from scratch
- Previous work is preserved (files aren't deleted)
