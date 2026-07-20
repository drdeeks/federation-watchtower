#!/usr/bin/env python3
"""
Enforcer Daemon for synthesis-1
Privileged process that owns agent workspace, validates all tool execution,
enforces habits, and performs heartbeat validation.
"""

import argparse
import asyncio
import json
import os
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional
import stat

def show_help():
    """Display usage information."""
    print("""
Enforcer Daemon - Workspace guardian with enforcer RPC

Usage: python3 enforcer_daemon.py <agent-id> [--help]

Arguments:
  agent-id    Agent identifier (e.g., synthesis-1)
  
Options:
  --help      Show this help message

Environment:
  WORKSPACE_ROOT      Root directory for agent workspaces (default: $HOME/agents)
  ENFORCER_SOCKET_DIR Directory for enforcer Unix sockets (default: $HOME/run/agent-enforcer)
  ENFORCER_LOG_DIR    Directory for enforcer logs (default: $HOME/var/log/agent-enforcer)

Example:
  python3 enforcer_daemon.py synthesis-1
""")
    sys.exit(0)
from pathlib import Path

_DEFAULT_ROOT = str(Path.home() / "agents")

WORKSPACE_ROOT = Path(os.environ.get("WORKSPACE_ROOT", _DEFAULT_ROOT))
ENFORCER_SOCKET_DIR = Path(os.environ.get("ENFORCER_SOCKET_DIR", str(Path.home() / "run" / "agent-enforcer")))
ENFORCER_LOG_DIR = Path(os.environ.get("ENFORCER_LOG_DIR", str(Path.home() / "var" / "log" / "agent-enforcer")))

class EnforcerConfig:
    """Configuration for enforcer daemon"""
    
    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        self.workspace = WORKSPACE_ROOT / agent_id
        self.socket_path = ENFORCER_SOCKET_DIR / f"{agent_id}.sock"
        self.log_path = ENFORCER_LOG_DIR / agent_id / "audit.log"
        self.heartbeat_interval = 300  # 5 minutes
        self.validation_interval = 30  # 30 seconds
        
        # Ensure directories exist
        ENFORCER_SOCKET_DIR.mkdir(parents=True, exist_ok=True)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

class AgentEnforcer:
    """Agent Enforcer - Owns workspace, validates all actions"""
    
    def __init__(self, config: EnforcerConfig):
        self.config = config
        self.agent_id = config.agent_id
        self.workspace = config.workspace
        self.rules = self._load_rules()
        self.violations: List[Dict] = []
        self.last_heartbeat: float = 0
        self.heartbeat_stale_threshold = 600  # 10 minutes
        self._running = True
    
    def _load_rules(self) -> dict:
        """Load enforcement rules from constitution"""
        constitution_path = self.workspace / ".agent" / "constitution.yaml"
        
        rules = {
            "required_tools": [
                "enforce.sh", "secret.sh", "memory-log.sh", 
                "memory-promote.sh", "TOOLS-GUIDE.md"
            ],
            "required_dirs": {
                "tools": 0o755,
                "skills": 0o755,
                "memory": 0o755,
                ".secrets": 0o700,
                ".agent": 0o755,
                ".agent/habits": 0o755,
                ".agent/logs": 0o755,
                ".agent/metrics": 0o755,
                ".agent/templates": 0o755,
                ".agent/constitutions": 0o755
            },
            "file_perms": {},
            "forbidden_patterns": [
                "chmod 777", "chown -R", "rm -rf /", "sudo", "su",
                "exec(", "eval(", "subprocess.run("
            ]
        }
        
        if constitution_path.exists():
            try:
                import yaml
                with open(constitution_path) as f:
                    constitution = yaml.safe_load(f)
                if "hard_constraints" in constitution.get("agent", {}):
                    rules["constitution_constraints"] = constitution["agent"]["hard_constraints"]
            except Exception:
                pass
        
        return rules
    
    def validate_workspace(self) -> List[str]:
        """Validate workspace structure, returning list of violations"""
        violations = []
        
        tools_dir = self.workspace / "tools"
        for tool in self.rules["required_tools"]:
            tool_path = tools_dir / tool
            if not tool_path.exists():
                violations.append(f"MISSING_TOOL: {tool}")
            elif not os.access(tool_path, os.X_OK) and tool.endswith(".sh"):
                violations.append(f"NOT_EXECUTABLE: {tool}")
        
        for dir_name, expected_perms in self.rules["required_dirs"].items():
            dir_path = self.workspace / dir_name
            if not dir_path.exists():
                violations.append(f"MISSING_DIR: {dir_name}")
            else:
                actual = stat.S_IMODE(os.stat(dir_path).st_mode)
                if actual != expected_perms:
                    violations.append(f"BAD_PERMS_DIR: {dir_name} (got {oct(actual)}, expected {oct(expected_perms)})")
        
        return violations
    
    def auto_remediate(self, violations: List[str]) -> int:
        """Fix violations that can be auto-remediated. Returns count fixed."""
        fixed = 0
        templates_dir = self.workspace / ".agent" / "templates" / "tool-enforcement"
        
        for v in violations:
            if v.startswith("MISSING_DIR:"):
                dir_name = v.split(": ", 1)[1]
                dir_path = self.workspace / dir_name
                dir_path.mkdir(parents=True, exist_ok=True)
                expected_perms = self.rules["required_dirs"].get(dir_name, 0o755)
                os.chmod(dir_path, expected_perms)
                fixed += 1
            elif v.startswith("NOT_EXECUTABLE:"):
                tool = v.split(": ", 1)[1]
                tool_path = self.workspace / "tools" / tool
                if tool_path.exists():
                    os.chmod(tool_path, 0o755)
                    fixed += 1
            elif v.startswith("MISSING_TOOL:"):
                tool = v.split(": ", 1)[1]
                template = templates_dir / f"{tool}.template"
                if template.exists():
                    import shutil
                    shutil.copy2(template, self.workspace / "tools" / tool)
                    os.chmod(self.workspace / "tools" / tool, 0o755)
                    fixed += 1
            elif v.startswith("BAD_PERMS_DIR:"):
                parts = v.split(" ")
                dir_name = parts[1].split(":")[0]
                dir_path = self.workspace / dir_name
                expected_perms = self.rules["required_dirs"].get(dir_name, 0o755)
                os.chmod(dir_path, expected_perms)
                fixed += 1
        
        return fixed
    
    def log_violation(self, violation_type: str, details: str):
        """Log violation to audit log"""
        entry = {
            "timestamp": time.time(),
            "agent": self.agent_id,
            "type": violation_type,
            "details": details
        }
        with open(self.config.log_path, "a") as f:
            f.write(json.dumps(entry) + "\n")
    
    async def handle_rpc(self, reader, writer):
        """Handle RPC from agent process - multiple requests per connection"""
        try:
            while True:
                data = await asyncio.wait_for(reader.readline(), timeout=300)
                if not data:
                    break
                
                try:
                    request = json.loads(data.decode())
                except json.JSONDecodeError:
                    writer.write(json.dumps({"error": "Invalid JSON"}).encode() + b"\n")
                    await writer.drain()
                    continue
                
                method = request.get("method")
                params = request.get("params", {})
                
                if method == "execute_tool":
                    response = await self._handle_tool_execution(params)
                elif method == "validate_workspace":
                    response = {"status": "ok", "violations": self.validate_workspace()}
                elif method == "heartbeat":
                    response = await self._handle_heartbeat(params)
                else:
                    response = {"error": f"Unknown method: {method}"}
                
                writer.write(json.dumps(response).encode() + b"\n")
                await writer.drain()
        except asyncio.TimeoutError:
            pass
        except ConnectionResetError:
            pass
        except Exception as e:
            try:
                writer.write(json.dumps({"error": str(e)}).encode() + b"\n")
                await writer.drain()
            except:
                pass
        finally:
            try:
                writer.close()
            except:
                pass
    
    async def _handle_tool_execution(self, params: dict) -> dict:
        """Handle tool execution request from agent"""
        tool = params.get("tool")
        tool_params = params.get("params", {})
        identity_hash = params.get("identity_hash", "")
        
        violations = self.validate_workspace()
        if violations:
            fixed = self.auto_remediate(violations)
            if violations:
                self.log_violation("WORKSPACE_VIOLATION", json.dumps(violations))
                return {"denied": True, "reason": f"Workspace violations: {violations}", "reflection": "Workspace hygiene is not optional. Run enforce.sh to fix."}
        
        self.log_violation("TOOL_EXECUTION", f"Tool: {tool}, Agent: {identity_hash[:8]}")
        return {"result": {"status": "ok", "tool": tool}}
    
    async def _handle_heartbeat(self, params: dict) -> dict:
        """Handle agent heartbeat"""
        self.last_heartbeat = time.time()
        violations = self.validate_workspace()
        identity_hash = params.get("identity_hash", "")
        
        response = {
            "status": "ok",
            "timestamp": time.time(),
            "violations": violations,
            "identity_valid": len(identity_hash) > 0
        }
        
        self.log_violation("HEARTBEAT", f"Valid: {not violations}, Identity: {identity_hash[:8]}")
        return response
    
    async def start_rpc_server(self):
        """Unix domain socket RPC server"""
        socket_path = self.config.socket_path
        
        if socket_path.exists():
            socket_path.unlink()
        
        server = await asyncio.start_unix_server(self.handle_rpc, path=str(socket_path))
        print(f"[Enforcer] RPC server listening on {socket_path}")
        
        async with server:
            await server.serve_forever()
    
    async def run(self):
        """Main enforcer daemon loop"""
        import signal
        loop = asyncio.get_event_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self._shutdown)
        
        print(f"[Enforcer] Starting enforcer daemon for {self.agent_id}")
        print(f"[Enforcer] Workspace: {self.workspace}")
        print(f"[Enforcer] Socket: {self.config.socket_path}")
        
        rpc_task = asyncio.create_task(self.start_rpc_server())
        
        async def validation_loop():
            while self._running:
                await asyncio.sleep(self.config.validation_interval)
                violations = self.validate_workspace()
                if violations:
                    fixed = self.auto_remediate(violations)
                    print(f"[Enforcer] Fixed {fixed}/{len(violations)} violations")
                    self.log_violation("PERIODIC_VALIDATION", f"Found {len(violations)}, fixed {fixed}")
                if self.last_heartbeat > 0:
                    elapsed = time.time() - self.last_heartbeat
                    if elapsed > self.heartbeat_stale_threshold:
                        self.log_violation("STALE_HEARTBEAT", f"Last heartbeat {elapsed:.0f}s ago")
        
        validation_task = asyncio.create_task(validation_loop())
        await asyncio.gather(rpc_task, validation_task)
    
    def _shutdown(self):
        """Graceful shutdown"""
        self._running = False
        print("\n[Enforcer] Shutting down...")
        if self.config.socket_path.exists():
            self.config.socket_path.unlink()

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Enforcer Daemon", add_help=False)
    parser.add_argument("agent_id", nargs="?", help="Agent identifier")
    parser.add_argument("--help", "-h", action="store_true", help="Show help")
    
    args, _ = parser.parse_known_args()
    
    if args.help or not args.agent_id:
        print("""
Enforcer Daemon - Workspace guardian with enforcer RPC

Usage: python3 enforcer_daemon.py <agent-id> [--help]

Arguments:
  agent-id    Agent identifier (e.g., synthesis-1)
  
Options:
  --help      Show this help message

Environment:
  WORKSPACE_ROOT      Root directory for agent workspaces (default: $HOME/agents)
  ENFORCER_SOCKET_DIR Directory for enforcer Unix sockets (default: $HOME/run/agent-enforcer)
  ENFORCER_LOG_DIR    Directory for enforcer logs (default: $HOME/var/log/agent-enforcer)

Example:
  python3 enforcer_daemon.py synthesis-1
""")
        sys.exit(0)
    
    parser.parse_args()
    
    config = EnforcerConfig(args.agent_id)
    enforcer = AgentEnforcer(config)
    asyncio.run(enforcer.run())

if __name__ == "__main__":
    main()