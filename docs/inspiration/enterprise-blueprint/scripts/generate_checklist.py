#!/usr/bin/env python3
"""
generate_checklist.py — Unified checklist lifecycle tool.
SINGLE source of truth for blueprint lifecycle management.

After generation (checklist.md + checklist-data.json), the blueprint is NEVER
referenced again. Everything runs from checklist-data.json.

Subcommands:
    generate (default)  Parse blueprint, write checklist.md + checklist-data.json
    init                Build enforcement chain from existing checklist-data.json
    verify              Verify a phase step
    complete            Complete a phase step
    status              Show chain state
    check               Check step status
    menu                Interactive chain menu
    generate-validators Generate phase validators from blueprint data
"""

import re
import sys
import json
import argparse
import subprocess
from pathlib import Path
from datetime import datetime, timezone
from dataclasses import dataclass, asdict, field
from typing import List, Dict, Optional, Any, Tuple

from skill_paths import resolve_loop_enforcer


# ─── CONFIG ───────────────────────────────────────────────────────────────────

CHAIN_PY = resolve_loop_enforcer()

SKILL_ROOT = Path(__file__).parent.parent

# ─── DATA MODELS ──────────────────────────────────────────────────────────────

@dataclass
class Task:
    id: str
    description: str
    deliverable: str = ""
    validation: str = ""
    rollback: str = ""
    prerequisite: str = ""
    feature_flag: str = ""

@dataclass
class Phase:
    number: int
    title: str
    tag: str = ""
    flag: str = ""
    tasks: List[Task] = field(default_factory=list)

@dataclass
class Module:
    id: str
    name: str
    purpose: str
    feature_flag: str

@dataclass
class Screen:
    id: str
    title: str
    feature_flag: str
    rollback_tag: str

@dataclass
class ChecklistData:
    """Complete structured data — single source of truth for all enforcement."""
    blueprint: str
    generated: str
    project_name: str
    phases: List[Phase]
    modules: List[Module]
    screens: List[Screen]
    feature_flags: Dict[str, Any] = field(default_factory=dict)
    phases_data: List[Dict] = field(default_factory=list)
    enforcement: Dict[str, Any] = field(default_factory=lambda: {
        "mode": "loop",
        "validators": False,
        "auto_verify": False,
        "phase_gates": True
    })

    def to_dict(self) -> dict:
        return {
            "blueprint": self.blueprint,
            "generated": self.generated,
            "project_name": self.project_name,
            "phases": [asdict(p) for p in self.phases],
            "modules": [asdict(m) for m in self.modules],
            "screens": [asdict(s) for s in self.screens],
            "feature_flags": self.feature_flags,
            "phases_data": self.phases_data,
            "enforcement": self.enforcement,
        }

    @classmethod
    def from_dict(cls, data: dict) -> 'ChecklistData':
        phases = []
        for p in data.get("phases", []):
            tasks = [Task(**t) for t in p.pop("tasks", [])]
            phase = Phase(**p, tasks=tasks)
            phases.append(phase)
        modules = [Module(**m) for m in data.get("modules", [])]
        screens = [Screen(**s) for s in data.get("screens", [])]
        return cls(
            blueprint=data.get("blueprint", ""),
            generated=data.get("generated", ""),
            project_name=data.get("project_name", ""),
            phases=phases,
            modules=modules,
            screens=screens,
            feature_flags=data.get("feature_flags", {}),
            phases_data=data.get("phases_data", []),
            enforcement=data.get("enforcement", {"mode": "loop", "validators": False, "auto_verify": False, "phase_gates": True}),
        )


# ─── BLUEPRINT CHECKLIST GENERATOR ──────────────────────────────────────────

class ChecklistGenerator:
    """Parses blueprint ONCE, produces checklist.md + checklist-data.json."""

    def __init__(self, blueprint_path: Path, output_dir: Path = None):
        self.blueprint = Path(blueprint_path)
        self.output_dir = output_dir or self.blueprint.parent
        if self.blueprint.exists():
            self.content = self.blueprint.read_text()
        else:
            self.content = ""

    def extract_project_name(self) -> str:
        h1 = re.search(r"^#\s+(.+)$", self.content, re.MULTILINE)
        if h1:
            title = h1.group(1).strip()
            title = re.sub(r"\s*[—-]\s*ENTERPRISE BLUEPRINT\s*$", "", title, flags=re.IGNORECASE)
            return title.strip()
        fm = re.search(r"Project\s*:\s*`?([^`\n]+)`?", self.content)
        if fm:
            return fm.group(1).strip()
        return self.blueprint.stem.replace("blueprint", "").strip("-_")

    def extract_phases(self) -> List[Phase]:
        phases = []

        # Extract Part VI tables (authoritative deliverable source)
        part_vi = ""
        pvi = re.search(r"## PART VI.*?(?=\n## [A-Z]|$)", self.content, re.DOTALL | re.IGNORECASE)
        if pvi:
            part_vi = pvi.group(0)

        phase_headers = list(re.finditer(r"### PHASE-(\d+)[a-z]?: ([^>\n]+)", self.content))

        for match in phase_headers:
            phase_num = int(match.group(1))
            title = match.group(2).strip()

            # Phase section from header to next header
            section = self.content[match.start():]
            nxt = re.search(r"### PHASE-\d+", section[1:])
            if nxt:
                section = section[:nxt.start()]

            # Parse metadata
            tag = ""
            flag = ""
            tg = re.search(r"\*\*(?:Section )?Tag:\*\*\s*`?([^`\n]+)`?", section)
            if tg:
                tag = tg.group(1).strip()
            fl = re.search(r"\*\*(?:Feature )?Flag:\*\*\s*`?([^`\n]+)`?", section)
            if fl:
                flag = fl.group(1).strip()

            # Tasks from Part VI table
            tasks = []
            if part_vi:
                tbl = re.search(
                    rf"### PHASE-{phase_num}: [^\n]*\n\| Prerequisite \| Feature Flag \| Deliverables \| Validation Gate \| Rollback \|\n\|[-:]+\|[-:]+\|[-:]+\|[-:]+\|[-:]+\|\n((?:\|.*\|\n)+)",
                    part_vi
                )
                if tbl:
                    for row in tbl.group(1).strip().split("\n"):
                        parts = [p.strip() for p in row.split("|") if p.strip()]
                        if len(parts) >= 5:
                            prereq, fflag, deliverable, val, rb = parts[:5]
                            # Each deliverable gets its own task
                            for d in re.split(r"[,;]", deliverable):
                                d = d.strip()
                                if d and not d.startswith("```") and d != "N/A":
                                    tid = f"PHASE-{phase_num}.{len(tasks)+1}"
                                    tasks.append(Task(
                                        id=tid, description=d, deliverable=d,
                                        validation=val, rollback=rb,
                                        prerequisite=prereq, feature_flag=fflag
                                    ))

            # Fallback: checkbox tasks
            if not tasks:
                for j, tm in enumerate(re.finditer(r"- \[ \] \*\*PHASE-[\d.]+\*\*\s*(.*)", section)):
                    tasks.append(Task(
                        id=f"PHASE-{phase_num}.{j+1}",
                        description=tm.group(1).strip()
                    ))

            phases.append(Phase(
                number=phase_num, title=title, tag=tag, flag=flag, tasks=tasks
            ))

        return phases

    def extract_modules(self) -> List[Module]:
        modules = []
        mt = re.search(r"\| Module ID \|.*?\n((?:\|.*?\n)+)", self.content)
        if mt:
            for line in mt.group(1).split("\n"):
                parts = [p.strip() for p in line.split("|") if p.strip()]
                if len(parts) >= 4 and parts[0].startswith("MOD-"):
                    modules.append(Module(id=parts[0], name=parts[1], purpose=parts[2], feature_flag=parts[3]))
        return modules

    def extract_screens(self) -> List[Screen]:
        screens = []
        for m in re.finditer(r"### Screen (\d+\.\d+) — ([^>\n]+)", self.content):
            sid = m.group(1).replace(".", "-")
            title = m.group(2).strip()
            sec = self.content[m.start():]
            nxt = re.search(r"### Screen \d+\.\d+", sec[1:])
            if nxt:
                sec = sec[:nxt.start()]
            fm = re.search(r"FEATURE FLAG \| (FEAT_[A-Z_]+)", sec)
            rm = re.search(r"ROLLBACK TAG \| \[([A-Z0-9-]+)\]", sec)
            screens.append(Screen(
                id=f"SCR-{sid}", title=title,
                feature_flag=fm.group(1) if fm else "",
                rollback_tag=rm.group(1) if rm else ""
            ))
        return screens

    def build_feature_flags(self, phases: List[Phase], modules: List[Module], screens: List[Screen]) -> Dict[str, Any]:
        flags = {}
        for p in phases:
            for f in p.flag.split(","):
                f = f.strip()
                if f:
                    flags.setdefault(f, {"phases": [], "modules": [], "screens": []})
                    flags[f]["phases"].append(f"PHASE-{p.number}")
        for m in modules:
            if m.feature_flag:
                flags.setdefault(m.feature_flag, {"phases": [], "modules": [], "screens": []})
                flags[m.feature_flag]["modules"].append(m.name)
        for s in screens:
            if s.feature_flag:
                flags.setdefault(s.feature_flag, {"phases": [], "modules": [], "screens": []})
                flags[s.feature_flag]["screens"].append(s.id)
        return flags

    def generate_checklist_md(self, data: ChecklistData) -> str:
        lines = []
        lines.append("# Implementation Checklist")
        lines.append(f"\n*Generated from `{data.blueprint}` on {data.generated}*\n")

        total_tasks = sum(len(p.tasks) for p in data.phases)
        lines.append("## Summary")
        lines.append(f"- **Project:** {data.project_name}")
        lines.append(f"- **Phases:** {len(data.phases)}")
        lines.append(f"- **Tasks:** {total_tasks}")
        lines.append(f"- **Modules:** {len(data.modules)}")
        lines.append(f"- **Screens:** {len(data.screens)}")
        lines.append(f"- **Mode:** {data.enforcement.get('mode', 'loop')}")
        lines.append(f"- **Validators:** {'enabled' if data.enforcement.get('validators') else 'disabled'}")
        lines.append("")

        lines.append("## Phase Checklist\n")
        for p in data.phases:
            tag = f"[PHASE-{p.number}-v1]"
            lines.append(f"### {tag} — PHASE-{p.number}: {p.title}\n")
            if p.flag:
                lines.append(f"**Flag:** `{p.flag}`\n")
            for t in p.tasks:
                lines.append(f"- [ ] **{t.id}** {t.description}")
                if t.deliverable and t.deliverable != t.description:
                    lines.append(f"    - *Deliverable:* `{t.deliverable}`")
                if t.validation:
                    lines.append(f"    - *Gate:* `{t.validation}`")
                if t.rollback:
                    lines.append(f"    - *Rollback:* `{t.rollback}`")
            lines.append("")

        if data.modules:
            lines.append("## Module Registry\n| Module ID | Name | Purpose | Flag |\n|---|---|---|---|")
            for m in data.modules:
                lines.append(f"| {m.id} | {m.name} | {m.purpose[:50]} | {m.feature_flag} |")
            lines.append("")

        if data.screens:
            lines.append("## Screens\n| ID | Title | Flag | Rollback |\n|---|---|---|---|")
            for s in data.screens:
                lines.append(f"| {s.id} | {s.title} | {s.feature_flag} | {s.rollback_tag} |")
            lines.append("")

        if data.feature_flags:
            lines.append("## Feature Flags\n| Flag | Phases | Modules | Screens |\n|---|---|---|---|")
            for f, ref in data.feature_flags.items():
                lines.append(f"| {f} | {', '.join(ref['phases'])} | {', '.join(ref['modules'])} | {', '.join(ref['screens'])} |")
            lines.append("")

        return "\n".join(lines)

    def generate(self, enforcement_mode: str = "loop", enable_validators: bool = False) -> ChecklistData:
        phases = self.extract_phases()
        modules = self.extract_modules()
        screens = self.extract_screens()
        feature_flags = self.build_feature_flags(phases, modules, screens)
        project_name = self.extract_project_name()

        phases_data = []
        for p in phases:
            pd = {"deliverables": [], "flag": p.flag}
            for t in p.tasks:
                if t.deliverable and t.deliverable != "validation_gate":
                    pd["deliverables"].append({
                        "id": t.id, "deliverable": t.deliverable,
                        "validation": t.validation, "rollback": t.rollback,
                        "prerequisite": t.prerequisite, "feature_flag": t.feature_flag
                    })
            phases_data.append(pd)

        data = ChecklistData(
            blueprint=str(self.blueprint),
            generated=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            project_name=project_name,
            phases=phases,
            modules=modules,
            screens=screens,
            feature_flags=feature_flags,
            phases_data=phases_data,
            enforcement={
                "mode": enforcement_mode,
                "validators": enable_validators,
                "auto_verify": False,
                "phase_gates": True
            }
        )
        return data

    def write(self, data: ChecklistData) -> Dict[str, Any]:
        cl_md = self.output_dir / "checklist.md"
        cl_md.write_text(self.generate_checklist_md(data))
        print(f"[OK] Checklist written: {cl_md}")

        cl_json = self.output_dir / "checklist-data.json"
        cl_json.write_text(json.dumps(data.to_dict(), indent=2))
        print(f"[OK] Data written: {cl_json}")

        return {
            "checklist_md": str(cl_md),
            "checklist_json": str(cl_json),
            "phases_found": len(data.phases),
            "modules_found": len(data.modules),
            "screens_found": len(data.screens),
            "mode": data.enforcement["mode"],
            "validators": data.enforcement["validators"],
        }


# ─── CHAIN ENFORCEMENT ────────────────────────────────────────────────────────

def load_checklist(project_dir: Path) -> ChecklistData:
    """Load single source of truth from checklist-data.json."""
    data_path = project_dir / "checklist-data.json"
    if not data_path.exists():
        print(f"Error: checklist-data.json not found in {project_dir}", file=sys.stderr)
        sys.exit(1)
    return ChecklistData.from_dict(json.loads(data_path.read_text()))


def run_chain(project_dir: Path, chain_name: str, subcmd: str, *args) -> dict:
    cmd = [sys.executable, str(CHAIN_PY), subcmd, str(project_dir), chain_name] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout.strip()
    if out:
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return {"output": out, "exit_code": r.returncode}
    return {"error": r.stderr.strip(), "exit_code": r.returncode}


def _phase_name(phase: Phase) -> str:
    return phase.title[:30].replace(" ", "-").replace(":", "").replace("/", "-")


def _chain_name(data: ChecklistData) -> str:
    """Filesystem-safe chain name from project data (max ~128 chars)."""
    raw_name = data.project_name.strip()
    safe_name = re.sub(r"[^\w\- ]", "", raw_name)
    safe_name = re.sub(r"\s+", "-", safe_name)
    safe_name = safe_name[:80].strip("-")
    return f"blueprint-{safe_name}" if safe_name else f"blueprint-{data.generated[:10]}"


def create_chain(project_dir: Path, data: ChecklistData, enable_validators: bool = False) -> Tuple[bool, str]:
    """Build enforcement chain from checklist-data.json."""
    chain_name = _chain_name(data)
    chain_dir = project_dir / ".blueprint-chain"
    chain_dir.mkdir(parents=True, exist_ok=True)

    # Clear old chain state so init is always fresh
    old_state_files = list((project_dir / ".chain").glob(f"{chain_name}.json"))
    if old_state_files:
        for f in old_state_files:
            f.unlink()
            print(f"[OK] Cleared old chain state: {f}")
    old_log_files = list((project_dir / ".chain").glob(f"{chain_name}.log"))
    if old_log_files:
        for f in old_log_files:
            f.unlink()

    step_files: List[str] = []
    step_validators: Dict[str, str] = {}

    # Generate validators if enabled
    if enable_validators:
        from blueprint_validator_gen import generate_all_validators
        vdir = chain_dir / "validators"
        vdir.mkdir(parents=True, exist_ok=True)
        bp = project_dir / "blueprint.md"
        if bp.exists():
            generated = generate_all_validators(bp, vdir)
            print(f"Generated {len(generated)} blueprint-driven validators")
        else:
            print(f"[WARN] blueprint.md not found at {bp}, cannot generate validators")

    for i, phase in enumerate(data.phases):
        pname = _phase_name(phase)

        # Phase gate
        pf = chain_dir / f"phase-{i:02d}-{pname}"
        pf.touch()
        step_files.append(str(pf))

        # Phase tasks
        for j, task in enumerate(phase.tasks):
            sn = f"{task.id}--{task.deliverable[:40] if task.deliverable else task.description[:40]}"
            sn = sn.replace(" ", "-").replace(":", "").replace("/", "-").replace("--", "-").strip("-")
            sf = chain_dir / f"phase-{i:02d}-step-{j+1:02d}-{sn}"
            sf.touch()
            step_files.append(str(sf))

        # Validation gate
        gf = chain_dir / f"phase-{i:02d}-step-{len(phase.tasks)+1:02d}-PHASE-{i}-V-Validation-gate"
        gf.touch()
        step_files.append(str(gf))

        # Assign validator to gate if enabled
        if enable_validators:
            vf = chain_dir / "validators" / f"validate_phase{i}_blueprint.py"
            if vf.exists():
                step_validators[str(gf)] = str(vf)

    # Save validator mapping
    if step_validators:
        (chain_dir / "validators.json").write_text(json.dumps(step_validators))

    if not step_files:
        return False, "0 steps generated — check phase extraction"

    # Create chain via chain.py
    result = run_chain(project_dir, chain_name, "create", *step_files)
    if "error" in result or result.get("exit_code", 0) != 0:
        return False, result.get("error") or result.get("output") or f"chain create failed (exit {result.get('exit_code')})"

    return True, chain_name


def get_status(project_dir: Path, chain_name: str) -> dict:
    return run_chain(project_dir, chain_name, "status")


def verify_step(project_dir: Path, chain_name: str, step_path: str) -> dict:
    """Verify a step — use validator from validators.json if one exists."""
    chain_dir = project_dir / ".blueprint-chain"
    vm = chain_dir / "validators.json"

    if vm.exists():
        validators = json.loads(vm.read_text())
        if step_path in validators:
            sv = subprocess.run(
                [sys.executable, str(CHAIN_PY), "set-validator", str(project_dir), chain_name, step_path, validators[step_path]],
                capture_output=True
            )

    return run_chain(project_dir, chain_name, "verify", step_path)


def complete_step(project_dir: Path, chain_name: str, step_path: str, auto_verify: bool = False) -> dict:
    if auto_verify:
        v = verify_step(project_dir, chain_name, step_path)
        if not v.get("ok") or v.get("state") != "verified":
            return {"verified": v, "completed": None}
    return run_chain(project_dir, chain_name, "complete", step_path)


def check_step(project_dir: Path, chain_name: str, step_path: str) -> dict:
    return run_chain(project_dir, chain_name, "check", step_path)


def resolve_step_path(project_dir: Path, data: ChecklistData, phase_idx: int, step_idx: int) -> Path:
    """Resolve step file path matching how create_chain names files."""
    chain_dir = project_dir / ".blueprint-chain"
    phase = data.phases[phase_idx]
    pname = _phase_name(phase)

    if step_idx == 0:
        return chain_dir / f"phase-{phase_idx:02d}-{pname}"

    num_tasks = len(phase.tasks)
    if 1 <= step_idx <= num_tasks:
        task = phase.tasks[step_idx - 1]
        sn = f"{task.id}--{task.deliverable[:40] if task.deliverable else task.description[:40]}"
        sn = sn.replace(" ", "-").replace(":", "").replace("/", "-").replace("--", "-").strip("-")
        return chain_dir / f"phase-{phase_idx:02d}-step-{step_idx:02d}-{sn}"

    if step_idx == num_tasks + 1:
        return chain_dir / f"phase-{phase_idx:02d}-step-{step_idx:02d}-PHASE-{phase_idx}-V-Validation-gate"

    raise ValueError(f"Step index {step_idx} out of range for phase {phase_idx}")


# ─── VALIDATOR GENERATION ─────────────────────────────────────────────────────

def generate_validators(project_dir: Path) -> int:
    """Generate blueprint-driven validators from blueprint.md."""
    from blueprint_validator_gen import generate_all_validators
    vdir = project_dir / ".blueprint-chain" / "validators"
    vdir.mkdir(parents=True, exist_ok=True)
    generated = generate_all_validators(project_dir / "blueprint.md", vdir)
    return len(generated)


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Unified checklist lifecycle: generate, enforce, verify, complete",
    )

    # First positional: subcommand or blueprint/project-dir
    parser.add_argument("action", nargs="?", default=None,
                        help="Subcommand (generate|init|status|phase|menu|generate-validators) or blueprint.md path")

    # Options (shared across subcommands)
    parser.add_argument("--output-dir", "-o", help="Output directory (generate)")
    parser.add_argument("--mode", choices=["plain", "loop", "agent", "crew"], default="loop",
                        help="Enforcement mode (generate)")
    parser.add_argument("--with-validators", action="store_true",
                        help="Enable blueprint-driven validators (init, generate)")
    parser.add_argument("--project-name", help="Override project name (generate)")
    parser.add_argument("--project-dir", help="Project directory (init|status|phase|menu|generate-validators)")
    parser.add_argument("--phase", type=int, help="Phase index (phase)")
    parser.add_argument("--step", type=int, default=0, help="Step index (phase)")
    parser.add_argument("--verify", action="store_true", help="Verify step (phase)")
    parser.add_argument("--complete", action="store_true", help="Complete step (phase)")
    parser.add_argument("--check", action="store_true", help="Check step status (phase)")
    parser.add_argument("--auto-verify", action="store_true", help="Auto-verify before complete (phase)")
    parser.add_argument("--json", action="store_true", help="JSON output")
    # Legacy compat (silently accepted)
    parser.add_argument("--blueprint", help=argparse.SUPPRESS)
    parser.add_argument("--init", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--status", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--menu", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--generate-validators", action="store_true", help=argparse.SUPPRESS)

    args = parser.parse_args()

    # Determine subcommand
    action = args.action if args.action else ""
    subcommand = action  # may be overridden below

    # If action is a file path ending in .md → generate
    if action.endswith(".md") or args.blueprint:
        subcommand = "generate"
    elif args.init:
        subcommand = "init"
    elif args.status:
        subcommand = "status"
    elif args.menu:
        subcommand = "menu"
    elif args.generate_validators:
        subcommand = "generate-validators"
    elif args.phase is not None:
        subcommand = "phase"

    if subcommand == "generate":
        bp = args.blueprint or action
        if not bp.endswith(".md"):
            # Try as project dir with blueprint.md
            bp = Path(bp) / "blueprint.md" if Path(bp).is_dir() else Path(bp)
        bp_path = Path(bp)
        if not bp_path.exists():
            print(f"Error: blueprint not found: {bp_path}", file=sys.stderr)
            sys.exit(1)
        output_dir = Path(args.output_dir) if args.output_dir else bp_path.parent
        gen = ChecklistGenerator(bp_path, output_dir)
        data = gen.generate(enforcement_mode=args.mode, enable_validators=args.with_validators)
        if args.project_name:
            data.project_name = args.project_name
        result = gen.write(data)
        print(json.dumps({"operation": "generate", "status": "ok", "details": result}, indent=2))

    elif subcommand == "init":
        project_dir = Path(args.project_dir or action).resolve()
        data = load_checklist(project_dir)
        ok, msg = create_chain(project_dir, data, enable_validators=args.with_validators)
        if ok:
            result = {"ok": True, "chain": msg, "phases": len(data.phases)}
        else:
            result = {"ok": False, "error": msg}
        print(json.dumps(result) if args.json else json.dumps(result, indent=2))
        if not ok:
            sys.exit(1)

    elif subcommand == "status":
        project_dir = Path(args.project_dir or action).resolve()
        data = load_checklist(project_dir)
        chain_name = _chain_name(data)
        status = get_status(project_dir, chain_name)
        print(json.dumps(status) if args.json else json.dumps(status, indent=2))

    elif subcommand == "phase":
        project_dir = Path(args.project_dir or action).resolve()
        data = load_checklist(project_dir)
        chain_name = _chain_name(data)

        if args.phase is None or args.phase >= len(data.phases):
            print(f"Error: phase {args.phase} out of range (0-{len(data.phases)-1})", file=sys.stderr)
            sys.exit(1)

        step_idx = args.step if args.step is not None else 0
        step_path = resolve_step_path(project_dir, data, args.phase, step_idx)

        if not step_path.exists():
            print(f"Error: step file not found: {step_path}", file=sys.stderr)
            sys.exit(1)

        sp = str(step_path)

        if args.check:
            result = check_step(project_dir, chain_name, sp)
        elif args.verify:
            result = verify_step(project_dir, chain_name, sp)
        elif args.complete:
            result = complete_step(project_dir, chain_name, sp, auto_verify=args.auto_verify)
        else:
            result = check_step(project_dir, chain_name, sp)

        print(json.dumps(result) if args.json else json.dumps(result, indent=2))

    elif subcommand == "menu":
        project_dir = Path(args.project_dir or action).resolve()
        data = load_checklist(project_dir)
        chain_name = _chain_name(data)
        subprocess.run([sys.executable, str(CHAIN_PY), "menu", str(project_dir), chain_name])

    elif subcommand == "generate-validators":
        project_dir = Path(args.project_dir or action).resolve()
        count = generate_validators(project_dir)
        result = {"ok": True, "validators_generated": count}
        print(json.dumps(result) if args.json else json.dumps(result, indent=2))

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
