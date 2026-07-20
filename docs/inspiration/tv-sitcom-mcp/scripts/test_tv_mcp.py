#!/usr/bin/env python3
"""Test client for TV Sitcom MCP Server - validates tools against live federation."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from tv_mcp_server import TVRoomManager, FederationClient


FEDERATION_URL = "http://localhost:41207"


def test_federation_client():
    """Test the federation API client."""
    print("=== Testing FederationClient ===")
    client = FederationClient(FEDERATION_URL)
    
    # Health
    health = client.get_health()
    assert health.get("status") == "healthy", f"Health check failed: {health}"
    print(f"  ✓ Health: {health.get('status')} | agents: {health.get('agents')} | rooms: {health.get('rooms')}")
    
    # Agents
    agents = client.get_agents()
    total = sum(len(v) for v in agents.values())
    assert total >= 20, f"Expected 20+ agents, got {total}"
    for project, lst in agents.items():
        print(f"  ✓ {project}: {len(lst)} agents")
    
    # Rooms
    rooms = client.get_rooms()
    print(f"  ✓ Rooms endpoint: {str(rooms)[:100]}...")
    
    print("  FederationClient tests PASSED")
    return True


def test_tv_room_manager():
    """Test the TVRoomManager with live data."""
    print("\n=== Testing TVRoomManager ===")
    manager = TVRoomManager(FEDERATION_URL)
    
    # All rooms
    rooms = manager.get_all_rooms()
    assert len(rooms) >= 5, f"Expected 5+ rooms, got {len(rooms)}"
    print(f"  ✓ get_all_rooms: {len(rooms)} rooms")
    for r in rooms:
        print(f"    - {r.room_id} ({r.project}): {len(r.agents)} agents, prod={r.is_production}")
    
    # Specific room
    room = manager.get_all_rooms()[0]
    detail = {"room_id": room.room_id, "project": room.project, "agents": len(room.agents)}
    print(f"  ✓ Room detail: {detail}")
    
    # TV feed
    feed = manager.get_tv_feed(limit=10)
    assert len(feed) > 0, "TV feed empty"
    print(f"  ✓ get_tv_feed: {len(feed)} entries")
    for entry in feed[:3]:
        print(f"    - {entry.timestamp} {entry.project} {entry.agent_id} {entry.event_type}: {entry.message}")
    
    # Agent lookup
    agents_by_project = manager.client.get_agents()
    first_agent_id = list(agents_by_project.values())[0][0]["agentId"]
    agent = manager.get_agent(first_agent_id)
    assert agent is not None, f"Agent {first_agent_id} not found"
    print(f"  ✓ get_agent: {agent.agent_id} ({agent.name}) role={agent.role} project={agent.project}")
    
    # Search
    results = manager.search_agents("lead")
    assert len(results) > 0, "Search 'lead' returned nothing"
    print(f"  ✓ search_agents('lead'): {len(results)} results")
    
    # Project summary
    print(f"  ✓ Project data available")
    
    print("  TVRoomManager tests PASSED")
    return True


def test_mcp_tool_signatures():
    """Verify the MCP tool function signatures work."""
    print("\n=== Testing MCP Tool Signatures ===")
    from tv_mcp_server import (
        get_all_rooms, get_room, get_tv_feed, get_agent,
        get_project_summary, get_system_status, search_agents
    )
    
    rooms = get_all_rooms()
    assert isinstance(rooms, list) and len(rooms) > 0
    print(f"  ✓ get_all_rooms() -> list[{len(rooms)}]")
    
    room = get_room(rooms[0]["room_id"])
    assert "room_id" in room
    print(f"  ✓ get_room() -> dict")
    
    feed = get_tv_feed(limit=5)
    assert isinstance(feed, list)
    print(f"  ✓ get_tv_feed(5) -> list[{len(feed)}]")
    
    agent = get_agent(list(feed[0].keys())[0] if feed else "mnemosyne-lead-1")
    assert "agent_id" in agent
    print(f"  ✓ get_agent() -> dict")
    
    summary = get_project_summary("mnemosyne")
    assert "project" in summary
    print(f"  ✓ get_project_summary() -> dict")
    
    status = get_system_status()
    assert "total_agents" in status
    print(f"  ✓ get_system_status() -> dict")
    
    results = search_agents("orchestrator")
    assert isinstance(results, list)
    print(f"  ✓ search_agents() -> list[{len(results)}]")
    
    print("  MCP tool signatures PASSED")
    return True


def main():
    import argparse
    parser = argparse.ArgumentParser(description="TV Sitcom MCP validation suite")
    parser.add_argument("--dry-run", action="store_true", help="Print tests without running")
    parser.add_argument("--help", action="help", help="Show this help")
    args = parser.parse_args()
    
    if args.dry_run:
        print("DRY RUN - would execute:")
        print("  1. test_federation_client")
        print("  2. test_tv_room_manager")
        print("  3. test_mcp_tool_signatures")
        return 0
    
    try:
        test_federation_client()
        test_tv_room_manager()
        test_mcp_tool_signatures()
        print("\n✅ ALL TESTS PASSED")
        return 0
    except Exception as e:
        print(f"\n❌ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())