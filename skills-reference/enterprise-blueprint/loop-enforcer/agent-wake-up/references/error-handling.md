# Error Handling Reference

## Common Errors and Fixes

### API Authentication Failed (401)
**Cause:** Expired or invalid API key.
**Fix:** Update provider config with valid credentials. Check `~/.hermes/config.yaml`.

### Rate Limit Exceeded (429)
**Cause:** Too many requests to API provider.
**Fix:** Wait and retry. Use fallback providers. Implement exponential backoff.

### Model Not Found (404)
**Cause:** Model name misspelled or deprecated.
**Fix:** Check provider documentation for current model names.

### Timeout (504)
**Cause:** Request took too long.
**Fix:** Increase timeout, simplify prompt, or try a faster model.

### Context Length Exceeded
**Cause:** Input too long for model's context window.
**Fix:** Summarize input, use chunking, or switch to model with larger context.

## Worker Crash Recovery

```bash
# 1. Check worker status
ps aux | grep "hermes.*kanban.*task" | grep -v grep

# 2. Check kanban log
hermes kanban log <task_id> --tail 20

# 3. Reclaim and re-dispatch
hermes kanban reclaim <task_id>
hermes kanban dispatch
```

## Profile Config Issues

```bash
# Verify profile has config
ls -la ~/.hermes/profiles/<name>/config.yaml

# Verify skills symlink
ls -la ~/.hermes/profiles/<name>/skills

# Fix missing config
cp ~/.hermes/config.yaml ~/.hermes/profiles/<name>/config.yaml
ln -s ~/.hermes/skills ~/.hermes/profiles/<name>/skills
```

## Logging

Logs are written to:
- `~/.hermes/logs/agent.log` — Main agent log
- `~/.hermes/logs/agent-deaths.log` — Self-heal death notifications
- `~/.hermes/logs/death-<task_id>.json` — Death marker files
