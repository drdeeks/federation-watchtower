# OpenClaw Gateway Authentication & Configuration

## OpenClaw Gateway Authentication Modes

OpenClaw Gateway requires explicit authentication configuration for local development.

### Gateway Startup Configuration

The gateway requires explicit auth mode configuration for local development.

```json
{
  "gateway": { "port": 18789, "mode": "local" },
  "agents": { "defaults": { "workspace": "/workspace", "skills": [] }, "list": [] },
  "channels": {
    "telegram": { "accounts": {}, "defaultAccount": "" },
    "imessage": { "enabled": false }
  },
  "bindings": [],
  "mcp": { "servers": {} }
}
```

### Required Startup Flags for Local Development

```bash
# Gateway must be started with these flags for local development:
openclaw gateway run \
  --allow-unconfigured \
  --token <your-token> \
  --port 18789 \
  --bind lan
```

### Authentication Modes

| Mode | Use Case | Requirements |
|------|----------|--------------|
| `none` | No auth, only with --allow-unconfigured | --allow-unconfigured flag required |
| `token` | Token-based auth | --token or OPENCLAW_GATEWAY_TOKEN |
| `password` | Password auth | --password or OPENCLAW_GATEWAY_PASSWORD |
| `trusted-proxy` | Behind reverse proxy | Proxy headers trusted |

**Key Requirements for Local Development:**
1. **Always use `--allow-unconfigured`** - Disables gateway.mode=local requirement
2. **Must specify `--bind lan`** - Binds to all interfaces (0.0.0.0)
3. **Must provide token** - `--token <token>` or OPENCLAW_GATEWAY_TOKEN env var
4. **No auth mode by default** - Explicit `--auth none` for no auth

### Common Startup Failures & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| "resolving authentication..." | Missing auth config | Add `--allow-unconfigured --token <token>` |
| "Refusing to bind to auto/lan without auth" | Missing auth credentials | Use `--auth none --allow-unconfigured` or provide token |
| "Missing config: gateway.mode=local" | Config missing mode | Add `"mode": "local"` to gateway config |
| "unconfigured gateway needs --allow-unconfigured" | Missing flag | Add `--allow-unconfigured` flag |

---

## MCP Bridge & Internal Port Handling

### MCP Bridge Architecture

The MCP (Model Context Protocol) bridge runs as a stdio server per agent:

```bash
# Each agent gets its own MCP server via stdio
python3 -m mcp_bridge --agent-id <agent-id> --hermes-home /workspace
```

### Port Allocation

| Component | Port | Purpose |
|-----------|------|---------|
| OpenClaw Gateway | 18789 | Main HTTP/WebSocket gateway |
| MCP Bridge (per agent) | stdio | Stdio transport (no port) |
| MCP Bridge Loopback | 42235+ | Internal loopback for MCP protocol |
| WebSocket | 18791 | Browser control |

### OpenClaw Gateway Configuration for MCP

```json
{
  "mcp": {
    "servers": {
      "hermes-mcp": {
        "command": "python3",
        "args": ["-m", "mcp_bridge"],
        "env": { "AGENT_ID": "gateway-mcp", "HERMES_HOME": "/workspace" },
        "transport": "stdio"
      }
    }
  }
}
```

### MCP Bridge Implementation (mcp_bridge.py)

```python
#!/usr/bin/env python3
"""MCP Bridge Server - Exposes Hermes agent tools via MCP stdio"""

import asyncio
import json
import sys
from pathlib import Path

# Add Hermes to path
sys.path.insert(0, "/opt/hermes")

try:
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import (
        Tool, TextContent, CallToolResult, 
        InitializeResult, ServerCapabilities
    )
except ImportError:
    print("MCP not installed. Run: pip install mcp", file=sys.stderr)
    sys.exit(1)

# Hermes imports
from hermes.agent import AIAgent
from hermes.config import Config
from hermes.tools import ToolRegistry
from hermes.memory import MemoryManager

class HermesMCPBridge:
    """MCP server that wraps a Hermes agent."""

    def __init__(self, agent_id: str, workspace: str):
        self.agent_id = agent_id
        self.workspace = Path(workspace)
        self.agent: Optional[AIAgent] = None
        self.tool_registry = ToolRegistry()
        self.memory_manager: Optional[MemoryManager] = None
        self.startup_complete = False
        
        # Setup server
        self.server = Server("hermes-mcp-bridge")
        self._register_tools()
        
    def _load_identity_files(self) -> Dict[str, str]:
        """Load identity files in mandatory order."""
        identity_files = {
            "identity": "IDENTITY.md",
            "memory": "MEMORY.md", 
            "user": "USER.md",
            "tools": "TOOLS.md",
            "startup": "STARTUP.md"
        }
        
        loaded = {}
        for key, filename in identity_files.items():
            path = self.workspace / filename
            if path.exists():
                loaded[key] = path.read_text(encoding="utf-8")
            else:
                loaded[key] = f"# {filename}\nNot found. Using defaults."
        return loaded
```

---

## MCP Bridge & Internal Port Handling

### MCP Bridge Architecture

The MCP (Model Context Protocol) bridge runs as a stdio server per agent:

```bash
# Each agent gets its own MCP server via stdio
python3 -m mcp_bridge --agent-id <agent-id> --hermes-home /workspace
```

### Port Allocation

| Component | Port | Purpose |
|-----------|------|---------|
| OpenClaw Gateway | 18789 | Main HTTP/WebSocket gateway |
| MCP Bridge (per agent) | stdio | Stdio transport (no port) |
| MCP Bridge Loopback | 42235+ | Internal loopback for MCP protocol |
| WebSocket | 18791 | Browser control |

### OpenClaw Gateway Configuration for MCP

```json
{
  "mcp": {
    "servers": {
      "hermes-mcp": {
        "command": "python3",
        "args": ["-m", "mcp_bridge"],
        "env": { "AGENT_ID": "gateway-mcp", "HERMES_HOME": "/workspace" },
        "transport": "stdio"
      }
    }
  }
}
```

---

## OpenClaw Gateway Authentication Modes

OpenClaw Gateway requires explicit authentication configuration for local development.

### Gateway Startup Configuration

The gateway requires explicit auth mode configuration for local development.

```json
{
  "gateway": { "port": 18789, "mode": "local" },
  "agents": { "defaults": { "workspace": "/workspace", "skills": [] }, "list": [] },
  "channels": {
    "telegram": { "accounts": {}, "defaultAccount": "" },
    "imessage": { "enabled": false }
  },
  "bindings": [],
  "mcp": { "servers": {} }
}
```

### Required Startup Flags for Local Development

```bash
# Gateway must be started with these flags for local development:
openclaw gateway run \
  --allow-unconfigured \
  --token <your-token> \
  --port 18789 \
  --bind lan
```

### Authentication Modes

| Mode | Use Case | Requirements |
|------|----------|--------------|
| `none` | No auth, only with --allow-unconfigured | --allow-unconfigured flag required |
| `token` | Token-based auth | --token or OPENCLAW_GATEWAY_TOKEN |
| `password` | Password auth | --password or OPENCLAW_GATEWAY_PASSWORD |
| `trusted-proxy` | Behind reverse proxy | Proxy headers trusted |

**Key Requirements for Local Development:**
1. **Always use `--allow-unconfigured`** - Disables gateway.mode=local requirement
2. **Must specify `--bind lan`** - Binds to all interfaces (0.0.0.0)
3. **Must provide token** - `--token <token>` or OPENCLAW_GATEWAY_TOKEN env var
4. **No auth mode by default** - Explicit `--auth none` for no auth

### Common Startup Failures & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| "resolving authentication..." | Missing auth config | Add `--allow-unconfigured --token <token>` |
| "Refusing to bind to auto/lan without auth" | Missing auth credentials | Use `--auth none --allow-unconfigured` or provide token |
| "Missing config: gateway.mode=local" | Config missing mode | Add `"mode": "local"` to gateway config |
| "unconfigured gateway needs --allow-unconfigured" | Missing flag | Add `--allow-unconfigured` flag |

---

## MCP Bridge & Internal Port Handling

### MCP Bridge Architecture

The MCP (Model Context Protocol) bridge runs as a stdio server per agent:

```bash
# Each agent gets its own MCP server via stdio
python3 -m mcp_bridge --agent-id <agent-id> --hermes-home /workspace
```

### Port Allocation

| Component | Port | Purpose |
|-----------|------|---------|
| OpenClaw Gateway | 18789 | Main HTTP/WebSocket gateway |
| MCP Bridge (per agent) | stdio | Stdio transport (no port) |
| MCP Bridge Loopback | 42235+ | Internal loopback for MCP protocol |
| WebSocket | 18791 | Browser control |

### OpenClaw Gateway Configuration for MCP

```json
{
  "mcp": {
    "servers": {
      "hermes-mcp": {
        "command": "python3",
        "args": ["-m", "mcp_bridge"],
        "env": { "AGENT_ID": "gateway-mcp", "HERMES_HOME": "/workspace" },
        "transport": "stdio"
      }
    }
  }
}
```

### MCP Bridge Implementation (mcp_bridge.py)

```python
#!/usr/bin/env python3
"""MCP Bridge Server - Exposes Hermes agent tools via MCP stdio"""

import asyncio
import json
import sys
from pathlib import Path

import aiohttp
from aiohttp import web

# Add Hermes to path
sys.path.insert(0, "/opt/hermes")

try:
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import (
        Tool, TextContent, CallToolResult, 
        InitializeResult, ServerCapabilities
    )
except ImportError:
    print("MCP not installed. Run: pip install mcp", file=sys.stderr)
    sys.exit(1)

# Hermes imports
from hermes.agent import AIAgent
from hermes.config import Config
from hermes.tools import ToolRegistry
from hermes.memory import MemoryManager

class HermesMCPBridge:
    """MCP server that wraps a Hermes agent."""
    
    def __init__(self, agent_id: str, workspace: str):
        self.agent_id = agent_id
        self.workspace = Path(workspace)
        self.agent: Optional[AIAgent] = None
        self.tool_registry = ToolRegistry()
        self.memory_manager: Optional[MemoryManager] = None
        self.startup_complete = False
        
        # Setup server
        self.server = Server("hermes-mcp-bridge")
        self._register_tools()
        
    def _load_identity_files(self) -> Dict[str, str]:
        """Load identity files in mandatory order."""
        identity_files = {
            "identity": "IDENTITY.md",
            "memory": "MEMORY.md", 
            "user": "USER.md",
            "tools": "TOOLS.md",
            "startup": "STARTUP.md"
        }
        
        loaded = {}
        for key, filename in identity_files.items():
            path = self.workspace / filename
            if path.exists():
                loaded[key] = path.read_text(encoding="utf-8")
            else:
                loaded[key] = f"# {filename}\nNot found. Using defaults."
        return loaded
    
    def _startup(self) -> bool:
        """Initialize the Hermes agent and register tools."""
        try:
            identity = self._load_identity_files()
            config = Config.load(self.workspace / "config.yaml")
            
            # Initialize memory manager
            self.memory_manager = MemoryManager(self.workspace)
            
            # Create agent
            self.agent = AIAgent(
                agent_id=self.agent_id,
                config=config,
                identity=identity,
                memory_manager=self.memory_manager,
                tool_registry=self.tool_registry,
                workspace=self.workspace
            )
            
            # Register Hermes tools as MCP tools
            self._register_tools()
            self.startup_complete = True
            return True
        except Exception as e:
            print(f"Startup failed: {e}", file=sys.stderr)
            return False
    
    def _register_tools(self):
        """Register all Hermes tools as MCP tools."""
        for tool in self.tool_registry.get_tools():
            self.server.add_tool(tool)
    
    async def run(self):
        """Run the MCP server via stdio."""
        if not self.startup_complete:
            if not self._startup():
                sys.exit(1)
        
        async with stdio_server() as (read, write):
            await self.server.run(read, write)

async def main():
    if len(sys.argv) < 2:
        print("Usage: python3 -m mcp_bridge --agent-id <id> [--hermes-home <path>]", file=sys.stderr)
        sys.exit(1)
    
    agent_id = None
    workspace = "/workspace"
    for i, arg in enumerate(sys.argv):
        if arg == "--agent-id" and i + 1 < len(sys.argv):
            agent_id = sys.argv[i + 1]
        elif arg == "--hermes-home" and i + 1 < len(sys.argv):
            workspace = sys.argv[i + 1]
    
    if not agent_id:
        print("Error: --agent-id required", file=sys.stderr)
        sys.exit(1)
    
    bridge = HermesMCPBridge(agent_id, workspace)
    await bridge.run()

if __name == "__main__":
    asyncio.run(main())
```

---

## OpenClaw Gateway Authentication Modes

OpenClaw Gateway requires explicit authentication configuration for local development.

### Gateway Startup Configuration

The gateway requires explicit auth mode configuration for local development.

```json
{
  "gateway": { "port": 18789, "mode": "local" },
  "agents": { "defaults": { "workspace": "/workspace", "skills": [] }, "list": [] },
  "channels": {
    "telegram": { "accounts": {}, "defaultAccount": "" },
    "imessage": { "enabled": false }
  },
  "bindings": [],
  "mcp": { "servers": {} }
}
```

### Required Startup Flags for Local Development

```bash
# Gateway must be started with these flags for local development:
openclaw gateway run \
  --allow-unconfigured \
  --token <your-token> \
  --port 18789 \
  --bind lan
```

### Authentication Modes

| Mode | Use Case | Requirements |
|------|----------|--------------|
| `none` | No auth, only with --allow-unconfigured | --allow-unconfigured flag required |
| `token` | Token-based auth | --token or OPENCLAW_GATEWAY_TOKEN |
| `password` | Password auth | --password or OPENCLAW_GATEWAY_PASSWORD |
| `trusted-proxy` | Behind reverse proxy | Proxy headers trusted |

**Key Requirements for Local Development:**
1. **Always use `--allow-unconfigured`** - Disables gateway.mode=local requirement
2. **Must specify `--bind lan`** - Binds to all interfaces (0.0.0.0)
3. **Must provide token** - `--token <token>` or OPENCLAW_GATEWAY_TOKEN env var
4. **No auth mode by default** - Explicit `--auth none` for no auth

### Common Startup Failures & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| "resolving authentication..." | Missing auth config | Add `--allow-unconfigured --token <token>` |
| "Refusing to bind to auto/lan without auth" | Missing auth credentials | Use `--auth none --allow-unconfigured` or provide token |
| "Missing config: gateway.mode=local" | Config missing mode | Add `"mode": "local"` to gateway config |
| "unconfigured gateway needs --allow-unconfigured" | Missing flag | Add `--allow-unconfigured` flag |

---

## Playwright Test Configuration & Debugging

### Common Playwright Test Discovery Issues

**Problem**: Playwright test runner reports "No tests found" despite valid test files existing.

**Root Causes & Fixes**:

1. **Wrong testDir in config**: Ensure `testDir` points to the directory containing `.spec.ts` files
   ```javascript
   // playwright.config.js
   export default defineConfig({
     testDir: 'tests',  // Relative to config file location
     // ...
   })
   ```

2. **Config file location mismatch**: Run Playwright from the directory containing the config file, or specify config explicitly:
   ```bash
   # From project root with config in tests/
   npx playwright test --config=tests/playwright.config.ts
   
   # Or from tests directory with config in same dir
   npx playwright test --config=playwright.config.ts
   ```

3. **Test file naming**: Files must match `*.spec.ts` or `*.test.ts` pattern (or configured pattern)

4. **Module resolution**: Ensure `@playwright/test` is installed in the same directory as tests (not parent directory)

5. **Syntax validation**: Check test files for syntax errors before running:
   ```bash
   npx tsc --noEmit --skipLibCheck tests/**/*.spec.ts
   ```

### Playwright Configuration Best Practices

```javascript
// playwright.config.js - Recommended minimal config
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'tests',           // Directory containing test files
  fullyParallel: true,        // Run tests in parallel
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:18789',  // Gateway URL
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
});
```

### Common Debugging Commands

```bash
# List all discovered tests
npx playwright test --list

# List tests with specific project
npx playwright test --project=chromium --list

# Run specific test file
npx playwright test health.spec.ts

# Run with specific project
npx playwright test --project=chromium

# Debug mode
npx playwright test --debug

# Generate HTML report
npx playwright test --reporter=html

# Run with trace on failure
npx playwright test --trace=on-first-retry
```

### Common Pitfalls & Fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| "No tests found" | Wrong testDir or config location | Verify testDir matches test file location |
| "Test file is imported by config" | test() called in config file | Move tests to separate files under testDir |
| "Cannot find module @playwright/test" | Module not installed in test dir | Run `npm install @playwright/test` in test dir |
| "Module not found" | Wrong working directory | Run from directory with package.json |
| Test timeout | Gateway not ready | Ensure gateway is healthy before tests |

---

## Security Hardening Script Improvements

### Security Hardening Script Improvements

#### Regex MULTILINE Flag for .gitignore Checking

**Problem**: The security hardening script's `.gitignore` pattern checking was failing to match patterns at the start of lines.

**Before (broken - misses patterns at line start):**
```python
for pattern in required_patterns:
    if not re.search(pattern, content):
        issues.append(f"Missing gitignore pattern: {pattern}")
```

**After (fixed - uses MULTILINE flag):**
```python
for pattern in required_patterns:
    if not re.search(pattern, content, re.MULTILINE):
        issues.append(f"Missing gitignore pattern: {pattern}")
```

#### Required Patterns for .gitignore Validation

```python
required_patterns = [
    r"\.secrets/",
    r"\*\.key",
    r"\*\.pem",
    r"\.env",
    r"\*API_KEY\*",
    r"\*TOKEN\*",
    r"\*\.wallet",
    r"\*private\*key\*",
    r"\.db$",        # Matches .db at end of line
    r"__pycache__/",
    r"node_modules/",
    r"\.vscode/",
]
```

#### Key Fixes Applied

1. **Added `re.MULTILINE` flag** to `re.search()` for `.gitignore` pattern matching
   - Allows `^` and `$` to match start/end of each line
   - Required for patterns like `\.db$` that need to match at line end

2. **Fixed `.db$` pattern** - Now correctly matches lines ending with `.db`
   - Previously: `*.db$` (regex escape issue)
   - Fixed: `\.db$` (properly escaped)

3. **Added dangerous pattern detection** for `.env` overrides:
   ```python
   dangerous = [
       r"!\.secrets/",
       r"!\*\.key",
       r"!\.env(?:$|\s)"  # Matches !.env at line end or followed by whitespace
   ]
   ```

---

## Sources

| Source | URL | Last Verified |
|--------|-----|---------------|
| Gitignore Templates | https://github.com/github/gitignore | 2026-06-09 |
| OpenSSF Scorecard | https://github.com/ossf/scorecard | 2026-06-09 |
| NIST SSDF | https://csrc.nist.gov/Projects/ssdf | 2026-06-09 |
| Semantic Versioning | https://semver.org | 2026-06-09 |
| Keep a Changelog | https://keepachangelog.com | 2026-06-09 |
| Git SCM | https://git-scm.com | 2026-06-09 |
| Conventional Commits | https://www.conventionalcommits.org | 2026-06-09 |
| Playwright Test | https://playwright.dev/docs/test-intro | 2026-06-13 |
| OpenClaw Gateway | https://docs.openclaw.ai | 2026-06-13 |
| MCP Specification | https://modelcontextprotocol.io | 2026-06-13 |
| OpenClaw Gateway Documentation | https://docs.openclaw.ai/docs/gateway | 2026-06-13 |
| MCP Loopback Auth | https://docs.openclaw.ai/docs/mcp-loopback-auth | 2026-06-13 |