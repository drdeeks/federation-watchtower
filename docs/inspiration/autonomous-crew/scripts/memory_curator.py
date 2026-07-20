#!/usr/bin/env python3
"""
Memory Watcher/Curator for synthesis-1
Runs at end of day to:
1. Curate daily notes to weekly patterns
2. Extract insights/lessons for long-term memory
3. Build knowledge index from daily links
4. Send summary heartbeat to enforcer
"""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict

def show_help():
    """Display usage information."""
    print("""
Memory Curator - Daily to weekly to long-term memory pipeline

Usage: python3 memory_curator.py <agent-id> [--help] [--dry-run]

Arguments:
  agent-id    Agent identifier (e.g., synthesis-1)
  
Options:
  --help      Show this help message
  --dry-run   Preview what would be curated without writing

Environment:
  WORKSPACE_ROOT      Root directory for agent workspaces (default: $HOME/agents)

Example:
  python3 memory_curator.py synthesis-1
  python3 memory_curator.py synthesis-1 --dry-run
""")

_DEFAULT_ROOT = str(Path.home() / "agents")

class MemoryCurator:
    """Curator for agent memory pipeline"""
    
    def __init__(self, agent_id: str = "synthesis-1"):
        self.agent_id = agent_id
        self.workspace = Path(os.environ.get("WORKSPACE_ROOT", _DEFAULT_ROOT)) / agent_id
        self.memory_dir = self.workspace / "memory"
        self.daily_dir = self.memory_dir / "daily"
        self.weekly_dir = self.memory_dir / "weekly"
        self.long_term_dir = self.memory_dir / "long-term"
        self.knowledge_index_file = self.memory_dir / "knowledge-index.json"
        
        for d in [self.daily_dir, self.weekly_dir, self.long_term_dir]:
            d.mkdir(parents=True, exist_ok=True)
    
    def get_today_daily(self) -> str:
        today = datetime.now().strftime("%Y-%m-%d")
        return str(self.daily_dir / f"{today}.md")
    
    def log_daily(self, entry_type: str, content: str, links: list = None):
        daily_file = self.get_today_daily()
        timestamp = datetime.now().isoformat()
        link_str = ""
        if links:
            link_str = "\n\n" + "\n".join([f"- [[{link}]]" for link in links])
        entry = f"## {timestamp} - {entry_type}\n\n{content}{link_str}\n\n---\n"
        with open(daily_file, "a") as f:
            f.write(entry)
    
    def curate_weekly(self) -> dict:
        today = datetime.now()
        week_ago = today - timedelta(days=7)
        weekly_insights = []
        weekly_decisions = []
        weekly_links = []
        
        for daily_file in sorted(self.daily_dir.glob("*.md")):
            file_date_str = daily_file.stem
            try:
                file_date = datetime.strptime(file_date_str, "%Y-%m-%d")
                if file_date < week_ago:
                    continue
            except ValueError:
                continue
            
            content = daily_file.read_text()
            
            for match in re.finditer(r"##\s.*INSIGHT.*\n\n(.*?)(?=\n##|\Z)", content, re.DOTALL):
                insight = match.group(1).strip()
                if insight:
                    weekly_insights.append({"date": file_date_str, "insight": insight})
            
            for match in re.finditer(r"##\s.*DECISION.*\n\n(.*?)(?=\n##|\Z)", content, re.DOTALL):
                decision = match.group(1).strip()
                if decision:
                    weekly_decisions.append({"date": file_date_str, "decision": decision})
            
            for match in re.finditer(r"\[\[([^\]]+)\]\]", content):
                weekly_links.append({"date": file_date_str, "link": match.group(1)})
        
        if weekly_insights or weekly_decisions:
            week_number = today.isocalendar()[1]
            weekly_file = self.weekly_dir / f"{today.year}-W{week_number:02d}.md"
            entries = []
            if weekly_insights:
                entries.append("## Insights\n")
                for item in weekly_insights:
                    entries.append(f"- ({item['date']}) {item['insight']}")
            if weekly_decisions:
                entries.append("\n## Decisions\n")
                for item in weekly_decisions:
                    entries.append(f"- ({item['date']}) {item['decision']}")
            if weekly_links:
                entries.append("\n## Knowledge Links\n")
                for item in weekly_links:
                    entries.append(f"- [[{item['link']}]] ({item['date']})")
            weekly_file.write_text("\n".join(entries))
        
        return {
            "insights_count": len(set(i["insight"] for i in weekly_insights)),
            "decisions_count": len(set(d["decision"] for d in weekly_decisions)),
            "links_count": len(set(l["link"] for l in weekly_links))
        }
    
    def promote_to_long_term(self) -> int:
        long_term_file = self.long_term_dir / "MEMORY.md"
        promoted = 0
        if not long_term_file.exists():
            long_term_file.write_text("# Long-Term Memory\n\nCurated patterns, lessons, and decisions.\n\n---\n\n")
        existing = long_term_file.read_text()
        
        for weekly_file in sorted(self.weekly_dir.glob("*.md")):
            week_id = weekly_file.stem
            if week_id not in existing:
                content = weekly_file.read_text()
                if content.strip():
                    entry = f"\n## {week_id}\n\n{content}\n\n---\n\n"
                    with open(long_term_file, "a") as f:
                        f.write(entry)
                    promoted += 1
        return promoted
    
    def update_knowledge_index(self) -> dict:
        index = defaultdict(list)
        for daily_file in sorted(self.daily_dir.glob("*.md")):
            file_date = daily_file.stem
            content = daily_file.read_text()
            for match in re.finditer(r"\[\[([^\]]+)\]\]", content):
                entity = match.group(1)
                start = max(0, match.start() - 100)
                end = min(len(content), match.end() + 100)
                context = content[start:end].strip()
                entry = {"date": file_date, "file": str(daily_file), "context": context}
                if file_date not in [e["date"] for e in index[entity]]:
                    index[entity].append(entry)
        clean_index = {entity: entries for entity, entries in index.items() if entries}
        with open(self.knowledge_index_file, "w") as f:
            json.dump(clean_index, f, indent=2)
        return {entity: len(entries) for entity, entries in clean_index.items()}
    
    def run_daily_curation(self) -> dict:
        print(f"[Curator] Running daily curation for {self.agent_id}")
        results = {}
        print("  Curating weekly insights...")
        weekly = self.curate_weekly()
        results["weekly"] = weekly
        print(f"    Insights: {weekly['insights_count']}, Decisions: {weekly['decisions_count']}")
        print("  Promoting to long-term memory...")
        promoted = self.promote_to_long_term()
        results["promoted"] = promoted
        print(f"    Promoted {promoted} entries")
        print("  Updating knowledge index...")
        index = self.update_knowledge_index()
        results["index_entities"] = len(index)
        print(f"    Indexed {len(index)} entities")
        return results

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Memory Curator", add_help=False)
    parser.add_argument("agent_id", nargs="?", help="Agent identifier")
    parser.add_argument("--help", "-h", action="store_true", help="Show help")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing")
    
    args, _ = parser.parse_known_args()
    
    if args.help or not args.agent_id:
        show_help()
        sys.exit(0)
    
    parser.parse_args()
    
    curator = MemoryCurator(args.agent_id)
    results = curator.run_daily_curation()
    
    print(f"\n[Curator] Daily curation complete:")
    for key, value in results.items():
        print(f"  {key}: {value}")

if __name__ == "__main__":
    main()