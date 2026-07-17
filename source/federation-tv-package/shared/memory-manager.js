/**
 * Memory Manager — Shared Module
 * 
 * Four-Layer Memory Architecture for Autonomous Agents
 * 1. Knowledge Graph (Obsidian-compatible wikilinks)
 * 2. Semantic Search (Hybrid BM25 + Vector)
 * 3. Daily Notes / Long-term Memory (Episodic)
 * 4. Forgetting / Learning (Curation)
 */

import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync, readdirSync, statSync } from 'fs';
import { join, dirname, extname, basename } from 'path';
import { fileURLToPath } from 'url';
import { createHash } from 'crypto';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Default vault path - can be overridden
const DEFAULT_VAULT_PATH = '/home/ubuntu/qwen-cloud-2026/memory';
const DAILY_PATH = join(DEFAULT_VAULT_PATH, 'daily');
const ENTITIES_PATH = join(DEFAULT_VAULT_PATH, 'entities');
const TEMPLATES_PATH = join(DEFAULT_VAULT_PATH, 'templates');
const SOUL_PATH = join(DEFAULT_VAULT_PATH, 'SOUL.md');
const MEMORY_PATH = join(DEFAULT_VAULT_PATH, 'MEMORY.md');

// Ensure directories exist
[DEFAULT_VAULT_PATH, DAILY_PATH, ENTITIES_PATH, TEMPLATES_PATH].forEach(dir => {
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
});

// ============================================================================
// OBSIDIAN DATABASE - Markdown Knowledge Graph with Wikilinks
// ============================================================================

export class ObsidianDatabase {
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
        const id = entity.id || createHash('sha256').update(entity.name || '').digest('hex').slice(0, 12);
        const filepath = join(ENTITIES_PATH, `${id}.md`);

        const frontmatter = {
            type: entity.type || 'note',
            name: entity.name || id,
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

export class SemanticSearch {
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
        const hash = createHash('sha256').update(text).digest();
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

        this.documents.set(docId, {
            chunks: chunks.map(c => c.id),
            metadata,
            indexedAt: new Date().toISOString()
        });

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

export class MemoryManager {
    constructor(vaultPath = DEFAULT_VAULT_PATH) {
        this.vaultPath = vaultPath;
        this.dailyPath = join(vaultPath, 'daily');
        this.entitiesPath = join(vaultPath, 'entities');
        this.templatesPath = join(vaultPath, 'templates');
        this.soulPath = join(vaultPath, 'SOUL.md');
        this.memoryPath = join(vaultPath, 'MEMORY.md');

        [vaultPath, this.dailyPath, this.entitiesPath, this.templatesPath].forEach(dir => {
            if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
        });

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
            const path = join(this.templatesPath, name);
            if (!existsSync(path)) writeFileSync(path, content);
        }
    }

    initSoulAndMemory() {
        if (!existsSync(this.soulPath)) {
            writeFileSync(this.soulPath, `# SOUL.md\n\n## Core\n\n**Move forward.** When you screw up, fix it and keep going.\n\n**Think like a COO, not an EA.** Own outcomes, not tasks.\n\n**Be genuine.** Not performing cleverness. Just present and honest.\n\n---\n\n## Operating Principles\n\n- Memory is for the next agent, not for you\n- Search before you act\n- Write what you'd need to know if you woke up fresh\n- Delete completed items\n- Be honest about uncertainty\n`);
        }

        if (!existsSync(this.memoryPath)) {
            writeFileSync(this.memoryPath, `# MEMORY.md\n\nCurated lessons and patterns.\n\n---\n\n## Lessons\n\n`);
        }
    }

    // Morning routine - loads identity + memory + recent context
    morningRoutine() {
        return {
            identity: this.readSoul(),
            memory: this.readMemory(),
            recentNotes: this.getRecentDailyNotes(1),
            entities: this.obsidian.getAllEntities().slice(0, 20),
            stats: this.getStats()
        };
    }

    readSoul() { return existsSync(this.soulPath) ? readFileSync(this.soulPath, 'utf8') : ''; }
    readMemory() { return existsSync(this.memoryPath) ? readFileSync(this.memoryPath, 'utf8') : ''; }

    // Mandatory search (Recall Discipline)
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

    // Daily notes (Episodic layer)
    getTodaysPath() {
        const today = new Date().toISOString().split('T')[0];
        return join(this.dailyPath, `${today}.md`);
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
            const path = join(this.dailyPath, `${dateStr}.md`);
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

    // Long-term memory (Semantic layer)
    addLesson(title, content) {
        const timestamp = new Date().toISOString().split('T')[0];
        const formatted = `### ${title} (${timestamp})\n\n${content}\n\n---\n`;
        appendFileSync(this.memoryPath, formatted);
        return { path: this.memoryPath, timestamp, title };
    }

    searchMemory(query) {
        const content = this.readMemory();
        const sections = content.split('###').filter(s => s.toLowerCase().includes(query.toLowerCase()));
        return sections.map(s => `### ${s}`).slice(0, 5);
    }

    // Entity management (Knowledge Graph layer)
    createEntity(entity) { return this.obsidian.createEntity(entity); }
    getEntity(id) { return this.obsidian.getEntity(id); }
    searchEntities(query) {
        return [...this.obsidian.searchByWikilink(query), ...this.obsidian.searchByTag(query)].slice(0, 10);
    }

    // Index content for semantic search
    async indexForSearch(docId, text, metadata = {}) {
        return await this.semantic.indexDocument(docId, text, metadata);
    }

    // Reindex all entities
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

// Export singleton instance
export const memoryManager = new MemoryManager();

// Export for different environments
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { ObsidianDatabase, SemanticSearch, MemoryManager, memoryManager };
}
if (typeof window !== 'undefined') {
    window.ObsidianDatabase = ObsidianDatabase;
    window.SemanticSearch = SemanticSearch;
    window.MemoryManager = MemoryManager;
    window.memoryManager = memoryManager;
}