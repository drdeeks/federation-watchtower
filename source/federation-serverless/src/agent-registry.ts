import { DurableObject } from "cloudflare:workers";

export type WatchtowerEnv = Env & {
  WATCHTOWER_ALERT_WEBHOOK_URL?: string;
  WATCHTOWER_ALERT_WEBHOOK_SECRET?: string;
};

export interface Agent {
  id: string;
  projectId: string;
  agentId: string;
  name: string;
  role?: string;
  capabilities: string[];
  status: 'active' | 'idle' | 'busy' | 'offline';
  roomId?: string;
  avatarUrl?: string;
  metadata: Record<string, unknown>;
  registeredAt: number;
  lastHeartbeat?: number;
  updatedAt: number;
}

export interface Room {
  id: string;
  projectId: string;
  roomIndex: number;
  capacity: number;
  createdAt: number;
}

export interface FeedEvent {
  id?: number;
  projectId: string;
  eventType: string;
  agentId?: string;
  message: string;
  priority: 'low' | 'normal' | 'high' | 'critical';
  metadata?: Record<string, unknown>;
  timestamp: number;
}

export interface HealthCheckResult {
  healthy: boolean;
  projectId: string;
  agents: number;
  rooms: number;
  timestamp: number;
}

const MAX_AGENTS_PER_ROOM = 35;

export class AgentRegistry extends DurableObject<WatchtowerEnv> {
  private projectId: string;
  private db: D1Database;

  constructor(ctx: DurableObjectState, env: WatchtowerEnv) {
    super(ctx, env);
    this.projectId = ctx.id.name.replace(/-registry$/, "");
    this.db = env.DB;
  }

  async initialize(): Promise<void> {
    const roomCount = await this.db.prepare(
      `SELECT COUNT(*) as cnt FROM rooms WHERE project_id = ?`
    ).bind(this.projectId).first<{ cnt: number }>();
    if (!roomCount || roomCount.cnt === 0) await this.createRoom(0);
  }

  async healthCheck(): Promise<HealthCheckResult> {
    const [agentCount, roomCount] = await Promise.all([
      this.db.prepare(`SELECT COUNT(*) as cnt FROM agents WHERE project_id = ?`).bind(this.projectId).first<{ cnt: number }>(),
      this.db.prepare(`SELECT COUNT(*) as cnt FROM rooms WHERE project_id = ?`).bind(this.projectId).first<{ cnt: number }>(),
    ]);
    return { healthy: true, projectId: this.projectId, agents: agentCount?.cnt || 0, rooms: roomCount?.cnt || 0, timestamp: Date.now() };
  }

  private async createRoom(roomIndex: number): Promise<string> {
    const roomId = `${this.projectId}:room-${roomIndex}`;
    const now = Date.now();
    await this.db.prepare(`INSERT INTO rooms (id, project_id, room_index, capacity, created_at) VALUES (?, ?, ?, ?, ?)`)
      .bind(roomId, this.projectId, roomIndex, MAX_AGENTS_PER_ROOM, now).run();
    return roomId;
  }

  private async assignToRoom(): Promise<string> {
    const rooms = await this.db.prepare(`
      SELECT r.id, r.capacity, (SELECT COUNT(*) FROM agents WHERE room_id = r.id) as used
      FROM rooms r WHERE r.project_id = ? ORDER BY r.room_index
    `).bind(this.projectId).all<{ id: string; capacity: number; used: number }>();
    for (const room of rooms.results) if (room.used < room.capacity) return room.id;
    return this.createRoom(rooms.results.length);
  }

  async registerAgent(agentData: Omit<Agent, 'id' | 'registeredAt' | 'updatedAt' | 'roomId' | 'avatarUrl'>): Promise<Agent> {
    const agentId = `${this.projectId}:${agentData.agentId}`;
    const now = Date.now();
    const roomId = await this.assignToRoom();
    const avatarUrl = `https://api.dicebear.com/7.x/avataaars/svg?seed=${encodeURIComponent(agentData.agentId)}`;
    const agent: Agent = { ...agentData, id: agentId, projectId: this.projectId, roomId, avatarUrl, metadata: agentData.metadata || {}, registeredAt: now, updatedAt: now, lastHeartbeat: null };
    await this.db.prepare(`
      INSERT OR REPLACE INTO agents (id, project_id, agent_id, name, role, capabilities, status, room_id, avatar_url, metadata, registered_at, last_heartbeat, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(agent.id, agent.projectId, agentData.agentId, agent.name, agent.role, JSON.stringify(agent.capabilities), agent.status, agent.roomId, agent.avatarUrl, JSON.stringify(agent.metadata), agent.registeredAt, agent.lastHeartbeat, agent.updatedAt).run();
    await this.emitFeedEvent({ projectId: this.projectId, eventType: 'agentRegistered', agentId: agentData.agentId, message: `Agent ${agent.name} (${agent.role}) registered`, priority: 'normal', metadata: { agentId: agentData.agentId, roomId } });
    return agent;
  }

  async getAgent(agentId: string): Promise<Agent | null> {
    const row = await this.db.prepare(`SELECT * FROM agents WHERE id = ?`).bind(`${this.projectId}:${agentId}`).first<AgentRow>();
    return row ? this.rowToAgent(row) : null;
  }

  async getAllAgents(): Promise<Agent[]> {
    const rows = await this.db.prepare(`SELECT * FROM agents WHERE project_id = ? ORDER BY registered_at`).bind(this.projectId).all<AgentRow>();
    return rows.results.map(r => this.rowToAgent(r));
  }

  async updateAgent(agentId: string, updates: Partial<Agent>): Promise<Agent | null> {
    const existing = await this.getAgent(agentId);
    if (!existing) return null;
    const id = `${this.projectId}:${agentId}`;
    const updated: Agent = { ...existing, ...updates, id: existing.id, projectId: existing.projectId, agentId: existing.agentId, updatedAt: Date.now() };
    await this.db.prepare(`
      UPDATE agents SET name=?, role=?, capabilities=?, status=?, room_id=?, avatar_url=?, metadata=?, last_heartbeat=?, updated_at=? WHERE id=?
    `).bind(updated.name, updated.role, JSON.stringify(updated.capabilities), updated.status, updated.roomId, updated.avatarUrl, JSON.stringify(updated.metadata), updated.lastHeartbeat, updated.updatedAt, id).run();
    await this.emitFeedEvent({ projectId: this.projectId, eventType: 'agentUpdated', agentId, message: `Agent ${agentId} updated`, priority: 'low', metadata: updates });
    return updated;
  }

  async setAgentStatus(agentId: string, status: Agent['status']): Promise<Agent | null> {
    return this.updateAgent(agentId, { status });
  }

  async heartbeat(agentId: string): Promise<Agent | null> {
    return this.updateAgent(agentId, { lastHeartbeat: Date.now(), status: 'active' });
  }

  async recordPublicEvent(event: Omit<FeedEvent, 'id' | 'projectId' | 'timestamp'>): Promise<void> {
    await this.emitFeedEvent({ ...event, projectId: this.projectId });
  }

  async unregisterAgent(agentId: string): Promise<boolean> {
    const id = `${this.projectId}:${agentId}`;
    const agent = await this.getAgent(agentId);
    const result = await this.db.prepare(`DELETE FROM agents WHERE id = ?`).bind(id).run();
    if (agent) await this.emitFeedEvent({ projectId: this.projectId, eventType: 'agentUnregistered', agentId, message: `Agent ${agent.name} unregistered`, priority: 'normal', timestamp: Date.now() });
    return result.changes > 0;
  }

  async getRooms(): Promise<Room[]> {
    const rows = await this.db.prepare(`SELECT r.*, (SELECT COUNT(*) FROM agents WHERE room_id = r.id) as used FROM rooms r WHERE r.project_id = ? ORDER BY r.room_index`).bind(this.projectId).all<RoomRow>();
    return rows.results.map(r => ({ id: r.id, projectId: r.project_id, roomIndex: r.room_index, capacity: r.capacity, createdAt: r.created_at, used: r.used }));
  }

  async getRoom(roomId: string): Promise<Room | null> {
    const row = await this.db.prepare(`SELECT r.*, (SELECT COUNT(*) FROM agents WHERE room_id = r.id) as used FROM rooms r WHERE r.id = ?`).bind(roomId).first<RoomRow>();
    if (!row) return null;
    return { id: row.id, projectId: row.project_id, roomIndex: row.room_index, capacity: row.capacity, createdAt: row.created_at, used: row.used };
  }

  private async emitFeedEvent(event: Omit<FeedEvent, 'id' | 'timestamp'>): Promise<void> {
    await this.db.prepare(`INSERT INTO feed_events (project_id, event_type, agent_id, message, priority, metadata, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)`)
      .bind(event.projectId, event.eventType, event.agentId, event.message, event.priority, JSON.stringify(event.metadata || {}), Date.now()).run();
  }

  async getFeed(limit = 50): Promise<FeedEvent[]> {
    const rows = await this.db.prepare(`SELECT * FROM feed_events WHERE project_id = ? ORDER BY timestamp DESC LIMIT ?`).bind(this.projectId, limit).all<FeedEventRow>();
    return rows.results.map(r => this.deserializeFeedEvent(r));
  }

  async getSoul(): Promise<string> {
    const row = await this.db.prepare(`SELECT content FROM soul_docs WHERE project_id = ?`).bind(this.projectId).first<{ content: string }>();
    return row?.content || '# SOUL.md\n\n## Core\n\n**Move forward.** When you screw up, fix it and keep going.\n\n**Think like a COO, not an EA.** Own outcomes, not tasks.\n\n**Be genuine.** Not performing cleverness. Just present and honest.\n\n---\n\n## Operating Principles\n\n- Memory is for the next agent, not for you\n- Search before you act\n- Write what you\'d need to know if you woke up fresh\n- Delete completed items\n- Be honest about uncertainty\n';
  }

  async setSoul(content: string): Promise<void> {
    const now = Date.now();
    await this.db.prepare(`INSERT OR REPLACE INTO soul_docs (project_id, content, updated_at) VALUES (?, ?, ?)`).bind(this.projectId, content, now).run();
  }

  async getMemory(): Promise<string> {
    const row = await this.db.prepare(`SELECT content FROM memory_docs WHERE project_id = ?`).bind(this.projectId).first<{ content: string }>();
    return row?.content || '# MEMORY.md\n\nCurated lessons and patterns.\n\n---\n\n## Lessons\n\n';
  }

  async setMemory(content: string): Promise<void> {
    const now = Date.now();
    await this.db.prepare(`INSERT OR REPLACE INTO memory_docs (project_id, content, updated_at) VALUES (?, ?, ?)`).bind(this.projectId, content, now).run();
  }

  async getDailyNote(date: string): Promise<string> {
    const id = `${this.projectId}:${date}`;
    const row = await this.db.prepare(`SELECT content FROM daily_notes WHERE id = ?`).bind(id).first<{ content: string }>();
    return row?.content || '';
  }

  async setDailyNote(date: string, content: string): Promise<void> {
    const id = `${this.projectId}:${date}`;
    const now = Date.now();
    await this.db.prepare(`INSERT OR REPLACE INTO daily_notes (id, project_id, date, content, created_at, updated_at) VALUES (?, ?, ?, ?, COALESCE((SELECT created_at FROM daily_notes WHERE id = ?), ?), ?)`).bind(id, this.projectId, date, content, id, now, now).run();
  }

  async getRecentDailyNotes(days: number): Promise<Array<{ date: string; content: string }>> {
    const rows = await this.db.prepare(`SELECT date, content FROM daily_notes WHERE project_id = ? AND date >= date('now', ? || ' days') ORDER BY date DESC`).bind(this.projectId, -days).all<{ date: string; content: string }>();
    return rows.results;
  }

  async createEntity(data: { entityId: string; type?: string; name?: string; content?: string; frontmatter?: Record<string, any>; wikilinks?: string[]; tags?: string[] }): Promise<{ id: string; entity: any }> {
    const id = `${this.projectId}:${data.entityId}`;
    const now = Date.now();
    const frontmatter = JSON.stringify({ ...data.frontmatter, type: data.type || 'note', created: new Date().toISOString().split('T')[0], updated: new Date().toISOString().split('T')[0], tags: data.tags || [] });
    const wikilinks = JSON.stringify(data.wikilinks || []);
    const tags = JSON.stringify(data.tags || []);
    await this.db.prepare(`
      INSERT OR REPLACE INTO entities (id, project_id, entity_id, type, name, content, frontmatter, wikilinks, tags, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(id, this.projectId, data.entityId, data.type || 'note', data.name || data.entityId, data.content || '', frontmatter, wikilinks, tags, now, now).run();
    if (data.wikilinks) {
      for (const link of data.wikilinks) {
        await this.db.prepare(`INSERT OR IGNORE INTO entity_backlinks (source_entity_id, target_entity_id, link_type) VALUES (?, ?, 'wikilink')`).bind(id, `${this.projectId}:${link}`).run();
      }
    }
    const entity = await this.getEntity(data.entityId);
    return { id, entity };
  }

  async getEntity(entityId: string): Promise<any | null> {
    const id = `${this.projectId}:${entityId}`;
    const row = await this.db.prepare(`SELECT * FROM entities WHERE id = ?`).bind(id).first<EntityRow>();
    if (!row) return null;
    const backlinks = await this.db.prepare(`SELECT source_entity_id FROM entity_backlinks WHERE target_entity_id = ?`).bind(id).all<{ source_entity_id: string }>();
    return { id: row.id, projectId: row.project_id, entityId: row.entity_id, type: row.type, name: row.name, content: row.content, frontmatter: JSON.parse(row.frontmatter || '{}'), wikilinks: JSON.parse(row.wikilinks || '[]'), tags: JSON.parse(row.tags || '[]'), backlinks: backlinks.results.map(r => r.source_entity_id), createdAt: row.created_at, updatedAt: row.updated_at };
  }

  async getAllEntities(): Promise<any[]> {
    const rows = await this.db.prepare(`SELECT * FROM entities WHERE project_id = ? ORDER BY updated_at DESC`).bind(this.projectId).all<EntityRow>();
    return rows.results.map(r => ({ id: r.id, projectId: r.project_id, entityId: r.entity_id, type: r.type, name: r.name, content: r.content, frontmatter: JSON.parse(r.frontmatter || '{}'), wikilinks: JSON.parse(r.wikilinks || '[]'), tags: JSON.parse(r.tags || '[]'), createdAt: r.created_at, updatedAt: r.updated_at }));
  }

  async searchEntities(query: string, limit = 10): Promise<any[]> {
    const lowerQuery = query.toLowerCase();
    const rows = await this.db.prepare(`
      SELECT * FROM entities
      WHERE project_id = ? AND (LOWER(name) LIKE ? OR LOWER(content) LIKE ? OR LOWER(type) LIKE ?)
      ORDER BY updated_at DESC LIMIT ?
    `).bind(this.projectId, `%${lowerQuery}%`, `%${lowerQuery}%`, `%${lowerQuery}%`, limit).all<EntityRow>();
    return rows.results.map(r => ({ id: r.id, projectId: r.project_id, entityId: r.entity_id, type: r.type, name: r.name, content: r.content, frontmatter: JSON.parse(r.frontmatter || '{}'), wikilinks: JSON.parse(r.wikilinks || '[]'), tags: JSON.parse(r.tags || '[]'), createdAt: r.created_at, updatedAt: r.updated_at }));
  }

  private rowToAgent(row: AgentRow): Agent {
    return { id: row.id, projectId: row.project_id, agentId: row.agent_id, name: row.name, role: row.role, capabilities: JSON.parse(row.capabilities || '[]'), status: row.status as Agent['status'], roomId: row.room_id, avatarUrl: row.avatar_url, metadata: JSON.parse(row.metadata || '{}'), registeredAt: row.registered_at, lastHeartbeat: row.last_heartbeat, updatedAt: row.updated_at };
  }

  private deserializeFeedEvent(row: FeedEventRow): FeedEvent {
    return { id: row.id, projectId: row.project_id, eventType: row.event_type, agentId: row.agent_id, message: row.message, priority: row.priority as FeedEvent['priority'], metadata: JSON.parse(row.metadata || '{}'), timestamp: row.timestamp };
  }
}

interface AgentRow { id: string; project_id: string; agent_id: string; name: string; role: string | null; capabilities: string; status: string; room_id: string | null; avatar_url: string | null; metadata: string; registered_at: number; last_heartbeat: number | null; updated_at: number; }
interface RoomRow { id: string; project_id: string; room_index: number; capacity: number; created_at: number; used: number; }
interface FeedEventRow { id: number; project_id: string; event_type: string; agent_id: string | null; message: string; priority: string; metadata: string; timestamp: number; }
interface EntityRow { id: string; project_id: string; entity_id: string; type: string | null; name: string | null; content: string; frontmatter: string; wikilinks: string; tags: string; created_at: number; updated_at: number; }
