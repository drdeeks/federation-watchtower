# Validator Examples

## Basic File Existence

```python
#!/usr/bin/env python3
import sys, os
path = sys.argv[1]
if not os.path.exists(path) or os.path.getsize(path) == 0:
    print(f"FAIL: {path}")
    sys.exit(1)
print(f"PASS: {path}")
sys.exit(0)
```

## Minimum Line Count

```python
#!/usr/bin/env python3
import sys
path = sys.argv[1]
min_lines = int(sys.argv[2]) if len(sys.argv) > 2 else 50
with open(path) as f:
    lines = len(f.readlines())
if lines < min_lines:
    print(f"FAIL: {lines} < {min_lines} lines")
    sys.exit(1)
print(f"PASS: {lines} lines")
sys.exit(0)
```

## No Placeholders

```python
#!/usr/bin/env python3
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
bad = re.findall(r'TODO|FIXME|HACK|\[placeholder\]', content, re.IGNORECASE)
if bad:
    print(f"FAIL: found {bad}")
    sys.exit(1)
print("PASS: no placeholders")
sys.exit(0)
```

## Additive-Only (No Deletions)

```python
#!/usr/bin/env python3
import sys, os, json
path = sys.argv[1]
# Check git status — if file was deleted or modified-destructively, fail
import subprocess
result = subprocess.run(["git", "diff", "--name-status", "HEAD"], capture_output=True, text=True)
for line in result.stdout.strip().split("\n"):
    if line.startswith("D") and path in line:
        print(f"FAIL: file was deleted: {path}")
        sys.exit(1)
print(f"PASS: additive check passed")
sys.exit(0)
```

## Syntax Check (JavaScript)

```python
#!/usr/bin/env python3
import sys, subprocess
path = sys.argv[1]
result = subprocess.run(["node", "--check", path], capture_output=True, text=True)
if result.returncode != 0:
    print(f"FAIL: syntax error\n{result.stderr}")
    sys.exit(1)
print(f"PASS: syntax OK")
sys.exit(0)
```
