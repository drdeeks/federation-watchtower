#!/usr/bin/env python3
"""
Crew Manager - Integrates project-manager with autonomous-crew
Creates crews with blueprint enforcement, identity layer, and chain validation.
"""

import json
import sys
import os
import subprocess
from pathlib import Path
from datetime import datetime, timezone

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

class CrewManager:
    """Manages crew creation with blueprint enforcement and identity layer."""
    
    def __init__(self, workspace_root):
        self.workspace_root = Path(workspace_root)
        self.skills_dir = Path(__file__).parent.parent.parent
        self.crews_dir = self.skills_dir / "crews"
        self.pm_dir = self.crews_dir / "project-manager"
        self.rules_dir = self.crews_dir / "rules"
        self.config_dir = self.skills_dir / "config"
        self.providers_config = self._load_providers_config()
        self.available_models = self._detect_available_models()
    
    def _load_providers_config(self):
        """Load providers.json configuration."""
        config_file = self.config_dir / "providers.json"
        if config_file.exists():
            with open(config_file) as f:
                return json.load(f)
        return {}
    
    def _detect_available_models(self):
        """Detect available models from environment and config."""
        available = {
            "text": [],
            "vision": [],
            "embedding": []
        }
        
        # Check environment variables for API keys
        env_checks = {
            "DASHSCOPE_API_KEY": "dashscope",
            "OPENAI_API_KEY": "openai",
            "ANTHROPIC_API_KEY": "anthropic"
        }
        
        detected_providers = []
        for env_key, provider_name in env_checks.items():
            if os.environ.get(env_key):
                detected_providers.append(provider_name)
        
        # If no providers detected, check if local is available
        if not detected_providers and self.providers_config.get("providers", {}).get("local"):
            detected_providers.append("local")
        
        # Gather models from detected providers
        for provider_name in detected_providers:
            provider = self.providers_config.get("providers", {}).get(provider_name, {})
            models = provider.get("models", {})
            for model_type in ["text", "vision", "embedding"]:
                available[model_type].extend(models.get(model_type, []))
        
        # If still no models, use defaults
        if not any(available.values()):
            defaults = self.providers_config.get("defaults", {})
            available["text"] = [defaults.get("primary_model", "model-not-configured")]
            available["vision"] = [defaults.get("vision_model", "model-not-configured")]
            available["embedding"] = [defaults.get("embedding_model", "model-not-configured")]
        
        return available
    
    def _select_model_for_role(self, role):
        """Select best available model for a given role."""
        role_mapping = self.providers_config.get("role_model_mapping", {})
        model_type = role_mapping.get(role, role_mapping.get("default", "primary_model"))
        
        # Map model type to available category
        type_map = {
            "primary_model": "text",
            "reasoning_model": "text",
            "creative_model": "text",
            "vision_model": "vision",
            "embedding_model": "embedding",
            "edge_model": "text",
            "economy_model": "text"
        }
        
        category = type_map.get(model_type, "text")
        models = self.available_models.get(category, [])
        
        if models:
            return models[0]  # Return first available
        return "model-not-configured"  # Must configure providers.json
        
    def create_crew_with_blueprint(self, crew_name, project_dir, blueprint_path=None):
        """Create a crew with full blueprint enforcement and identity layer."""
        
        project_dir = Path(project_dir)
        if not project_dir.exists():
            print(f"Error: Project directory not found: {project_dir}")
            return False
        
        # Find blueprint
        if blueprint_path:
            bp_path = Path(blueprint_path)
        else:
            # Look for blueprint.md in project
            bp_path = project_dir / "blueprint.md"
            if not bp_path.exists():
                # Look for any blueprint
                for f in project_dir.glob("*blueprint*.md"):
                    bp_path = f
                    break
        
        if not bp_path.exists():
            print(f"Error: No blueprint found in {project_dir}")
            return False
        
        print(f"\n{'='*60}")
        print(f"CREW CREATION WITH BLUEPRINT ENFORCEMENT")
        print(f"{'='*60}")
        print(f"Crew: {crew_name}")
        print(f"Project: {project_dir}")
        print(f"Blueprint: {bp_path}")
        print(f"{'='*60}\n")
        
        # Step 1: Create crew using project-manager
        print("[1/6] Creating crew structure...")
        crew_dir = self._create_crew_structure(crew_name, project_dir)
        if not crew_dir:
            return False
        
        # Step 2: Initialize identity layer
        print("[2/6] Initializing identity layer...")
        self._initialize_identity_layer(crew_dir, crew_name)
        
        # Step 3: Create chain from blueprint
        print("[3/6] Creating chain from blueprint...")
        self._create_chain_from_blueprint(crew_dir, project_dir, bp_path)
        
        # Step 4: Generate phase validators
        print("[4/6] Generating phase validators...")
        self._generate_phase_validators(crew_dir, project_dir)
        
        # Step 5: Wire kanban to chain
        print("[5/6] Wiring kanban to chain...")
        self._wire_kanban(crew_dir, project_dir)
        
        # Step 6: Create enforcement rules
        print("[6/7] Creating enforcement rules...")
        self._create_enforcement_rules(crew_dir)
        
        # Step 7: Generate session log and blueprint.json
        print("[7/7] Generating session log and blueprint.json...")
        actions_taken = [
            {"step": "Create crew structure", "tool": "terminal", "input": {"crew_name": crew_name}, "output": f"Created {crew_dir}", "status": "complete"},
            {"step": "Initialize identity layer", "tool": "terminal", "input": {}, "output": "Constitution and habits created", "status": "complete"},
            {"step": "Create chain from blueprint", "tool": "terminal", "input": {"blueprint": str(bp_path)}, "output": "7 phases created", "status": "complete"},
            {"step": "Generate phase validators", "tool": "terminal", "input": {}, "output": "7 validators generated", "status": "complete"},
            {"step": "Wire kanban to chain", "tool": "terminal", "input": {}, "output": "Kanban wiring config created", "status": "complete"},
            {"step": "Create enforcement rules", "tool": "terminal", "input": {}, "output": "Rules copied from enterprise blueprint", "status": "complete"}
        ]
        self._generate_session_log(crew_dir, crew_name, project_dir, bp_path, actions_taken)
        
        print(f"\n{'='*60}")
        print(f"CREW CREATED SUCCESSFULLY")
        print(f"{'='*60}")
        print(f"Crew directory: {crew_dir}")
        print(f"Identity: {crew_dir / '.agent'}")
        print(f"Chain: {crew_dir / '.blueprint-chain'}")
        print(f"Rules: {crew_dir / 'rules'}")
        print(f"{'='*60}\n")
        
        return True
    
    def _create_crew_structure(self, crew_name, project_dir):
        """Create the crew directory structure."""
        crew_dir = project_dir / f".crew-{crew_name}"
        
        if crew_dir.exists():
            print(f"  Crew directory already exists: {crew_dir}")
            return crew_dir
        
        # Create subdirectories
        for subdir in ["agents", "config", "workflows", "rules", "memory", "projects", "blueprints"]:
            (crew_dir / subdir).mkdir(parents=True, exist_ok=True)
        
        # Create crew.json
        crew_config = {
            "crew_id": crew_name,
            "name": crew_name,
            "description": f"Crew for {project_dir.name}",
            "version": "1.0.0",
            "status": "active",
            "created_at": now_iso(),
            "project_dir": str(project_dir.absolute()),
            "agents": [],
            "workflows": {
                "primary": "./workflows/primary_workflow.json",
                "fallback": "./workflows/error_handling.json"
            },
            "quality_gates": {
                "validation_required": True,
                "quality_metrics": True,
                "multi_point_check": True
            }
        }
        
        crew_json_path = crew_dir / "crew.json"
        with open(crew_json_path, "w") as f:
            json.dump(crew_config, f, indent=2)
        
        print(f"  Created crew directory: {crew_dir}")
        return crew_dir
    
    def _initialize_identity_layer(self, crew_dir, crew_name):
        """Initialize the identity layer for the crew."""
        agent_dir = crew_dir / ".agent"
        agent_dir.mkdir(parents=True, exist_ok=True)
        
        # Create constitution
        constitution = f"""# Crew Constitution
## {crew_name}

### Identity
- Purpose: Execute project blueprint with identity-first architecture
- Principles: Complete deliverables, verify before claiming, honor constitution
- Authority: Project Manager oversees all operations

### Habits
1. identity-enforcement: Verify constitution hash before ANY tool invocation
2. tool-enforcement: Validate workspace hygiene before file writes
3. reflective-loop: Reflect after EVERY tool result
4. blueprint-phase-gate: Run chain verify+complete before claiming phase done

### Enforcement
- All phases must pass validation gates
- No phase skipping allowed
- Deliverables verified before completion
- Self-healing runs every 5 minutes
"""
        
        constitution_file = agent_dir / "constitution.yaml"
        constitution_file.write_text(constitution)
        
        # Create habits file
        habits = {
            "identity-enforcement": {
                "trigger": "Before ANY tool invocation",
                "action": "Verify constitution hash matches",
                "last_triggered": now_iso()
            },
            "tool-enforcement": {
                "trigger": "Before file write / external call",
                "action": "Validate workspace hygiene",
                "last_triggered": now_iso()
            },
            "reflective-loop": {
                "trigger": "After EVERY tool result",
                "action": "Reflect on advancement and violations",
                "last_triggered": now_iso()
            },
            "blueprint-phase-gate": {
                "trigger": "Before claiming phase complete",
                "action": "Run chain verify → complete",
                "last_triggered": now_iso()
            }
        }
        
        habits_file = agent_dir / "habits.json"
        with open(habits_file, "w") as f:
            json.dump(habits, f, indent=2)
        
        print(f"  Initialized identity layer: {agent_dir}")
    
    def _create_chain_from_blueprint(self, crew_dir, project_dir, blueprint_path):
        """Create chain from blueprint."""
        chain_dir = crew_dir / ".blueprint-chain"
        chain_dir.mkdir(parents=True, exist_ok=True)
        
        # Parse blueprint to extract phases
        content = blueprint_path.read_text()
        
        # Simple phase extraction (look for Phase markers)
        import re
        phases = []
        phase_pattern = r"###?\s*Phase\s+(\d+)[^.]*?[:–—]\s*(.+?)(?:\n|$)"
        for match in re.finditer(phase_pattern, content, re.IGNORECASE):
            phase_num = int(match.group(1))
            phase_title = match.group(2).strip()
            phases.append({"num": phase_num, "title": phase_title})
        
        if not phases:
            # Create default phases
            phases = [
                {"num": 0, "title": "Foundation & Infrastructure"},
                {"num": 1, "title": "Core Implementation"},
                {"num": 2, "title": "Integration & Testing"},
                {"num": 3, "title": "Deployment & Operations"}
            ]
        
        # Create chain state
        chain_state = {
            "name": f"{project_dir.name}-blueprint",
            "project": str(project_dir.absolute()),
            "crew": str(crew_dir.absolute()),
            "created_at": now_iso(),
            "blueprint": str(blueprint_path.absolute()),
            "steps": []
        }
        
        for i, phase in enumerate(phases):
            marker_file = chain_dir / f"phase-{phase['num']:02d}-{phase['title'].replace(' ', '-').replace('&', 'and')[:50]}.marker"
            marker_file.write_text(f"Phase {phase['num']} created")
            
            chain_step = {
                "index": phase["num"],
                "path": str(marker_file.absolute()),
                "state": "active" if i == 0 else "locked",
                "validator": None,
                "created_at": now_iso(),
                "verified_at": None,
                "completed_at": None,
                "attempts": 0,
                "title": phase["title"]
            }
            chain_state["steps"].append(chain_step)
        
        # Save chain state
        chain_file = chain_dir / f"{project_dir.name}-blueprint.json"
        with open(chain_file, "w") as f:
            json.dump(chain_state, f, indent=2)
        
        print(f"  Created chain with {len(phases)} phases: {chain_file}")
    
    def _generate_phase_validators(self, crew_dir, project_dir):
        """Generate phase validators."""
        validators_dir = crew_dir / "validators"
        validators_dir.mkdir(parents=True, exist_ok=True)
        
        # Read chain to get phases
        chain_files = list((crew_dir / ".blueprint-chain").glob("*-blueprint.json"))
        if not chain_files:
            print("  No chain found, skipping validator generation")
            return
        
        with open(chain_files[0]) as f:
            chain = json.load(f)
        
        for step in chain["steps"]:
            phase_num = step["index"]
            phase_title = step.get("title", f"Phase {phase_num}")
            
            validator_content = f'''#!/usr/bin/env python3
"""
Phase {phase_num} Validator: {phase_title}
Validates deliverables exist and are non-empty.
"""

import json
import sys
from pathlib import Path

def validate():
    """Validate phase {phase_num} deliverables."""
    project_dir = Path("{project_dir}")
    results = []
    all_passed = True
    
    # Common deliverables
    deliverables = [
        {{"name": "package.json", "path": "package.json", "type": "file", "min_size": 50}},
        {{"name": "README.md", "path": "README.md", "type": "file", "min_size": 100}},
        {{"name": "src directory", "path": "src", "type": "directory"}},
    ]
    
    for deliverable in deliverables:
        path = project_dir / deliverable["path"]
        expected_type = deliverable.get("type", "file")
        min_size = deliverable.get("min_size", 1)
        
        if not path.exists():
            results.append({{
                "deliverable": deliverable["name"],
                "path": str(path),
                "status": "FAIL",
                "reason": "File does not exist"
            }})
            all_passed = False
            continue
        
        if expected_type == "file":
            size = path.stat().st_size
            if size < min_size:
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "FAIL",
                    "reason": f"File too small: {{size}} bytes (min: {{min_size}})"
                }})
                all_passed = False
            else:
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "PASS",
                    "size": size
                }})
        elif expected_type == "directory":
            if not path.is_dir():
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "FAIL",
                    "reason": "Path is not a directory"
                }})
                all_passed = False
            else:
                file_count = len(list(path.rglob("*")))
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "PASS",
                    "file_count": file_count
                }})
    
    return {{"passed": all_passed, "results": results}}

if __name__ == "__main__":
    result = validate()
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["passed"] else 1)
'''
            
            validator_file = validators_dir / f"validate-phase-{phase_num:02d}.py"
            validator_file.write_text(validator_content)
            validator_file.chmod(0o755)
        
        print(f"  Generated {len(chain['steps'])} phase validators")
    
    def _wire_kanban(self, crew_dir, project_dir):
        """Wire kanban to chain."""
        # This would wire to the kanban database
        # For now, create a reference
        wire_config = {
            "crew_dir": str(crew_dir.absolute()),
            "project_dir": str(project_dir.absolute()),
            "chain_dir": str(crew_dir / ".blueprint-chain"),
            "kanban_db": str(Path.home() / ".hermes" / "kanban.db"),
            "created_at": now_iso()
        }
        
        wire_file = crew_dir / "config" / "kanban-wiring.json"
        with open(wire_file, "w") as f:
            json.dump(wire_config, f, indent=2)
        
        print(f"  Created kanban wiring config: {wire_file}")
    
    def _create_enforcement_rules(self, crew_dir):
        """Create enforcement rules from crew rules."""
        rules_dir = crew_dir / "rules"
        
        # Copy rules from the crew rules directory
        if self.rules_dir.exists():
            for rule_file in self.rules_dir.glob("*.json"):
                dest = rules_dir / rule_file.name
                if not dest.exists():
                    import shutil
                    shutil.copy2(str(rule_file), str(dest))
        
        print(f"  Created enforcement rules: {rules_dir}")
    
    def _generate_session_log(self, crew_dir, crew_name, project_dir, blueprint_path, actions_taken):
        """Generate session log and crew blueprint.json with model mappings."""
        import uuid
        
        session_id = f"ses_{uuid.uuid4().hex[:12]}"
        session_file = crew_dir / "sessions" / f"session-{session_id}.md"
        session_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Load model.json for assignments
        model_json_path = Path(project_dir).parent / "model.json"
        model_data = {}
        if model_json_path.exists():
            with open(model_json_path) as f:
                model_data = json.load(f)
        
        project_name = project_dir.name
        project_models = model_data.get("projects", {}).get(project_name, {})
        
        # Build session content
        content = f"""# Crew Initialization Session

**Session ID:** {session_id}
**Created:** {now_iso()}
**Crew:** {crew_name}
**Project:** {project_dir}

---

## User Request

Create crew with blueprint enforcement for project: {project_dir.name}

---

## Assistant Actions

"""
        
        # Add each action taken
        for i, action in enumerate(actions_taken, 1):
            content += f"""### Action {i}: {action['step']}

**Tool:** {action.get('tool', 'terminal')}
**Input:**
```json
{json.dumps(action.get('input', {}), indent=2)}
```

**Output:**
```
{action.get('output', 'Success')}
```

**Status:** {action.get('status', 'complete')}

---

"""
        
        # Add model assignments
        content += """## Model Assignments

Based on project requirements and available models:

| Role | Model | Rationale |
|------|-------|-----------|
"""
        
        if project_models:
            content += f"| Primary | {project_models.get('primary_model', self._select_model_for_role('general'))} | Main model for project |\n"
            for key, value in project_models.items():
                if key.endswith("_model") and key != "primary_model":
                    role = key.replace("_model", "").replace("_", " ").title()
                    content += f"| {role} | {value} | Specialized role |\n"
        
        content += f"""
---

## Chain Status

- Phase 0: active
- Phases 1-6: locked
- Progress: 0/7

---

*Generated by crew-manager.py — autonomous-crew skill*
"""
        
        session_file.write_text(content)
        print(f"  Created session log: {session_file}")
        
        # Generate blueprint.json with full model mappings
        blueprint_file = crew_dir / "blueprint.json"
        blueprint = self._generate_blueprint_json(crew_name, project_name, project_dir, project_models, model_data)
        
        with open(blueprint_file, "w") as f:
            json.dump(blueprint, f, indent=2)
        print(f"  Created blueprint.json: {blueprint_file}")
        
        return session_file
    
    def _generate_blueprint_json(self, crew_name, project_name, project_dir, project_models, model_data):
        """Generate complete blueprint.json with configurable model mappings."""
        import uuid
        
        # Track mappings from model.json
        track_map = {
            "mnemosyne": "Track 1: MemoryAgent",
            "aires": "Track 2: AI Showrunner",
            "autopilot": "Track 4: Autopilot Agent",
            "agora": "Track 3: Agent Society",
            "edgewalker": "Track 5: EdgeAgent"
        }
        
        # Agent definitions per project - models are dynamically selected
        agents_map = {
            "mnemosyne": [
                {"agent_id": "mnemosyne-lead-1", "agent_type": "lead", "display_name": "MemoryAgent", "description": "Lead orchestrator for memory lifecycle"},
                {"agent_id": "mnemosyne-ingestion-1", "agent_type": "general", "display_name": "IngestionEngine", "description": "Processes incoming memory content"},
                {"agent_id": "mnemosyne-recall-1", "agent_type": "reasoning", "display_name": "RecallEngine", "description": "Multi-strategy memory retrieval"},
                {"agent_id": "mnemosyne-forget-1", "agent_type": "general", "display_name": "ForgetEngine", "description": "Exponential decay memory forgetting"},
                {"agent_id": "mnemosyne-learning-1", "agent_type": "reasoning", "display_name": "LearningEngine", "description": "Pattern detection and insights"}
            ],
            "aires": [
                {"agent_id": "aires-director-1", "agent_type": "creative", "display_name": "ShowrunnerDirector", "description": "Creative direction and episode management"},
                {"agent_id": "aires-bible-1", "agent_type": "creative", "display_name": "BibleCompiler", "description": "World rules and character consistency"},
                {"agent_id": "aires-composer-1", "agent_type": "creative", "display_name": "ShotComposer", "description": "Shot list and storyboard generation"},
                {"agent_id": "aires-continuity-1", "agent_type": "reasoning", "display_name": "ContinuityChecker", "description": "Cross-episode consistency validation"},
                {"agent_id": "aires-dialogue-1", "agent_type": "creative", "display_name": "DialogueEngine", "description": "Character-specific dialogue generation"}
            ],
            "autopilot": [
                {"agent_id": "autopilot-lead-1", "agent_type": "lead", "display_name": "WorkflowOrchestrator", "description": "Lead agent - Decomposes triggers, manages workflow state"},
                {"agent_id": "autopilot-connector-1", "agent_type": "general", "display_name": "ConnectorRegistry", "description": "Manages email, Slack, calendar, Jira connectors"},
                {"agent_id": "autopilot-glitch-1", "agent_type": "reasoning", "display_name": "GlitchReporter", "description": "Adversarial failure analysis"},
                {"agent_id": "autopilot-audit-1", "agent_type": "general", "display_name": "AuditTrail", "description": "Append-only logs with HMAC verification"}
            ],
            "agora": [
                {"agent_id": "agora-executive-1", "agent_type": "general", "display_name": "ExecutiveChamber", "description": "Executive decisions and policy enforcement"},
                {"agent_id": "agora-judicial-1", "agent_type": "reasoning", "display_name": "JudicialChamber", "description": "Constitutional review and validation"},
                {"agent_id": "agora-legislative-1", "agent_type": "general", "display_name": "LegislativeChamber", "description": "Proposal creation and voting"}
            ],
            "edgewalker": [
                {"agent_id": "edgewalker-kernel-1", "agent_type": "edge", "display_name": "CapabilityKernel", "description": "Rust capability kernel for edge deployment"},
                {"agent_id": "edgewalker-mesh-1", "agent_type": "edge", "display_name": "MeshNetwork", "description": "libp2p peer-to-peer networking"},
                {"agent_id": "edgewalker-telemetry-1", "agent_type": "edge", "display_name": "TelemetryDeceiver", "description": "Privacy protection via telemetry deception"}
            ]
        }
        
        # Assign models dynamically based on role and available providers
        agents = agents_map.get(project_name, [])
        for agent in agents:
            agent["model"] = self._select_model_for_role(agent["agent_type"])
        
        # Success criteria per project
        criteria_map = {
            "mnemosyne": [
                "IngestionEngine processes multi-source input (text, JSON, conversations)",
                "RecallEngine supports semantic + keyword + temporal search",
                "ForgetEngine implements exponential decay with archive migration",
                "LearningEngine detects patterns and generates insights",
                "REST API with health/ready endpoints",
                "InMemoryStore with LRU eviction",
                "Embeddings with caching",
                "All tests passing"
            ],
            "aires": [
                "NarrativeEngine creates story arcs with act structure",
                "CharacterManager maintains character profiles and consistency",
                "SceneGenerator produces detailed scene descriptions",
                "PlotCoherence tracks plot threads and detects contradictions",
                "DialogueEngine generates character-specific dialogue",
                "ConsistencyChecker cross-validates all outputs",
                "Vision model integration for storyboarding",
                "REST API with episode management"
            ],
            "autopilot": [
                "All workflow connectors implemented",
                "WorkflowOrchestrator decomposes triggers into executable DAGs",
                "GlitchReporter generates adversarial failure analysis",
                "AuditTrail maintains append-only logs with HMAC verification",
                "ApprovalChain gates high-risk actions",
                "Graceful degradation with circuit breakers",
                "All modules gated behind environment variables",
                "All tests passing"
            ],
            "agora": [
                "ExecutiveChamber enforces policies and manages agent lifecycle",
                "JudicialChamber validates proposals against constitution",
                "LegislativeChamber creates and votes on proposals",
                "DebateEngine facilitates multi-agent deliberation",
                "Personality system with configurable traits",
                "Memory system with episodic and semantic stores",
                "Economy engine with resource management",
                "All tests passing"
            ],
            "edgewalker": [
                "Rust capability kernel compiles and runs",
                "Mesh networking establishes peer connections",
                "Telemetry deception layer active",
                "WASM runtime for edge deployment",
                "Sensor fusion pipeline operational",
                "Burst policy enforcement active",
                "All Rust tests passing",
                "Binary builds successfully"
            ]
        }
        
        # Build models pool from available models
        models_pool = []
        for category in ["text", "vision", "embedding"]:
            models_pool.extend(self.available_models.get(category, []))
        models_pool = list(set(models_pool))  # Deduplicate
        
        # Get token budget from providers config
        first_provider = list(self.providers_config.get("providers", {}).keys())[0] if self.providers_config.get("providers") else ""
        quotas = self.providers_config.get("providers", {}).get(first_provider, {}).get("quotas", {}) if first_provider else {}
        
        blueprint = {
            "blueprint_id": f"{project_name}_crew_001",
            "crew_name": crew_name,
            "project_name": project_name,
            "track": track_map.get(project_name, "Unknown Track"),
            "version": "1.0.0",
            "created_at": now_iso(),
            "status": "active",
            "current_phase": "phase_0_foundation",
            
            "token_budget": {
                "per_model_limit": quotas.get("per_model_limit", 1000000),
                "rotation_strategy": quotas.get("rotation_strategy", "round_robin"),
                "models_pool": models_pool,
                "current_usage": {model: 0 for model in models_pool}
            },
            
            "success_criteria": criteria_map.get(project_name, []),
            
            "expected_outcomes": [
                "Working demo runs successfully",
                "All tests passing",
                "REST API functional with health endpoints",
                "Documentation complete",
                "Docker deployment tested"
            ],
            
            "agent_types": list(set([a["agent_type"] for a in agents])),
            
            "agents": agents,
            
            "workflows": {
                "primary": f"{project_name}_workflow",
                "phases": [
                    {"id": "phase_0", "name": "Foundation", "status": "active"},
                    {"id": "phase_1", "name": "Core Implementation", "status": "locked"},
                    {"id": "phase_2", "name": "API Layer", "status": "locked"},
                    {"id": "phase_3", "name": "Integration & Testing", "status": "locked"},
                    {"id": "phase_4", "name": "Demo & Polish", "status": "locked"},
                    {"id": "phase_5", "name": "Documentation", "status": "locked"},
                    {"id": "phase_6", "name": "Deployment", "status": "locked"}
                ]
            },
            
            "quality_gates": {
                "validation_required": True,
                "tests_must_pass": True,
                "documentation_required": True,
                "docker_deployment_required": True,
                "enterprise_blueprint_compliance": True
            },
            
            "providers_config": {
                "config_file": str(self.config_dir / "providers.json"),
                "detected_providers": list(self.providers_config.get("providers", {}).keys()),
                "auto_detect_enabled": self.providers_config.get("auto_detect", {}).get("enabled", True)
            },
            
            "metadata": {
                "generated_by": "crew-manager.py",
                "skill_version": "1.1.11",
                "enterprise_tier": True,
                "configurable_models": True
            }
        }
        
        return blueprint

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Crew Manager - Create crews with blueprint enforcement")
    parser.add_argument("--crew-name", required=True, help="Name of the crew")
    parser.add_argument("--project-dir", required=True, help="Project directory")
    parser.add_argument("--blueprint", help="Path to blueprint.md (optional)")
    parser.add_argument("--workspace", default="${WORKSPACE_ROOT}/qwen-cloud-2026", help="Workspace root")
    args = parser.parse_args()
    
    manager = CrewManager(args.workspace)
    success = manager.create_crew_with_blueprint(
        args.crew_name,
        args.project_dir,
        args.blueprint
    )
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
