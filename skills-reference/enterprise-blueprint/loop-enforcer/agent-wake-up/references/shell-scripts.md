# Shell Scripts Reference

## Profile Fixup (After Bulk Creation)

```bash
# Copy global config + symlink skills to all profiles
GLOBAL_CONFIG=<agent-home>/config.yaml
for profile in $(ls <agent-home>/profiles/ | grep -v default); do
  PROFILE_DIR=<agent-home>/profiles/$profile
  [ ! -f "$PROFILE_DIR/config.yaml" ] && cp "$GLOBAL_CONFIG" "$PROFILE_DIR/config.yaml"
  [ ! -d "$PROFILE_DIR/skills" ] && [ ! -L "$PROFILE_DIR/skills" ] && \
    ln -s <agent-home>/skills "$PROFILE_DIR/skills"
done
```

## Model Config Fix (Python Regex — NOT yaml.dump)

```bash
for profile in $(ls <agent-home>/profiles/ | grep -v default); do
  python3 -c "
import re, os
path = f'{os.environ[\"HOME\"]}/.hermes/profiles/{os.argv[1]}/config.yaml'
with open(path) as f: content = f.read()
old = re.search(r'^model:\n(?:  \w.*\n)*', content, re.MULTILINE)
if old:
    new = 'model:\n  default: <your-model>\n  provider: <your-provider>\n'
    content = content[:old.start()] + new + content[old.end():]
with open(path, 'w') as f: f.write(content)
" "$profile"
done
```

## Bulk Profile Creation

```bash
for name in project-lead project-engineer-1 project-engineer-2; do
  hermes profile create "$name" \
    --description "Role description" \
    --model <your-model> \
    --provider <your-provider> \
    --no-skills
done

# Fixup all profiles after creation
for p in $(ls <agent-home>/profiles/ | grep -v default); do
  [ ! -f <agent-home>/profiles/$p/config.yaml ] && \
    cp <agent-home>/config.yaml <agent-home>/profiles/$p/config.yaml
  [ ! -d <agent-home>/profiles/$p/skills ] && \
    ln -s <agent-home>/skills <agent-home>/profiles/$p/skills
done
```

## Quick Health Check

```bash
# Check workers
ps aux | grep "hermes.*kanban.*task" | grep -v grep | wc -l

# Check recent files
find ~/agent-workspaces/ -type f -mmin -15 | head -20

# Check kanban status
hermes kanban list
hermes kanban list --status=running
```
