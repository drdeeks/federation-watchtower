#!/usr/bin/env python3
"""
Phase 2 Validator: Runtime & Agents
Checks for agent definitions, runtime config, process management, orchestration.
Run by ENFORCER only — not by agent.
"""

import sys
from pathlib import Path


def check_runtime_agents(project_root: Path) -> tuple[bool, list[str]]:
    """Validate Phase 2 runtime & agents deliverables."""
    errors = []
    warnings = []
    
    # 1. Agent definitions (SOUL.md, agent.json, or similar)
    agent_markers = [
        "SOUL.md", "AGENT.md", "agent.json", "agent.yaml",
        "agents/", "agent/", ".agent/", "config/agents/"
    ]
    agent_found = any((project_root / p).exists() for p in agent_markers)
    if not agent_found:
        errors.append("No agent definition found (expected SOUL.md, agent.json, or agents/ directory)")
    
    # 2. Runtime / process management
    runtime_files = [
        "scripts/start.sh", "scripts/run.sh", "scripts/launch.sh",
        "Dockerfile", "docker-compose.yml", "docker-compose.yaml",
        "Procfile", "supervisord.conf", "systemd/", "service/",
        "scripts/start.py", "scripts/run.py", "entrypoint.sh"
    ]
    runtime_found = any((project_root / p).exists() for p in runtime_files)
    if not runtime_found:
        warnings.append("No runtime/process management found (Dockerfile, start script, systemd, etc.)")
    
    # 3. Configuration for agents/crew
    crew_config = [
        "config/crew.yaml", "config/agents.yaml", "crew.yaml",
        "agents.yaml", ".crew/", "config/crew/", "config/orchestration.yaml"
    ]
    if not any((project_root / p).exists() for p in crew_config):
        warnings.append("No crew/agent orchestration config found (config/crew.yaml recommended)")
    
    # 4. Message passing / communication layer
    comm_indicators = [
        "redis", "rabbitmq", "kafka", "nats", "mqtt", "grpc",
        "message", "queue", "bus", "channel", "pubsub",
        "zeromq", "amqp", "websocket", "socket.io"
    ]
    comm_found = False
    for f in project_root.rglob("*.py"):
        try:
            content = f.read_text().lower()
            if any(c in content for c in comm_indicators):
                comm_found = True
                break
        except:
            pass
    for f in project_root.rglob("*.js"):
        try:
            content = f.read_text().lower()
            if any(c in content for c in comm_indicators):
                comm_found = True
                break
        except:
            pass
    for f in project_root.rglob("*.go"):
        try:
            content = f.read_text().lower()
            if any(c in content for c in comm_indicators):
                comm_found = True
                break
        except:
            pass
    if not comm_found:
        warnings.append("No inter-agent communication layer detected (Redis, RabbitMQ, gRPC, NATS, etc.)")
    
    # 5. Logging / observability
    obs_files = [
        "config/logging.yaml", "logging.yaml", "config/observability.yaml",
        "prometheus.yml", "grafana/", "otel/", "tracing.py",
        "config/metrics.yaml", "config/tracing.yaml"
    ]
    if not any((project_root / p).exists() for p in obs_files):
        warnings.append("No observability config found (logging, metrics, tracing)")
    
    # 6. Agent lifecycle management (spawn, restart, health)
    lifecycle_scripts = [
        "scripts/spawn.py", "scripts/restart.py", "scripts/health.py",
        "scripts/watchdog.py", "scripts/supervisor.py", "scripts/monitor.py"
    ]
    if not any((project_root / p).exists() for p in lifecycle_scripts):
        warnings.append("No agent lifecycle management scripts found (spawn, restart, health check)")
    
    return len(errors) == 0, errors + warnings


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: validate_phase2_runtime_agents.py <step-path>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase2_runtime_agents.py <step-path>", file=sys.stderr)
        sys.exit(1)
    
    step_path = Path(sys.argv[1])
    project_root = step_path.parent.parent
    
    passed, messages = check_runtime_agents(project_root)
    
    for msg in messages:
        level = "ERROR" if not passed else "WARN"
        print(f"[{level}] {msg}")
    
    if passed:
        print("[OK] Phase 2 Runtime & Agents validation passed")
        sys.exit(0)
    else:
        print("[FAIL] Phase 2 Runtime & Agents validation failed")
        sys.exit(1)


if __name__ == "__main__":
    main()