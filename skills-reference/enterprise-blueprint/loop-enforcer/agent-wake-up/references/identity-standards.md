# Identity Standards Reference

## SOUL.md Structure

Every agent workspace must contain a SOUL.md with these sections:

```markdown
# <Agent Name>

## Role
<Single paragraph describing the agent's primary function>

## Core Capabilities
- <Capability 1>
- <Capability 2>
- <Capability 3>

## Operating Principles
1. <Principle 1>
2. <Principle 2>
3. <Principle 3>

## Communication Style
<Description of how the agent communicates>

## Decision Framework
<How the agent makes decisions>

## Memory Strategy
<What the agent remembers and how>

## Limitations
<What the agent cannot do or should not do>
```

## USER.md Structure

```markdown
# User Profile

## Identity
- Name: <name>
- Role: <role>
- Timezone: <timezone>

## Preferences
- Communication style: <style>
- Technical level: <level>
- Response format: <format>

## Projects
- <project 1>: <brief description>
- <project 2>: <brief description>

## Constraints
- <constraint 1>
- <constraint 2>
```

## Agent Naming Convention

- Lowercase, hyphen-separated
- Format: `<project>-<role>`
- Examples: `mnemosyne-lead`, `aires-director`, `edgewalker-kernel`

## Workspace Structure

```
workspace/
├── SOUL.md          # Agent identity
├── USER.md          # User preferences
├── MEMORY.md        # Persistent knowledge
├── AGENTS.md        # Crew roster (optional)
├── TOOLS.md         # Available tools (optional)
├── src/             # Source code
├── scripts/         # Automation scripts
├── tests/           # Test suites
└── docs/            # Documentation
```
