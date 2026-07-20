#!/usr/bin/env python3
"""
Install Identity Skill - Deploy agent-identity-architecture into agent workspace
"""

import argparse
import shutil
from pathlib import Path

def show_help():
    print("""
Install Identity Skill - Deploy agent-identity-architecture into agent workspace

Usage: python3 install-identity-skill.py <workspace> [--help]

Arguments:
  workspace    Agent workspace directory

Options:
  --help       Show this help message

Example:
  python3 install-identity-skill.py \$HOME/agents/ui-a1b2
""")

def main():
    parser = argparse.ArgumentParser(description="Install Identity Skill", add_help=False)
    parser.add_argument("workspace", nargs="?", help="Agent workspace directory")
    parser.add_argument("--help", "-h", action="store_true", help="Show help")
    
    args, _ = parser.parse_known_args()
    
    if args.help or not args.workspace:
        show_help()
        return 0
    
    parser.parse_args()
    
    workspace = Path(args.workspace)
    identity_skill_path = os.environ.get("AGENT_IDENTITY_SKILL", str(Path.home() / ".hermes" / "skills" / "devops" / "agent-identity-architecture"))
    identity_skill = Path(identity_skill_path)
    
    if not identity_skill.exists():
        print("ERROR: agent-identity-architecture skill not found")
        return 1
    
    print(f"=== Installing agent-identity-architecture into {workspace} ===")
    
    # Create directory structure
    for d in ["tools", "skills", "memory/daily", "memory/weekly", "memory/long-term", 
              ".secrets", ".agent/habits", ".agent/logs", ".agent/metrics", 
              ".agent/templates", ".agent/constitutions"]:
        (workspace / d).mkdir(parents=True, exist_ok=True)
    
    # Copy scripts
    for script in identity_skill.glob("scripts/*.py"):
        shutil.copy2(script, workspace / script.name)
    for script in identity_skill.glob("scripts/*.sh"):
        shutil.copy2(script, workspace / script.name)
    
    # Copy templates
    templates_dir = workspace / ".agent" / "templates"
    templates_dir.mkdir(exist_ok=True)
    for tpl in identity_skill.glob("references/templates/*"):
        if tpl.is_file():
            shutil.copy2(tpl, templates_dir / tpl.name)
        else:
            shutil.copytree(tpl, templates_dir / tpl.name, dirs_exist_ok=True)
    
    # Copy habit definitions
    habits_dir = workspace / ".agent" / "habits"
    for habit in identity_skill.glob("references/*habit*.yaml"):
        shutil.copy2(habit, habits_dir / habit.name)
    for habit in identity_skill.glob("references/*enforcement*.yaml"):
        shutil.copy2(habit, habits_dir / habit.name)
    for habit in identity_skill.glob("references/*reflective*.yaml"):
        shutil.copy2(habit, habits_dir / habit.name)
    
    # Create constitution from template
    if (identity_skill / "templates/constitution-template.yaml").exists():
        shutil.copy2(identity_skill / "templates/constitution-template.yaml", 
                     workspace / ".agent" / "constitution.yaml")
    
    # Make tools executable
    for script in workspace.glob("tools/*.sh"):
        script.chmod(0o755)
    for script in workspace.glob("*.sh"):
        script.chmod(0o755)
    
    print("✅ Identity skill installed")
    print("  Next: customize constitution.yaml, then run start-agent.sh")
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())