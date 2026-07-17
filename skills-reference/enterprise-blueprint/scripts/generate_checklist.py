#!/usr/bin/env python3
"""
Checklist Generator
Generates phase-gated checklist from validated blueprint.
"""

import re
import sys
import json
from pathlib import Path


class ChecklistGenerator:
    def __init__(self, blueprint_path, checklist_path=None, sync=False):
        self.blueprint = Path(blueprint_path)
        self.checklist_path = Path(checklist_path) if checklist_path else self.blueprint.with_name("checklist.md")
        self.content = self.blueprint.read_text()
        self.sync = sync

    def extract_phases(self):
        """Extract all phases with their tasks and metadata."""
        phases = []
        
        # Find all PHASE sections
        phase_pattern = r"### PHASE-(\d+)[a-z]?: ([^>\n]+)"
        for match in re.finditer(phase_pattern, self.content):
            phase_num = int(match.group(1))
            title = match.group(2).strip()
            
            # Find rollback tag
            rollback_match = re.search(rf"PHASE-{phase_num}[a-z]?.*?\*\*Rollback Tag:\*\* `\[(PHASE-\d+-v\d+)\]", self.content[match.start():match.start()+2000])
            rollback_tag = rollback_match.group(1) if rollback_match else f"[PHASE-{phase_num}-v1]"
            
            # Find feature flags
            feat_matches = re.findall(r"FEAT_[A-Z_]+", self.content[match.start():match.start()+2000])
            
            # Find tasks (checkboxes)
            section = self.content[match.start():]
            next_phase = re.search(r"### PHASE-\d+", section[1:])
            if next_phase:
                section = section[:next_phase.start()]
            
            tasks = re.findall(r"- \[ \] \*\*PHASE-[\d.]+.*?\*\*(.*?)(?:→|$)", section)
            
            phases.append({
                "number": phase_num,
                "title": title,
                "rollback_tag": rollback_tag,
                "feature_flags": list(set(feat_matches)),
                "tasks": tasks
            })
        
        return phases

    def extract_modules(self):
        """Extract module registry entries."""
        modules = []
        # Find module table
        table_match = re.search(r"\| Module ID \|.*?\n((?:\|.*?\n)+)", self.content)
        if table_match:
            for line in table_match.group(1).split("\n"):
                parts = [p.strip() for p in line.split("|") if p.strip()]
                if len(parts) >= 4 and parts[0].startswith("MOD-"):
                    modules.append({
                        "id": parts[0],
                        "name": parts[1],
                        "purpose": parts[2],
                        "feature_flag": parts[3]
                    })
        return modules

    def extract_screens(self):
        """Extract screen specifications."""
        screens = []
        screen_pattern = r"### Screen (\d+\.\d+) — ([^>]+)"
        for match in re.finditer(screen_pattern, self.content):
            screen_id = match.group(1).replace(".", "-")
            title = match.group(2).strip()
            
            section = self.content[match.start():]
            next_screen = re.search(r"### Screen \d+\.\d+", section[1:])
            if next_screen:
                section = section[:next_screen.start()]
            
            feat_match = re.search(r"FEATURE FLAG \| (FEAT_[A-Z_]+)", section)
            rollback_match = re.search(r"ROLLBACK TAG \| \[([A-Z0-9-]+)\]", section)
            
            screens.append({
                "id": f"SCR-{screen_id}",
                "title": title,
                "feature_flag": feat_match.group(1) if feat_match else "",
                "rollback_tag": rollback_match.group(1) if rollback_match else ""
            })
        return screens

    def generate(self):
        phases = self.extract_phases()
        modules = self.extract_modules()
        screens = self.extract_screens()
        
        lines = []
        lines.append("# Implementation Checklist")
        lines.append(f"\n*Generated from {self.blueprint.name} on {datetime.now().strftime('%Y-%m-%d')}*\n")
        
        # Summary
        lines.append("## Summary")
        lines.append(f"- **Phases:** {len(phases)}")
        lines.append(f"- **Modules:** {len(modules)}")
        lines.append(f"- **Screens:** {len(screens)}")
        lines.append("")
        
        # Phase Tasks
        lines.append("## Phase Checklist")
        lines.append("")
        
        for phase in phases:
            lines.append(f"### {phase['rollback_tag']} — PHASE-{phase['number']}: {phase['title']}")
            lines.append("")
            if phase['feature_flags']:
                lines.append("**Feature Flags:** " + ", ".join(phase['feature_flags']))
                lines.append("")
            
            for i, task in enumerate(phase['tasks'], 1):
                lines.append(f"- [ ] **PHASE-{phase['number']}.{i}** {task.strip()}")
            
            # Add generic validation gate
            lines.append(f"- [ ] **PHASE-{phase['number']}.V** Validation gate: `hemlock test-all` → PASS")
            lines.append("")
        
        # Modules Table
        if modules:
            lines.append("## Module Registry")
            lines.append("")
            lines.append("| Module ID | Name | Purpose | Feature Flag |")
            lines.append("|-----------|------|---------|--------------|")
            for mod in modules:
                lines.append(f"| {mod['id']} | {mod['name']} | {mod['purpose'][:50]}... | {mod['feature_flag']} |")
            lines.append("")
        
        # Screens Table
        if screens:
            lines.append("## Screen Specifications")
            lines.append("")
            lines.append("| Screen ID | Title | Feature Flag | Rollback Tag |")
            lines.append("|-----------|-------|--------------|--------------|")
            for screen in screens:
                lines.append(f"| {screen['id']} | {screen['title']} | {screen['feature_flag']} | {screen['rollback_tag']} |")
            lines.append("")
        
        # Feature Flags Summary
        all_flags = set()
        for phase in phases:
            all_flags.update(phase['feature_flags'])
        
        if all_flags:
            lines.append("## Feature Flags")
            lines.append("")
            lines.append("| Flag | Modules | Screens |")
            lines.append("|------|---------|---------|")
            for flag in sorted(all_flags):
                modules_with = [m['name'] for m in modules if m['feature_flag'] == flag]
                screens_with = [s['id'] for s in screens if s['feature_flag'] == flag]
                lines.append(f"| {flag} | {', '.join(modules_with)} | {', '.join(screens_with)} |")
            lines.append("")
        
        return "\n".join(lines)

    def write(self):
        content = self.generate()
        self.checklist_path.write_text(content)
        print(f"[OK] Checklist written: {self.checklist_path}")
        
        # Count stats
        phases = self.extract_phases()
        modules = self.extract_modules()
        screens = self.extract_screens()
        
        return {
            "phases_found": len(phases),
            "modules_found": len(modules),
            "screens_found": len(screens),
            "sync_mode": self.sync
        }


if __name__ == "__main__":
    import argparse
    from datetime import datetime
    
    parser = argparse.ArgumentParser()
    parser.add_argument("blueprint", help="Path to blueprint markdown file")
    parser.add_argument("--output", "-o", help="Output checklist path")
    parser.add_argument("--sync", action="store_true", help="Sync existing checklist")
    args = parser.parse_args()
    
    gen = ChecklistGenerator(args.blueprint, args.output, args.sync)
    result = gen.write()
    
    print(json.dumps({
        "operation": "generate_checklist",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "status": "success",
        "details": result
    }, indent=2))