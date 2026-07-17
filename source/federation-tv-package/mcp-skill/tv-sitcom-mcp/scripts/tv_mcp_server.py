#!/usr/bin/env python3
"""
TV Sitcom Show MCP Server — Exposes the agent TV room as an MCP server
for external company integration. Now wired to live federation gateway (port 41207).
"""

import asyncio
import json
import os
import sys
from datetime import datetime
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

# FastMCP for MCP server
try:
    from fastmcp import FastMCP
except ImportError:
    print("Installing fastmcp...")
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "fastmcp"], check=True)
    from fastmcp import FastMCP

# Load environment
PORT = int(os.getenv("TV_MCP_PORT", "41208"))
HOST = os.getenv("TV_MCP_HOST", "0.0.0.0")
FEDERATION_URL = os.getenv("FEDERATION_URL", "http://localhost:41207")

# ============================================================================
# Federation API Client
# ============================================================================

class FederationClient:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip('/')
        self._cache = {}
        self._cache_ttl = 5  # seconds
        self._last_fetch = 0

    def _fetch(self, endpoint: str) -> Any:
        """Fetch JSON from federation API with short caching."""
        import time
        now = time.time()
        cache_key = endpoint
        if cache_key in self._cache and (now - self._last_fetch) < self._cache_ttl:
            return self._cache[cache_key]
        
        url = f"{self.base_url}{endpoint}"
        req = Request(url, headers={"Accept": "application/json"})
        try:
            with urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode())
                self._cache[cache_key] = data
                self._last_fetch = now
                return data
        except (URLError, HTTPError, json.JSONDecodeError) as e:
            print(f"[FederationClient] {endpoint} failed: {e}", file=sys.stderr)
            # Return stale cache if available
            return self._cache.get(cache_key, {})

    def get_agents(self) -> Dict[str, List[Dict]]:
        """Returns {projectId: [agent, ...]}"""
        data = self._fetch("/api/agents")
        return (data.get("agents") or {}) if data else {}

    def get_health(self) -> Dict:
        return self._fetch("/health")

    def get_blueprints(self) -> Dict:
        return self._fetch("/api/blueprints")

    def get_rooms(self) -> Dict:
        return self._fetch("/api/rooms")

    def register_agent(self, project_id: str, agent_data: Dict) -> Dict:
        """POST to register agent."""
        url = f"{self.base_url}/api/agents/register"
        payload = json.dumps({**agent_data, "projectId": project_id}).encode()
        req = Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urlopen(req, timeout=5) as resp:
                return json.loads(resp.read().decode())
        except (URLError, HTTPError, json.JSONDecodeError) as e:
            return {"success": False, "error": str(e)}


# ============================================================================
# Data Models (kept for MCP compatibility)
# ============================================================================

@dataclass
class AgentSnapshot:
    agent_id: str
    name: str
    role: str
    project: str
    status: str
    avatar: str
    room: str
    last_seen: str
    metrics: Dict[str, Any]

@dataclass
class RoomSnapshot:
    room_id: str
    project: str
    agents: List[AgentSnapshot]
    capacity: int
    is_production: bool

@dataclass
class TVFeedEntry:
    timestamp: str
    event_type: str
    agent_id: str
    agent_name: str
    project: str
    message: str
    priority: str


# ============================================================================
# TV Room Manager (now backed by federation)
# ============================================================================

class TVRoomManager:
    def __init__(self, federation_url: str):
        self.client = FederationClient(federation_url)
        self.projects = {
            "mnemosyne": {"name": "Mnemosyne", "emoji": "🧠", "color": "#3b82f6"},
            "agora": {"name": "Agora", "emoji": "🏛️", "color": "#f59e0b"},
            "aires": {"name": "Aires", "emoji": "🎬", "color": "#a855f7"},
            "autopilot": {"name": "Autopilot", "emoji": "⚙️", "color": "#22c55e"},
            "edgewalker": {"name": "Edgewalker", "emoji": "⚡", "color": "#ef4444"},
        }
        self.max_per_room = 35

    def _agent_to_snapshot(self, agent: Dict, project_id: str) -> AgentSnapshot:
        """Convert federation agent dict to AgentSnapshot."""
        # Extract avatar emoji from SVG dataUrl or use fallback
        avatar = agent.get("avatar", {})
        avatar_emoji = "🤖"
        if isinstance(avatar, dict):
            # Federation generates SVG avatars; extract first letter or use role emoji
            role = agent.get("role", "agent")
            role_emojis = {
                "lead": "🧠", "orchestration": "🧠", "director": "🎬", "kernel": "⚙️",
                "connector": "🔌", "cynic": "🕵️", "auditor": "📋", "ingestion": "✏️",
                "recall": "🔍", "forget": "🧹", "learning": "📚", "dialogue": "✍️",
                "bible": "📖", "composer": "🎵", "continuity": "🔄", "legislative": "⚖️",
                "executive": "🛡️", "judicial": "👨‍⚖️", "mesh": "🌐", "deception": "🎭"
            }
            avatar_emoji = role_emojis.get(role.lower(), "🤖")
        
        return AgentSnapshot(
            agent_id=agent.get("agentId", "unknown"),
            name=agent.get("name", "Unknown Agent"),
            role=agent.get("role", "agent"),
            project=project_id,
            status=agent.get("status", "unknown"),
            avatar=avatar_emoji,
            room=agent.get("roomId", f"{project_id.upper()}-ROOM-1"),
            last_seen=datetime.fromtimestamp(agent.get("lastSeen", 0) / 1000).isoformat() + "Z" 
                if agent.get("lastSeen") else datetime.utcnow().isoformat() + "Z",
            metrics={
                "tasks_done": 0,
                "errors": 0,
                "capabilities": agent.get("capabilities", [])
            }
        )

    def get_all_rooms(self) -> List[RoomSnapshot]:
        rooms = []
        agents_by_project = self.client.get_agents()
        
        for project_id, project_info in self.projects.items():
            agents = agents_by_project.get(project_id, [])
            if not agents:
                # Still create the room structure even if empty
                rooms.append(RoomSnapshot(
                    room_id=f"{project_id.upper()}-ROOM-1",
                    project=project_id,
                    agents=[],
                    capacity=self.max_per_room,
                    is_production=True
                ))
                continue
            
            # Group agents by room
            rooms_by_id = {}
            for agent in agents:
                room_id = agent.get("roomId", f"{project_id.upper()}-ROOM-1")
                if room_id not in rooms_by_id:
                    rooms_by_id[room_id] = []
                rooms_by_id[room_id].append(agent)
            
            # Ensure at least production room exists
            if f"{project_id.upper()}-ROOM-1" not in rooms_by_id:
                rooms_by_id[f"{project_id.upper()}-ROOM-1"] = []
            
            for idx, (room_id, room_agents) in enumerate(sorted(rooms_by_id.items())):
                snapshots = [self._agent_to_snapshot(a, project_id) for a in room_agents]
                rooms.append(RoomSnapshot(
                    room_id=room_id,
                    project=project_id,
                    agents=snapshots,
                    capacity=self.max_per_room,
                    is_production=(idx == 0)
                ))
        return rooms

    def get_tv_feed(self, limit: int = 50) -> List[TVFeedEntry]:
        """Generate feed from real agent data + timestamps."""
        agents_by_project = self.client.get_agents()
        feed = []
        
        for project_id, agents in agents_by_project.items():
            for agent in agents:
                status = agent.get("status", "unknown")
                registered = agent.get("registeredAt", 0)
                last_seen = agent.get("lastSeen", registered)
                
                # Registration event
                if registered:
                    feed.append(TVFeedEntry(
                        timestamp=datetime.fromtimestamp(registered / 1000).isoformat() + "Z",
                        event_type="agent_registered",
                        agent_id=agent.get("agentId", "unknown"),
                        agent_name=agent.get("name", "Unknown"),
                        project=project_id,
                        message=f"registered as {agent.get('role', 'agent')}",
                        priority="high"
                    ))
                
                # Heartbeat / activity
                if last_seen and last_seen != registered:
                    feed.append(TVFeedEntry(
                        timestamp=datetime.fromtimestamp(last_seen / 1000).isoformat() + "Z",
                        event_type="heartbeat",
                        agent_id=agent.get("agentId", "unknown"),
                        agent_name=agent.get("name", "Unknown"),
                        project=project_id,
                        message=f"active ({status})",
                        priority="low"
                    ))
        
        # Sort by timestamp desc, take limit
        feed.sort(key=lambda x: x.timestamp, reverse=True)
        return feed[:limit]

    def get_agent(self, agent_id: str) -> Optional[AgentSnapshot]:
        agents_by_project = self.client.get_agents()
        for project_id, agents in agents_by_project.items():
            for agent in agents:
                if agent.get("agentId") == agent_id:
                    return self._agent_to_snapshot(agent, project_id)
        return None

    def search_agents(self, query: str) -> List[AgentSnapshot]:
        query = query.lower()
        results = []
        agents_by_project = self.client.get_agents()
        for project_id, agents in agents_by_project.items():
            for agent in agents:
                if (query in agent.get("name", "").lower() or
                    query in agent.get("role", "").lower() or
                    query in project_id.lower() or
                    query in agent.get("agentId", "").lower()):
                    results.append(self._agent_to_snapshot(agent, project_id))
        return results

    def get_system_status(self) -> Dict[str, Any]:
        health = self.client.get_health()
        rooms = self.get_all_rooms()
        total_agents = sum(len(r.agents) for r in rooms)
        active_agents = sum(len([a for a in r.agents if a.status == "active"]) for r in rooms)
        production_rooms = [r for r in rooms if r.is_production]
        
        return {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "federation_status": health.get("status", "unknown"),
            "projects": len(self.projects),
            "total_rooms": len(rooms),
            "production_rooms": len(production_rooms),
            "total_agents": total_agents,
            "active_agents": active_agents,
            "idle_agents": total_agents - active_agents,
            "global_utilization": round(total_agents / (len(rooms) * self.max_per_room) * 100, 1) if rooms else 0,
            "projects": {p: self.projects[p]["name"] for p in self.projects},
            "uptime": health.get("uptime", 0)
        }


# ============================================================================
# MCP Server Setup
# ============================================================================

mcp = FastMCP("TV Sitcom Show")
tv_manager = TVRoomManager(FEDERATION_URL)

# ============================================================================
# MCP Tools (same signatures, now live data)
# ============================================================================

@mcp.tool()
def get_all_rooms() -> List[Dict[str, Any]]:
    """Get all production rooms across all projects with agent counts."""
    rooms = tv_manager.get_all_rooms()
    return [
        {
            "room_id": r.room_id,
            "project": r.project,
            "project_name": tv_manager.projects[r.project]["name"],
            "project_emoji": tv_manager.projects[r.project]["emoji"],
            "agent_count": len(r.agents),
            "capacity": r.capacity,
            "utilization": round(len(r.agents) / r.capacity * 100, 1),
            "is_production": r.is_production,
            "agents": [asdict(a) for a in r.agents[:5]]
        }
        for r in rooms
    ]

@mcp.tool()
def get_room(room_id: str) -> Dict[str, Any]:
    """Get detailed view of a specific production room."""
    rooms = tv_manager.get_all_rooms()
    for r in rooms:
        if r.room_id == room_id:
            return {
                "room_id": r.room_id,
                "project": r.project,
                "project_name": tv_manager.projects[r.project]["name"],
                "project_emoji": tv_manager.projects[r.project]["emoji"],
                "project_color": tv_manager.projects[r.project]["color"],
                "agents": [asdict(a) for a in r.agents],
                "capacity": r.capacity,
                "utilization": round(len(r.agents) / r.capacity * 100, 1),
                "is_production": r.is_production
            }
    return {"error": f"Room {room_id} not found"}

@mcp.tool()
def get_tv_feed(limit: int = 50, project: str = None, priority: str = None) -> List[Dict[str, Any]]:
    """Get live TV feed of agent activity across all projects."""
    feed = tv_manager.get_tv_feed(limit * 2)
    
    if project:
        feed = [f for f in feed if f.project == project]
    if priority:
        feed = [f for f in feed if f.priority == priority]
    
    return [asdict(f) for f in feed[:limit]]

@mcp.tool()
def get_agent(agent_id: str) -> Dict[str, Any]:
    """Get detailed agent profile."""
    agent = tv_manager.get_agent(agent_id)
    if agent:
        return asdict(agent)
    return {"error": f"Agent {agent_id} not found"}

@mcp.tool()
def get_project_summary(project: str) -> Dict[str, Any]:
    """Get summary stats for a project."""
    if project not in tv_manager.projects:
        return {"error": f"Project {project} not found"}
    
    rooms = tv_manager.get_all_rooms()
    project_rooms = [r for r in rooms if r.project == project]
    total_agents = sum(len(r.agents) for r in project_rooms)
    active_agents = sum(len([a for a in r.agents if a.status == "active"]) for r in project_rooms)
    
    return {
        "project": project,
        "name": tv_manager.projects[project]["name"],
        "emoji": tv_manager.projects[project]["emoji"],
        "color": tv_manager.projects[project]["color"],
        "rooms": len(project_rooms),
        "total_agents": total_agents,
        "active_agents": active_agents,
        "utilization": round(total_agents / (len(project_rooms) * 35) * 100, 1) if project_rooms else 0
    }

@mcp.tool()
def get_system_status() -> Dict[str, Any]:
    """Get overall system health and stats."""
    return tv_manager.get_system_status()

@mcp.tool()
def search_agents(query: str) -> List[Dict[str, Any]]:
    """Search agents by name, role, or project."""
    results = tv_manager.search_agents(query)
    return [asdict(a) for a in results]

# Register agent tool (write operation)
@mcp.tool()
def register_agent(project_id: str, agent_id: str, name: str, role: str, capabilities: List[str] = None) -> Dict[str, Any]:
    """Register a new agent with the federation."""
    return tv_manager.client.register_agent(project_id, {
        "agentId": agent_id,
        "name": name,
        "role": role,
        "capabilities": capabilities or []
    })


# ============================================================================
# MCP Resources (for static data)
# ============================================================================

@mcp.resource("config://projects")
def projects_config() -> str:
    """Projects configuration."""
    return json.dumps({
        pid: {
            "name": info["name"],
            "emoji": info["emoji"],
            "color": info["color"]
        }
        for pid, info in tv_manager.projects.items()
    }, indent=2)

@mcp.resource("config://rooms")
def rooms_config() -> str:
    """Rooms configuration schema."""
    return json.dumps({
        "max_per_room": tv_manager.max_per_room,
        "projects": {p: {"rooms": 3} for p in tv_manager.projects}
    }, indent=2)

@mcp.resource("status://federation")
def federation_status() -> str:
    """Real-time federation health."""
    return json.dumps(tv_manager.get_system_status(), indent=2)


# ============================================================================
# Entry Point
# ============================================================================

def main():
    import argparse
    parser = argparse.ArgumentParser(description="TV Sitcom Show MCP Server")
    parser.add_argument("--host", default="0.0.0.0", help="Bind host")
    parser.add_argument("--port", type=int, default=41208, help="Bind port")
    parser.add_argument("--federation", default="http://localhost:41207", help="Federation gateway URL")
    parser.add_argument("--help", action="help", help="Show this help message")
    args = parser.parse_args()
    
    # Update globals for the manager
    global FEDERATION_URL, HOST, PORT, tv_manager
    FEDERATION_URL = args.federation
    HOST = args.host
    PORT = args.port
    tv_manager = TVRoomManager(FEDERATION_URL)
    
    print(f"Starting TV Sitcom Show MCP Server on {HOST}:{PORT}")
    print(f"  → Federation gateway: {FEDERATION_URL}")
    print("  → MCP tools: get_all_rooms, get_room, get_tv_feed, get_agent, get_project_summary, get_system_status, search_agents, register_agent")
    print("  → MCP resources: config://projects, config://rooms, status://federation")
    mcp.run(transport="streamable-http", host=HOST, port=PORT)

if __name__ == "__main__":
    main()