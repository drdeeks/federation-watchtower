# Delegation Patterns Reference

## delegate_task Usage

```python
# Single task
delegate_task(
    goal="Implement the data parser",
    context="File: src/parser.ts. Use TypeScript strict mode.",
    toolsets=["terminal", "file"]
)

# Batch (3 parallel)
delegate_task(tasks=[
    {"goal": "Task A", "context": "...", "toolsets": ["terminal"]},
    {"goal": "Task B", "context": "...", "toolsets": ["file"]},
    {"goal": "Task C", "context": "...", "toolsets": ["web"]},
])
```

## execute_code Usage

```python
# Multi-step with processing
execute_code(code="""
from hermes_tools import web_search, terminal, write_file

# Research
results = web_search("best practices for X", limit=3)

# Process
findings = [r['title'] for r in results['data']['web']]

# Write
write_file("research.md", "\\n".join(findings))
print(f"Wrote {len(findings)} findings")
""")
```

## Toolset Selection

| Task Type | Toolsets |
|-----------|----------|
| Code work | terminal, file |
| Research | web, search |
| Web interaction | browser |
| Full-stack | terminal, file, web |
| File processing | file, terminal |

## Subagent Rules

1. Leaf subagents CANNOT delegate further
2. Subagents have NO memory of parent conversation
3. Always verify subagent claims (file writes, uploads)
4. Pass all context explicitly — subagents are isolated

## When NOT to Delegate

- Single tool call → call directly
- Needs user interaction → subagents can't use clarify
- Simple mechanical work → use execute_code
- Long-running background work → use cronjob or terminal(background=True)
