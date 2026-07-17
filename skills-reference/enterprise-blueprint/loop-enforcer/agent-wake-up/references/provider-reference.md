# Provider Configuration Reference

## Config Pattern

```yaml
model:
  default: <your-model>
  provider: <your-provider>
providers: {}
fallback_providers:
  - provider: <fallback-provider-1>
    model: <fallback-model-1>
  - provider: <fallback-provider-2>
    model: <fallback-model-2>
```

## Bulk Config Fixup

```bash
GLOBAL=<agent-home>/config.yaml
for p in $(ls <agent-home>/profiles/ | grep -v default); do
  CONFIG=<agent-home>/profiles/$p/config.yaml
  [ ! -f "$CONFIG" ] && cp "$GLOBAL" "$CONFIG"
  [ ! -d <agent-home>/profiles/$p/skills ] && \
    ln -s <agent-home>/skills <agent-home>/profiles/$p/skills
done
```

## Diagnosing API Failures

```bash
# Check worker logs
hermes kanban log <task_id> --tail 20

# Check API connectivity
hermes chat -q "say OK" --provider <your-provider> --model <your-model>

# Check profile config
cat <agent-home>/profiles/<name>/config.yaml
```

## Config Best Practices
- NEVER use yaml.dump() — it scrambles config structure
- Use regex replacement on text content instead
- Keep provider configs in global config, copy to profiles
- Test API connectivity before dispatching workers
