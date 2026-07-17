# Profile Setup for Kanban Dispatch — Verification Checklist

## The Problem

`hermes profile create --no-skills --no-alias --description "..." <name>` creates a profile directory with:
- `agent.json` (minimal, no model config)
- NO `config.yaml`
- NO `skills/` directory

The dispatcher spawns workers using `-p <profile> --skills kanban-worker chat -q work kanban task <id>`. Without config.yaml, the worker has no model configured. Without skills/, it has no tools. The worker starts, heartbeats, but produces zero output.

## Verification Steps (before dispatch)

```bash
# 1. Check config exists and is non-trivial
for p in $(hermes profile list 2>&1 | awk 'NR>2{print $1}'); do
  size=$(wc -c < ~/.hermes/profiles/$p/config.yaml 2>/dev/null || echo 0)
  echo "$p: config=${size}B"
done
# Expected: ~16000B for each profile (same as global config)

# 2. Check skills exist
for p in $(hermes profile list 2>&1 | awk 'NR>2{print $1}'); do
  count=$(ls ~/.hermes/profiles/$p/skills/ 2>/dev/null | wc -l)
  echo "$p: skills=$count"
done
# Expected: 80+ for each profile
```

## Fix Steps (if profiles are empty)

```bash
# Copy global config
GLOBAL=~/.hermes/config.yaml
for p in $(ls ~/.hermes/profiles/ | grep -v default); do
  [ ! -f ~/.hermes/profiles/$p/config.yaml ] && cp $GLOBAL ~/.hermes/profiles/$p/config.yaml
done

# Symlink skills
for p in $(ls ~/.hermes/profiles/ | grep -v default); do
  [ ! -d ~/.hermes/profiles/$p/skills ] && [ ! -L ~/.hermes/profiles/$p/skills ] && \
    ln -s ~/.hermes/skills ~/.hermes/profiles/$p/skills
done
```

## Recovery Pattern (workers already running on empty profiles)

```bash
# 1. Reclaim all affected tasks
hermes kanban reclaim t_xxx

# 2. Fix profiles (see above)

# 3. Re-dispatch
hermes kanban dispatch
```

## Key Gotcha: Default Profile Location

The default profile does NOT have a directory at `~/.hermes/profiles/default/`. It uses the global config at `~/.hermes/config.yaml`. When copying config to new profiles, always use the global path, not the default profile path.

## Symptoms of Empty Profiles

- `hermes kanban tail <task_id>` shows: created -> claimed -> spawned -> heartbeat (no file creation)
- Workspace directory at `~/.hermes/kanban/workspaces/<task_id>/` stays empty
- Worker process is running (visible in `ps aux`) but produces nothing
- No error messages -- the worker just has no model to call
