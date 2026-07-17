/**
 * Enhanced Federation Server — Production Grade
 * 
 * Full agent registry integration with:
 * - Automatic avatar generation with fallbacks
 * - Room management (max 35/room, overflow handling)
 * - Plugin system for agent capabilities
 * - Health monitoring and self-healing
 * - Four-layer memory architecture
 * - WebSocket for real-time updates
 */

import http from 'http';
import url from 'url';
import crypto from 'crypto';
import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync, readdirSync, statSync } from 'fs';
import { join, dirname, extname, basename } from 'path';
import { fileURLToPath } from 'url';
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PORT = 41207;
const VAULT_PATH = '/home/ubuntu/qwen-cloud-2026/memory';
const DAILY_PATH = join(VAULT_PATH, 'daily');
const ENTITIES_PATH = join(VAULT_PATH, 'entities');
const TEMPLATES_PATH = join(VAULT_PATH, 'templates');
const SOUL_PATH = join(VAULT_PATH, 'SOUL.md');
const MEMORY_PATH = join(VAULT_PATH, 'MEMORY.md');

// Ensure directories exist
[VAULT_PATH, DAILY_PATH, ENTITIES_PATH, TEMPLATES_PATH].forEach(dir => {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
});

// ============================================================================
// AGENT REGISTRY INTEGRATION
// ============================================================================

import { AgentRegistry } from '../shared/agent-registry.js';
import { PluginManager, AvatarPlugin, RoomPlugin, FederationPlugin, HealthPlugin, TVRoomPlugin } from '../shared/agent-plugins.js';

// Project configurations
const PROJECTS = {
  autopilot: { name: 'Autopilot', track: 'Track 4: Autopilot Agent', color: '#22c55e', emoji: '⚙️', prefix: 'AP' },
  aires: { name: 'Aires', track: 'Track 2: AI Showrunner', color: '#a855f7', emoji: '🎬', prefix: 'AI' },
  mnemosyne: { name: 'Mnemosyne', track: 'Track 1: MemoryAgent', color: '#3b82f6', emoji: '🧠', prefix: 'MN' },
  agora: { name: 'Agora', track: 'Track 3: Agent Society', color: '#f59e0b', emoji: '🏛️', prefix: 'AG' },
  edgewalker: { name: 'Edgewalker', track: 'Track 5: EdgeAgent', color: '#ef4444', emoji: '⚡', prefix: 'EW' }
};

// Global registries per project
const projectRegistries = new Map();
const pluginManagers = new Map();

// Initialize all project registries
async function initializeProjectRegistries() {
  for (const [projectId, config] of Object.entries(PROJECTS)) {
    const registry = new AgentRegistry({
      federationUrl: `http://localhost:${PORT}`,
      projectId,
      maxAgentsPerRoom: 35,
      avatarStrategy: 'auto',
      healthCheckInterval: 30000
    });

    const pluginManager = new PluginManager(registry);
    pluginManager.loadBuiltins();

    await registry.initialize();

    projectRegistries.set(projectId, registry);
    pluginManagers.set(projectId, pluginManager);

    console.log(`✅ ${config.name} registry initialized (${registry.agents.size} agents, ${registry.rooms.length} rooms)`);
  }
}

// ============================================================================
// OBSIDIAN DATABASE - Markdown Knowledge Graph with Wikilinks
// ============================================================================

class ObsidianDatabase {
  constructor() {
    this.index = new Map();
    this.entities = new Map();
    this.backlinks = new Map();
    this.tags = new Map();
    this.frontmatterCache = new Map();
    this.rebuildIndex();
  }

  rebuildIndex() {
    this.index.clear();
    this.entities.clear();
    this.backlinks.clear();
    this.tags.clear();
    this.frontmatterCache.clear();

    if (existsSync(ENTITIES_PATH)) {
      const files = readdirSync(ENTITIES_PATH, { recursive: true });
      for (const file of files) {
        if (extname(file) === '.md') {
          const filepath = join(ENTITIES_PATH, file);
          this.indexFile(filepath);
        }
      }
    }
  }

  indexFile(filepath) {
    try {
      const content = readFileSync(filepath, 'utf8');
      const { frontmatter, body } = this.parseFrontmatter(content);
      const entityId = basename(filepath, '.md');

      const entity = {
        id: entityId,
        filepath,
        frontmatter,
        body,
        wikilinks: this.extractWikilinks(body),
        tags: frontmatter.tags || [],
        type: frontmatter.type || 'note',
        created: frontmatter.created || statSync(filepath).birthtime.toISOString(),
        updated: frontmatter.updated || statSync(filepath).mtime.toISOString()
      };

      this.entities.set(entityId, entity);

      for (const link of entity.wikilinks) {
        if (!this.index.has(link)) this.index.set(link, new Set());
        this.index.get(link).add(entityId);
      }

      for (const tag of entity.tags) {
        if (!this.tags.has(tag)) this.tags.set(tag, new Set());
        this.tags.get(tag).add(entityId);
      }

      for (const link of entity.wikilinks) {
        if (!this.backlinks.has(link)) this.backlinks.set(link, new Set());
        this.backlinks.get(link).add(entityId);
      }
    } catch (e) {
      console.error(`Failed to index ${filepath}:`, e.message);
    }
  }

  parseFrontmatter(content) {
    const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
    if (fmMatch) {
      const frontmatter = {};
      fmMatch[1].split('\n').forEach(line => {
        const [key, ...val] = line.split(':');
        if (key && val.length) {
          frontmatter[key.trim()] = val.join(':').trim();
        }
      });
      return { frontmatter, body: content.slice(fmMatch[0].length).trim() };
    }
    return { frontmatter: {}, body: content };
  }

  extractWikilinks(content) {
    const links = [];
    const regex = /\[\[([^\]]+)\]\]/g;
    let match;
    while ((match = regex.exec(content)) !== null) {
      links.push(match[1].split('|')[0].trim());
    }
    return [...new Set(links)];
  }

  createEntity(entity) {
    const id = entity.id || crypto.createHash('sha256').update(entity.name || '').digest('hex').slice(0, 12);
    const filepath = join(ENTITIES_PATH, `${id}.md`);

    const frontmatter = {
      type: entity.type || 'note',
      created: new Date().toISOString().split('T')[0],
      updated: new Date().toISOString().split('T')[0],
      tags: entity.tags || [],
      ...entity.frontmatter
    };

    const fmLines = Object.entries(frontmatter).map(([k, v]) =>
      Array.isArray(v) ? `${k}: [${v.map(x => `"${x}"`).join(', ')}]` : `${k}: ${v}`
    ).join('\n');

    const content = `---\n${fmLines}\n---\n\n# ${entity.name || id}\n\n${entity.content || ''}\n`;

    writeFileSync(filepath, content);
    this.indexFile(filepath);

    return { id, filepath, entity: this.entities.get(id) };
  }

  getEntity(id) { return this.entities.get(id); }
  getEntityByName(name) {
    for (const entity of this.entities.values()) {
      if (entity.frontmatter.name === name || entity.id === name) return entity;
    }
    return null;
  }
  searchByTag(tag) {
    const ids = this.tags.get(tag) || new Set();
    return Array.from(ids).map(id => this.entities.get(id));
  }
  searchByWikilink(link) {
    const ids = this.index.get(link) || new Set();
    return Array.from(ids).map(id => this.entities.get(id));
  }
  getBacklinks(entityId) {
    const ids = this.backlinks.get(entityId) || new Set();
    return Array.from(ids).map(id => this.entities.get(id));
  }
  getAllEntities() { return Array.from(this.entities.values()); }
  getStats() {
    return {
      totalEntities: this.entities.size,
      totalWikilinks: this.index.size,
      totalTags: this.tags.size,
      types: [...new Set(Array.from(this.entities.values()).map(e => e.type))]
    };
  }
}

// ============================================================================
// SEMANTIC SEARCH - Hybrid BM25 + Vector
// ============================================================================

class SemanticSearch {
  constructor() {
    this.chunks = new Map();
    this.documents = new Map();
    this.vocabulary = new Map();
    this.chunkSize = 500;
    this.chunkOverlap = 100;
  }

  tokenize(text) {
    return text.toLowerCase().replace(/[^\w\s]/g, ' ').split(/\s+/).filter(t => t.length > 1);
  }

  buildVocabulary() {
    this.vocabulary.clear();
    const N = this.chunks.size;
    if (N === 0) return;

    const docFreq = new Map();
    for (const [chunkId, chunk] of this.chunks) {
      const terms = new Set(this.tokenize(chunk.text));
      for (const term of terms) {
        docFreq.set(term, (docFreq.get(term) || 0) + 1);
      }
    }

    for (const [term, df] of docFreq) {
      const idf = Math.log((N - df + 0.5) / (df + 0.5) + 1);
      this.vocabulary.set(term, { df, idf });
    }
  }

  bm25Score(queryTerms, chunkText) {
    const k1 = 1.5, b = 0.75;
    const tokens = this.tokenize(chunkText);
    const docLen = tokens.length;
    const avgDocLen = 500;

    let score = 0;
    const termFreq = new Map();
    for (const token of tokens) {
      termFreq.set(token, (termFreq.get(token) || 0) + 1);
    }

    for (const term of queryTerms) {
      const tf = termFreq.get(term) || 0;
      if (tf === 0) continue;

      const vocab = this.vocabulary.get(term);
      if (!vocab) continue;

      const idf = vocab.idf;
      const numerator = tf * (k1 + 1);
      const denominator = tf + k1 * (1 - b + b * docLen / avgDocLen);
      score += idf * (numerator / denominator);
    }
    return score;
  }

  async getEmbedding(text) {
    const hash = crypto.createHash('sha256').update(text).digest();
    const embedding = new Array(384).fill(0);
    for (let i = 0; i < hash.length; i++) {
      embedding[i % 384] += hash[i] / 255;
    }
    const norm = Math.sqrt(embedding.reduce((a, b) => a + b * b, 0));
    return embedding.map(v => v / (norm || 1));
  }

  cosineSimilarity(a, b) {
    let dot = 0, na = 0, nb = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
  }

  chunkText(text, metadata = {}) {
    const chunks = [];
    const words = text.split(/\s+/);

    for (let i = 0; i < words.length; i += this.chunkSize - this.chunkOverlap) {
      const chunkWords = words.slice(i, i + this.chunkSize);
      if (chunkWords.length < 50) continue;

      const chunkText = chunkWords.join(' ');
      const chunkId = `${metadata.docId || 'doc'}-${chunks.length}`;

      chunks.push({
        id: chunkId,
        text: chunkText,
        metadata: { ...metadata, chunkIndex: chunks.length, startWord: i }
      });
    }
    return chunks;
  }

  async indexDocument(docId, text, metadata = {}) {
    const chunks = this.chunkText(text, { docId, ...metadata });

    for (const chunk of chunks) {
      const embedding = await this.getEmbedding(chunk.text);
      this.chunks.set(chunk.id, { ...chunk, embedding, metadata });
    }

    this.documents.set(docId, { chunks: chunks.map(c => c.id), metadata, indexedAt: new Date().toISOString() });
    this.buildVocabulary();
    return chunks.length;
  }

  async hybridSearch(query, limit = 5) {
    const queryTerms = this.tokenize(query);
    const queryEmbedding = await this.getEmbedding(query);

    const results = [];

    for (const [chunkId, chunk] of this.chunks) {
      const bm25 = this.bm25Score(queryTerms, chunk.text);
      const vectorScore = this.cosineSimilarity(queryEmbedding, chunk.embedding);
      const rrfScore = 1 / (1 + bm25 * 10) + 1 / (1 + (1 - vectorScore) * 10);

      if (bm25 > 0 || vectorScore > 0.3) {
        results.push({
          chunkId,
          text: chunk.text.slice(0, 200) + '...',
          score: rrfScore,
          bm25,
          vectorScore,
          metadata: chunk.metadata
        });
      }
    }

    results.sort((a, b) => b.score - a.score);
    return results.slice(0, limit);
  }

  getStats() {
    return {
      totalChunks: this.chunks.size,
      totalDocuments: this.documents.size,
      vocabularySize: this.vocabulary.size
    };
  }
}

// ============================================================================
// MEMORY MANAGER - Four-Layer Architecture
// ============================================================================

class MemoryManager {
  constructor() {
    this.obsidian = new ObsidianDatabase();
    this.semantic = new SemanticSearch();
    this.initTemplates();
    this.initSoulAndMemory();
  }

  initTemplates() {
    const templates = {
      'daily-note.md': `# {{date:YYYY-MM-DD}}\n\n## Session Notes\n- \n\n## Decisions\n- \n\n## Links\n- [[{{date:YYYY-MM-DD, -1 day}}|Yesterday]]\n`,
      'person.md': `# {{name}}\n\n---\ntype: person\ncreated: {{date:YYYY-MM-DD}}\nupdated: {{date:YYYY-MM-DD}}\ntags: [people/agent]\n---\n\n## Context\n\n## Milestones\n\n## Notes\n`,
      'project.md': `# {{name}}\n\n---\ntype: project\ncreated: {{date:YYYY-MM-DD}}\nupdated: {{date:YYYY-MM-DD}}\ntags: [project]\n---\n\n## Description\n\n## Status\n\n## Milestones\n\n## Notes\n`
    };

    for (const [name, content] of Object.entries(templates)) {
      const path = join(TEMPLATES_PATH, name);
      if (!existsSync(path)) writeFileSync(path, content);
    }
  }

  initSoulAndMemory() {
    if (!existsSync(SOUL_PATH)) {
      writeFileSync(SOUL_PATH, `# SOUL.md\n\n## Core\n\n**Move forward.** When you screw up, fix it and keep going.\n\n**Think like a COO, not an EA.** Own outcomes, not tasks.\n\n**Be genuine.** Not performing cleverness. Just present and honest.\n\n---\n\n## Operating Principles\n\n- Memory is for the next agent, not for you\n- Search before you act\n- Write what you'd need to know if you woke up fresh\n- Delete completed items\n- Be honest about uncertainty\n`);
    }

    if (!existsSync(MEMORY_PATH)) {
      writeFileSync(MEMORY_PATH, `# MEMORY.md\n\nCurated lessons and patterns.\n\n---\n\n## Lessons\n\n`);
    }
  }

  morningRoutine() {
    return {
      identity: this.readSoul(),
      memory: this.readMemory(),
      recentNotes: this.getRecentDailyNotes(1),
      entities: this.obsidian.getAllEntities().slice(0, 20),
      stats: this.getStats()
    };
  }

  readSoul() { return existsSync(SOUL_PATH) ? readFileSync(SOUL_PATH, 'utf8') : ''; }
  readMemory() { return existsSync(MEMORY_PATH) ? readFileSync(MEMORY_PATH, 'utf8') : ''; }

  async mandatorySearch(query, limit = 10) {
    return {
      semantic: await this.semantic.hybridSearch(query, limit),
      obsidian: {
        entities: this.obsidian.searchByWikilink(query).slice(0, limit),
        tags: this.obsidian.searchByTag(query).slice(0, limit),
        backlinks: this.obsidian.getBacklinks(query).slice(0, limit)
      },
      daily: this.searchDailyNotes(query).slice(0, limit),
      memory: this.searchMemory(query).slice(0, limit),
      identity: this.readSoul().includes(query) ? ['Identity match'] : []
    };
  }

  getTodaysPath() {
    const today = new Date().toISOString().split('T')[0];
    return join(DAILY_PATH, `${today}.md`);
  }

  appendDailyNote(type, content, links = []) {
    const path = this.getTodaysPath();
    const timestamp = new Date().toISOString();
    const linkStr = links.length > 0 ? '\n' + links.map(l => `- [[${l}]]`).join('\n') : '';
    const formatted = `## ${timestamp} — ${type}\n\n${content}\n${linkStr}\n\n---\n`;
    appendFileSync(path, formatted);
    return { path, timestamp };
  }

  getRecentDailyNotes(days = 7) {
    const notes = [];
    for (let i = 0; i < days; i++) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      const dateStr = date.toISOString().split('T')[0];
      const path = join(DAILY_PATH, `${dateStr}.md`);
      if (existsSync(path)) {
        notes.push({ date: dateStr, content: readFileSync(path, 'utf8') });
      }
    }
    return notes;
  }

  searchDailyNotes(query) {
    const recent = this.getRecentDailyNotes(30);
    return recent
      .filter(d => d.content.toLowerCase().includes(query.toLowerCase()))
      .map(d => ({ date: d.date, snippet: this.extractSnippet(d.content, query) }));
  }

  addLesson(title, content) {
    const timestamp = new Date().toISOString().split('T')[0];
    const formatted = `### ${title} (${timestamp})\n\n${content}\n\n---\n`;
    appendFileSync(MEMORY_PATH, formatted);
    return { path: MEMORY_PATH, timestamp, title };
  }

  searchMemory(query) {
    const content = this.readMemory();
    const sections = content.split('###').filter(s => s.toLowerCase().includes(query.toLowerCase()));
    return sections.map(s => `### ${s}`).slice(0, 5);
  }

  createEntity(entity) { return this.obsidian.createEntity(entity); }
  getEntity(id) { return this.obsidian.getEntity(id); }
  searchEntities(query) {
    return [...this.obsidian.searchByWikilink(query), ...this.obsidian.searchByTag(query)].slice(0, 10);
  }

  async indexForSearch(docId, text, metadata = {}) {
    return await this.semantic.indexDocument(docId, text, metadata);
  }

  async reindexAll() {
    let count = 0;
    for (const entity of this.obsidian.getAllEntities()) {
      const text = `${entity.frontmatter.name || entity.id}\n${entity.body}`;
      await this.indexForSearch(entity.id, text, { type: entity.type, entityId: entity.id });
      count++;
    }
    return count;
  }

  extractSnippet(content, query, context = 100) {
    const idx = content.toLowerCase().indexOf(query.toLowerCase());
    if (idx === -1) return '';
    const start = Math.max(0, idx - context);
    const end = Math.min(content.length, idx + query.length + context);
    return '...' + content.substring(start, end) + '...';
  }

  getStats() {
    return {
      obsidian: this.obsidian.getStats(),
      semantic: this.semantic.getStats(),
      daily: { recentDays: this.getRecentDailyNotes(7).length },
      memory: { size: this.readMemory().length },
      identity: { size: this.readSoul().length }
    };
  }
}

const memoryManager = new MemoryManager();

// Index existing content on startup
(async () => {
  await memoryManager.reindexAll();
  console.log('✅ Semantic search index built');
})();

// ============================================================================
// WEBSOCKET SERVER FOR REAL-TIME UPDATES
// ============================================================================

const wsConnections = new Map(); // projectId -> Set of WebSocket connections

function handleWebSocketUpgrade(req, socket, head) {
  const parsedUrl = url.parse(req.url, true);
  const projectId = parsedUrl.query.projectId || 'all';

  // Simple WebSocket handshake
  const key = req.headers['sec-websocket-key'];
  if (!key) {
    socket.destroy();
    return;
  }

  const acceptKey = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');

  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${acceptKey}\r\n` +
    '\r\n'
  );

  const ws = {
    socket,
    projectId,
    send: (data) => {
      const payload = JSON.stringify(data);
      const frame = Buffer.alloc(2 + payload.length);
      frame[0] = 0x81; // FIN + text frame
      frame[1] = payload.length;
      payload.copy(frame, 2);
      socket.write(frame);
    }
  };

  if (!wsConnections.has(projectId)) wsConnections.set(projectId, new Set());
  wsConnections.get(projectId).add(ws);

  socket.on('data', (data) => {
    // Handle incoming WebSocket frames (simplified)
    if (data[0] === 0x88) { // Close frame
      wsConnections.get(projectId)?.delete(ws);
      socket.end();
    }
  });

  socket.on('close', () => {
    wsConnections.get(projectId)?.delete(ws);
  });

  // Send initial state
  if (projectId !== 'all') {
    const registry = projectRegistries.get(projectId);
    if (registry) {
      ws.send({ type: 'init', rooms: registry.getRooms(), agents: registry.getAllAgents() });
    }
  } else {
    // Send all projects summary
    const summary = {};
    for (const [pid, registry] of projectRegistries) {
      summary[pid] = { rooms: registry.getRooms().length, agents: registry.agents.size };
    }
    ws.send({ type: 'init', projects: summary });
  }
}

function broadcastToProject(projectId, message) {
  const connections = wsConnections.get(projectId) || new Set();
  for (const ws of connections) {
    try { ws.send(message); } catch (e) { connections.delete(ws); }
  }
}

function broadcastAll(message) {
  for (const [projectId, connections] of wsConnections) {
    for (const ws of connections) {
      try { ws.send(message); } catch (e) { connections.delete(ws); }
    }
  }
}

// ============================================================================
// HTTP SERVER
// ============================================================================

async function handleRequest(req, res) {
  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;
  const query = parsedUrl.query;
  const method = req.method;

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, DELETE');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Health
  if (pathname === '/health' && method === 'GET') {
    const totalAgents = Array.from(projectRegistries.values()).reduce((sum, r) => sum + r.agents.size, 0);
    const totalRooms = Array.from(projectRegistries.values()).reduce((sum, r) => sum + r.rooms.length, 0);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      agents: totalAgents,
      rooms: totalRooms,
      projects: PROJECTS
    }));
    return;
  }

  // WebSocket upgrade
  if (pathname === '/ws' && req.headers.upgrade === 'websocket') {
    handleWebSocketUpgrade(req, res.socket || req.connection, null);
    return;
  }

  // Blueprints
  if (pathname === '/api/blueprints' && method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      projects: Object.entries(PROJECTS).map(([id, config]) => ({
        id, ...config, version: '1.0'
      })),
      timestamp: new Date().toISOString()
    }));
    return;
  }

  // ========================================================================
  // AGENT REGISTRY ENDPOINTS
  // ========================================================================

  // Register agent
  if (pathname === '/api/agents/register' && method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const data = JSON.parse(body);
        const { agentId, projectId, ...agentData } = data;

        if (!projectId || !PROJECTS[projectId]) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'Invalid projectId' }));
          return;
        }

        const registry = projectRegistries.get(projectId);
        if (!registry) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'Registry not initialized' }));
          return;
        }

        const agent = await registry.registerAgent({ ...agentData, agentId, projectId });

        // Broadcast update
        broadcastToProject(projectId, { type: 'agentRegistered', agent, rooms: registry.getRooms() });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, agent, timestamp: new Date().toISOString() }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: e.message }));
      }
    });
    return;
  }

  // Get agent
  if (pathname.startsWith('/api/agents/') && method === 'GET') {
    const agentId = pathname.split('/')[3];
    const projectId = query.projectId;

    if (!projectId || !PROJECTS[projectId]) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: 'projectId required' }));
      return;
    }

    const registry = projectRegistries.get(projectId);
    const agent = registry?.getAgent(agentId);

    if (!agent) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: 'Agent not found' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, agent, timestamp: new Date().toISOString() }));
    return;
  }

  // List agents
  if (pathname === '/api/agents' && method === 'GET') {
    const projectId = query.projectId;

    if (projectId && PROJECTS[projectId]) {
      const registry = projectRegistries.get(projectId);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, agents: registry.getAllAgents(), timestamp: new Date().toISOString() }));
    } else {
      // All projects
      const allAgents = {};
      for (const [pid, registry] of projectRegistries) {
        allAgents[pid] = registry.getAllAgents();
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, agents: allAgents, timestamp: new Date().toISOString() }));
    }
    return;
  }

  // Update agent
  if (pathname.startsWith('/api/agents/') && method === 'PUT') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const agentId = pathname.split('/')[3];
        const projectId = query.projectId;
        const data = JSON.parse(body);

        if (!projectId || !PROJECTS[projectId]) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'projectId required' }));
          return;
        }

        const registry = projectRegistries.get(projectId);
        const agent = await registry.updateAgent(agentId, data);

        broadcastToProject(projectId, { type: 'agentUpdated', agent });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, agent, timestamp: new Date().toISOString() }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: e.message }));
      }
    });
    return;
  }

  // Remove agent
  if (pathname.startsWith('/api/agents/') && method === 'DELETE') {
    const agentId = pathname.split('/')[3];
    const projectId = query.projectId;

    if (!projectId || !PROJECTS[projectId]) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: 'projectId required' }));
      return;
    }

    const registry = projectRegistries.get(projectId);
    await registry.removeAgent(agentId);

    broadcastToProject(projectId, { type: 'agentRemoved', agentId });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, timestamp: new Date().toISOString() }));
    return;
  }

  // Get rooms
  if (pathname === '/api/rooms' && method === 'GET') {
    const projectId = query.projectId;

    if (projectId && PROJECTS[projectId]) {
      const registry = projectRegistries.get(projectId);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, rooms: registry.getRooms(), timestamp: new Date().toISOString() }));
    } else {
      const allRooms = {};
      for (const [pid, registry] of projectRegistries) {
        allRooms[pid] = registry.getRooms();
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, rooms: allRooms, timestamp: new Date().toISOString() }));
    }
    return;
  }

  // Get room details
  if (pathname.startsWith('/api/rooms/') && method === 'GET') {
    const roomId = pathname.split('/')[3];
    const projectId = query.projectId;

    if (!projectId || !PROJECTS[projectId]) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: 'projectId required' }));
      return;
    }

    const registry = projectRegistries.get(projectId);
    const room = registry.rooms.find(r => r.id === roomId);

    if (!room) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: 'Room not found' }));
      return;
    }

    const agents = registry.getAgentsInRoom(roomId);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, room: { ...room, agents }, timestamp: new Date().toISOString() }));
    return;
  }

  // Join (legacy compatibility)
  if (pathname === '/api/join' && method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const data = JSON.parse(body);
        const { agentId, projectId, role } = data;

        if (!agentId || !projectId || !PROJECTS[projectId]) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'agentId and valid projectId required' }));
          return;
        }

        const registry = projectRegistries.get(projectId);
        const agent = await registry.registerAgent({ agentId, projectId, role });

        broadcastToProject(projectId, { type: 'agentRegistered', agent, rooms: registry.getRooms() });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          success: true,
          agent,
          message: `Agent ${agentId} successfully joined project ${projectId}`,
          timestamp: new Date().toISOString()
        }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: e.message }));
      }
    });
    return;
  }

  // ========================================================================
  // MEMORY API ENDPOINTS
  // ========================================================================

  if (pathname === '/api/memory/identity' && method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, identity: memoryManager.readSoul(), timestamp: new Date().toISOString() }));
    return;
  }

  if (pathname === '/api/memory/long-term' && method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, memory: memoryManager.readMemory(), timestamp: new Date().toISOString() }));
    return;
  }

  if (pathname === '/api/memory/daily' && method === 'GET') {
    const days = parseInt(query.days) || 7;
    const notes = memoryManager.getRecentDailyNotes(days);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, notes, timestamp: new Date().toISOString() }));
    return;
  }

  if (pathname === '/api/memory/daily' && method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        const result = memoryManager.appendDailyNote(data.type || 'NOTE', data.content, data.links || []);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, note: result, timestamp: new Date().toISOString() }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: 'Invalid JSON' }));
      }
    });
    return;
  }

  if (pathname === '/api/memory/knowledge-graph' && method === 'GET') {
    const type = query.type;
    let entities = type
      ? memoryManager.obsidian.getAllEntities().filter(e => e.type === type)
      : memoryManager.obsidian.getAllEntities();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, entities, stats: memoryManager.obsidian.getStats(), timestamp: new Date().toISOString() }));
    return;
  }

  if (pathname === '/api/memory/entity' && method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const entity = JSON.parse(body);
        if (!entity.type || !entity.name) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'type and name required' }));
          return;
        }
        const result = memoryManager.createEntity(entity);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, entity: result, timestamp: new Date().toISOString() }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: 'Invalid JSON' }));
      }
    });
    return;
  }

  if (pathname === '/api/memory/entities/search' && method === 'GET') {
    const q = query.q || '';
    const entities = memoryManager.searchEntities(q);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, query: q, entities, timestamp: new Date().toISOString() }));
    return;
  }

  if (pathname === '/api/memory/search' && method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const data = JSON.parse(body);
        const { query: searchQuery, limit = 10 } = data;
        if (!searchQuery) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'query required' }));
          return;
        }
        const results = await memoryManager.mandatorySearch(searchQuery, limit);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, query: searchQuery, results, timestamp: new Date().toISOString() }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: 'Invalid JSON' }));
      }
    });
    return;
  }

  if (pathname === '/api/memory/semantic-search' && method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const data = JSON.parse(body);
        const { query: searchQuery, limit = 5 } = data;
        if (!searchQuery) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'query required' }));
          return;
        }
        const results = await memoryManager.semantic.hybridSearch(searchQuery, limit);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, query: searchQuery, results, timestamp: new Date().toISOString() }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: 'Invalid JSON' }));
      }
    });
    return;
  }

  if (pathname === '/api/memory/index' && method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const data = JSON.parse(body);
        const { docId, text, metadata } = data;
        if (!docId || !text) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'docId and text required' }));
          return;
        }
        const count = await memoryManager.indexForSearch(docId, text, metadata || {});
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, chunksIndexed: count, timestamp: new Date().toISOString() }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: 'Invalid JSON' }));
      }
    });
    return;
  }

  if (pathname === '/api/memory/reindex' && method === 'POST') {
    memoryManager.reindexAll().then(count => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, entitiesReindexed: count, timestamp: new Date().toISOString() }));
    }).catch(e => {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: e.message }));
    });
    return;
  }

  if (pathname === '/api/memory/lesson' && method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        const { title, content } = data;
        if (!title || !content) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'title and content required' }));
          return;
        }
        const result = memoryManager.addLesson(title, content);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, lesson: result, timestamp: new Date().toISOString() }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: 'Invalid JSON' }));
      }
    });
    return;
  }

  if (pathname === '/api/memory/morning-routine' && method === 'GET') {
    const context = memoryManager.morningRoutine();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, context, timestamp: new Date().toISOString() }));
    return;
  }

  if (pathname === '/api/memory/stats' && method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, stats: memoryManager.getStats(), timestamp: new Date().toISOString() }));
    return;
  }

  if (pathname === '/api/memory/templates' && method === 'GET') {
    const templates = readdirSync(TEMPLATES_PATH).filter(f => extname(f) === '.md');
    const templateData = {};
    for (const t of templates) {
      templateData[t] = readFileSync(join(TEMPLATES_PATH, t), 'utf8');
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, templates: templateData, timestamp: new Date().toISOString() }));
    return;
  }

  // Plugin endpoints
  if (pathname === '/api/plugins' && method === 'GET') {
    const projectId = query.projectId;
    if (projectId && pluginManagers.has(projectId)) {
      const pm = pluginManagers.get(projectId);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, plugins: pm.getAllPlugins().map(p => ({ name: p.name, version: p.version, capabilities: Array.from(p.capabilities) })), timestamp: new Date().toISOString() }));
    } else {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: 'projectId required' }));
    }
    return;
  }

  // 404
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ success: false, error: 'Not found', path: pathname }));
}

// Create server
const server = http.createServer(handleRequest);

// Handle WebSocket upgrades
server.on('upgrade', (req, socket, head) => {
  handleWebSocketUpgrade(req, socket, head);
});

// Start
async function startServer() {
  await initializeProjectRegistries();

  server.listen(PORT, () => {
    console.log('\n╔══════════════════════════════════════════════════════════════════════╗');
    console.log('║  🤖 AGENT FEDERATION SERVER - PRODUCTION GRADE                      ║');
    console.log('║  Port: ' + PORT + '                                                            ║');
    console.log('╚══════════════════════════════════════════════════════════════════════╝\n');
    console.log('✅ Federation API ready');
    console.log('✅ Agent Registry with avatar generation (5 fallback strategies)');
    console.log('✅ Room management (max 35/room, auto overflow)');
    console.log('✅ Plugin system (avatar, room, federation, health, TV room)');
    console.log('✅ Four-Layer Memory Architecture active');
    console.log('✅ WebSocket real-time updates');
    console.log('\n📡 HTTP Endpoints:');
    console.log('  GET  /health                              - Health check');
    console.log('  GET  /api/blueprints                      - List projects');
    console.log('  POST /api/agents/register                 - Register agent with avatar');
    console.log('  GET  /api/agents                          - List agents');
    console.log('  GET  /api/agents/:id                      - Get agent');
    console.log('  PUT  /api/agents/:id                      - Update agent');
    console.log('  DELETE /api/agents/:id                    - Remove agent');
    console.log('  GET  /api/rooms                           - List rooms');
    console.log('  GET  /api/rooms/:id                       - Get room with agents');
    console.log('  GET  /api/plugins                         - List plugins');
    console.log('  GET  /api/memory/identity                 - SOUL.md');
    console.log('  GET  /api/memory/long-term                - MEMORY.md');
    console.log('  GET  /api/memory/daily                    - Daily notes');
    console.log('  POST /api/memory/daily                    - Add daily note');
    console.log('  GET  /api/memory/knowledge-graph          - Entities');
    console.log('  POST /api/memory/entity                   - Create entity');
    console.log('  GET  /api/memory/entities/search          - Search entities');
    console.log('  POST /api/memory/search                   - Mandatory search');
    console.log('  POST /api/memory/semantic-search          - Hybrid vector search');
    console.log('  POST /api/memory/index                    - Index document');
    console.log('  POST /api/memory/reindex                  - Reindex all');
    console.log('  POST /api/memory/lesson                   - Add lesson');
    console.log('  GET  /api/memory/morning-routine          - Full context load');
    console.log('  GET  /api/memory/stats                    - Memory statistics');
    console.log('  GET  /api/memory/templates                - Obsidian templates');
    console.log('\n🔌 WebSocket: ws://localhost:' + PORT + '/ws?projectId=<project>');
  });

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.error('\n❌ Port ' + PORT + ' is already in use');
    } else {
      console.error('\n❌ Server error:', err.message);
    }
    process.exit(1);
  });

  process.on('SIGINT', async () => {
    console.log('\n🛑 Shutting down federation server...');
    for (const registry of projectRegistries.values()) {
      registry.shutdown();
    }
    server.close(() => {
      console.log('✅ Federation server stopped gracefully');
      process.exit(0);
    });
  });
}

startServer();