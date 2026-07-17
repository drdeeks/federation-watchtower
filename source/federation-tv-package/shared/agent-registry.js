/**
 * Agent Registration & Avatar System — Production Grade
 * 
 * Features:
 * - Automatic avatar generation with multiple fallback strategies
 * - Room assignment (max 35/room, overflow to production rooms)
 * - Plugin system for agent integration
 * - Robust error handling with graceful degradation
 * - Federation gateway integration
 * - Real-time status synchronization
 */

class AgentRegistry {
    constructor(config = {}) {
        this.config = {
            maxAgentsPerRoom: 35,
            federationUrl: config.federationUrl || 'http://localhost:41207',
            projectId: config.projectId || 'unknown',
            avatarStrategy: config.avatarStrategy || 'auto', // 'auto' | 'generated' | 'emoji' | 'initials' | 'identicon'
            fallbackAvatars: true,
            healthCheckInterval: 30000,
            ...config
        };

        this.agents = new Map();
        this.rooms = [];
        this.plugins = new Map();
        this.eventListeners = new Map();
        this.healthCheckTimer = null;
        this.isInitialized = false;

        // Avatar generation strategies (priority order)
        this.avatarStrategies = [
            { name: 'generated', fn: this.generateSvgAvatar.bind(this) },
            { name: 'identicon', fn: this.generateIdenticon.bind(this) },
            { name: 'emoji', fn: this.getEmojiAvatar.bind(this) },
            { name: 'initials', fn: this.getInitialsAvatar.bind(this) },
            { name: 'fallback', fn: this.getFallbackAvatar.bind(this) }
        ];
    }

    /**
     * Initialize the registry
     */
    async initialize() {
        if (this.isInitialized) return true;

        try {
            // Load existing agents from federation
            await this.syncFromFederation();
            
            // Build initial rooms
            this.rebuildRooms();
            
            // Start health checks
            this.startHealthChecks();
            
            this.isInitialized = true;
            this.emit('initialized', { agentCount: this.agents.size, roomCount: this.rooms.length });
            
            return true;
        } catch (error) {
            console.error('[AgentRegistry] Initialization failed:', error);
            // Graceful degradation - start with empty state
            this.rooms = [this.createEmptyRoom(1)];
            this.isInitialized = true;
            return false;
        }
    }

    /**
     * Register a new agent with full avatar generation and room assignment
     */
    async registerAgent(agentData) {
        const agentId = agentData.agentId || this.generateAgentId();
        
        // Validate required fields
        const validation = this.validateAgentData(agentData);
        if (!validation.valid) {
            throw new Error(`Agent validation failed: ${validation.errors.join(', ')}`);
        }

        // Check for duplicate
        if (this.agents.has(agentId)) {
            return this.updateAgent(agentId, agentData);
        }

        // Generate avatar with fallback chain
        const avatar = await this.generateAvatarWithFallbacks(agentData);

        // Create agent record
        const agent = {
            agentId,
            projectId: this.config.projectId,
            ...agentData,
            avatar,
            avatarStrategy: avatar.strategy,
            status: 'registering',
            registeredAt: Date.now(),
            lastSeen: Date.now(),
            health: 'unknown',
            metadata: agentData.metadata || {},
            capabilities: agentData.capabilities || [],
            roomId: null
        };

        // Store agent
        this.agents.set(agentId, agent);

        // Assign to room
        const roomId = this.assignToRoom(agentId);
        agent.roomId = roomId;
        agent.status = 'active';

        // Register with federation
        await this.registerWithFederation(agent);

        // Emit event
        this.emit('agentRegistered', { agent, roomId });

        return agent;
    }

    /**
     * Generate avatar with robust fallback chain
     */
    async generateAvatarWithFallbacks(agentData) {
        const strategies = this.config.avatarStrategy === 'auto' 
            ? this.avatarStrategies 
            : this.avatarStrategies.filter(s => s.name === this.config.avatarStrategy);

        let lastError = null;

        for (const strategy of strategies) {
            try {
                const avatar = await strategy.fn(agentData);
                if (avatar && this.validateAvatar(avatar)) {
                    return { ...avatar, strategy: strategy.name };
                }
            } catch (error) {
                lastError = error;
                console.warn(`[AgentRegistry] Avatar strategy '${strategy.name}' failed:`, error.message);
                continue;
            }
        }

        // Ultimate fallback - should never fail
        return this.getFallbackAvatar(agentData);
    }

    /**
     * Strategy 1: Generated SVG Avatar (primary)
     */
    async generateSvgAvatar(agentData) {
        const { agentId, name, role, projectId } = agentData;
        const colors = this.getProjectColors(projectId);
        const seed = this.hashString(agentId);
        
        // Deterministic generation from agent ID
        const bgHue = (seed * 137) % 360;
        const accentHue = (bgHue + 180 + (seed * 23) % 60) % 360;
        const shapeType = seed % 5;
        const patternSeed = seed * 7;

        const svg = this.renderAgentSvg({
            agentId,
            name: name || agentId,
            role: role || 'agent',
            bgHue,
            accentHue,
            shapeType,
            patternSeed,
            colors,
            size: 128
        });

        return {
            type: 'svg',
            data: svg,
            dataUrl: `data:image/svg+xml;base64,${btoa(svg)}`,
            width: 128,
            height: 128
        };
    }

    /**
     * Render deterministic SVG avatar
     */
    renderAgentSvg({ agentId, name, role, bgHue, accentHue, shapeType, patternSeed, colors, size }) {
        const center = size / 2;
        const radius = size * 0.35;
        
        // Background gradient
        const bgGradId = `bg-${agentId}`;
        const accentGradId = `accent-${agentId}`;
        
        let shapePath = '';
        switch (shapeType) {
            case 0: // Circle
                shapePath = `<circle cx="${center}" cy="${center}" r="${radius}" />`;
                break;
            case 1: // Rounded square
                const sqSize = radius * 1.6;
                shapePath = `<rect x="${center - sqSize/2}" y="${center - sqSize/2}" width="${sqSize}" height="${sqSize}" rx="${radius * 0.3}" />`;
                break;
            case 2: // Hexagon
                const hexPoints = [];
                for (let i = 0; i < 6; i++) {
                    const angle = (i * Math.PI / 3) - Math.PI / 6;
                    hexPoints.push(`${center + radius * Math.cos(angle)},${center + radius * Math.sin(angle)}`);
                }
                shapePath = `<polygon points="${hexPoints.join(' ')}" />`;
                break;
            case 3: // Rounded triangle
                const triPoints = [];
                for (let i = 0; i < 3; i++) {
                    const angle = (i * 2 * Math.PI / 3) - Math.PI / 2;
                    triPoints.push(`${center + radius * 1.2 * Math.cos(angle)},${center + radius * 1.2 * Math.sin(angle)}`);
                }
                shapePath = `<polygon points="${triPoints.join(' ')}" />`;
                break;
            default: // Diamond
                shapePath = `<polygon points="${center},${center-radius*1.3} ${center+radius*1.3},${center} ${center},${center+radius*1.3} ${center-radius*1.3},${center}" />`;
        }

        // Pattern based on seed
        const patternId = `pattern-${agentId}`;
        const pattern = this.generatePattern(patternSeed, accentHue);

        return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>
    <linearGradient id="${bgGradId}" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:hsl(${bgHue}, 60%, 15%)"/>
      <stop offset="100%" style="stop-color:hsl(${bgHue}, 50%, 8%)"/>
    </linearGradient>
    <linearGradient id="${accentGradId}" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:hsl(${accentHue}, 70%, 55%)"/>
      <stop offset="100%" style="stop-color:hsl(${accentHue}, 60%, 35%)"/>
    </linearGradient>
    <pattern id="${patternId}" x="0" y="0" width="16" height="16" patternUnits="userSpaceOnUse">
      ${pattern}
    </pattern>
    <filter id="glow-${agentId}">
      <feGaussianBlur stdDeviation="3" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  <rect width="${size}" height="${size}" fill="url(#${bgGradId})"/>
  <rect width="${size}" height="${size}" fill="url(#${patternId})" opacity="0.15"/>
  ${shapePath.replace('/>', ` fill="url(#${accentGradId})" filter="url(#glow-${agentId})" />`)}
  <text x="${center}" y="${center + 4}" 
        font-family="system-ui, sans-serif" 
        font-size="${size * 0.25}" 
        font-weight="bold" 
        fill="white" 
        text-anchor="middle" 
        opacity="0.95">
    ${this.getInitials(name)}
  </text>
  <text x="${center}" y="${center + size * 0.18}" 
        font-family="system-ui, sans-serif" 
        font-size="${size * 0.08}" 
        fill="hsl(${accentHue}, 50%, 70%)" 
        text-anchor="middle" 
        opacity="0.7">
    ${role.slice(0, 12)}
  </text>
</svg>`;
    }

    /**
     * Generate geometric pattern for avatar background
     */
    generatePattern(seed, hue) {
        const patterns = [];
        const rand = this.seededRandom(seed);
        
        for (let i = 0; i < 8; i++) {
            const x = (rand() * 16).toFixed(1);
            const y = (rand() * 16).toFixed(1);
            const size = (2 + rand() * 4).toFixed(1);
            const opacity = (0.1 + rand() * 0.2).toFixed(2);
            const shape = Math.floor(rand() * 3);
            
            if (shape === 0) {
                patterns.push(`<circle cx="${x}" cy="${y}" r="${size}" fill="hsl(${hue}, 70%, 60%)" opacity="${opacity}"/>`);
            } else if (shape === 1) {
                patterns.push(`<rect x="${x}" y="${y}" width="${size}" height="${size}" fill="hsl(${hue}, 70%, 60%)" opacity="${opacity}" rx="1"/>`);
            } else {
                patterns.push(`<polygon points="${x},${y} ${+x+size},${y} ${x},${+y+size}" fill="hsl(${hue}, 70%, 60%)" opacity="${opacity}"/>`);
            }
        }
        return patterns.join('');
    }

    /**
     * Strategy 2: Identicon (block-based)
     */
    generateIdenticon(agentData) {
        const { agentId } = agentData;
        const hash = this.hashString(agentId);
        const size = 5;
        const blocks = [];
        const colors = this.getProjectColors(agentData.projectId);
        
        for (let y = 0; y < size; y++) {
            for (let x = 0; x < Math.ceil(size / 2); x++) {
                const bit = (hash >> (y * Math.ceil(size/2) + x)) & 1;
                if (bit) {
                    const hue = 200 + (hash * 13) % 160;
                    blocks.push(`<rect x="${x*20}" y="${y*20}" width="20" height="20" fill="hsl(${hue}, 60%, 45%)"/>`);
                    if (x !== size - 1 - x) {
                        blocks.push(`<rect x="${(size-1-x)*20}" y="${y*20}" width="20" height="20" fill="hsl(${hue}, 60%, 45%)"/>`);
                    }
                }
            }
        }

        const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <rect width="100" height="100" fill="#0f172a"/>
  ${blocks.join('')}
</svg>`;

        return {
            type: 'svg',
            data: svg,
            dataUrl: `data:image/svg+xml;base64,${btoa(svg)}`,
            width: 100,
            height: 100
        };
    }

    /**
     * Strategy 3: Emoji avatar
     */
    getEmojiAvatar(agentData) {
        const roleEmojis = {
            'director': '🎬', 'orchestrator': '🧠', 'scribe': '✏️', 'architect': '📐',
            'kernel': '⚙️', 'sovereign': '👑', 'connector': '🔌', 'graph': '📊',
            'inference': '⚡', 'operator': '🔧', 'cynic': '🕵️', 'frontend': '🎨',
            'auditor': '📋', 'monitor': '👁️', 'backup': '💾', 'archiver': '🗄️',
            'cleaner': '🧹', 'analyst': '📈', 'bible': '📖', 'composer': '🎵',
            'continuity': '🔄', 'cost': '💰', 'shotlist': '📋', 'lighting': '💡',
            'script': '✍️', 'editor': '🎞️', 'casting': '🎭', 'indexer': '🗂️',
            'recall': '🔍', 'forgetter': '🧹', 'learner': '📚', 'shadow': '👻',
            'privacy': '🔐', 'legislator': '⚖️', 'judge': '👨‍⚖️', 'marshal': '🛡️',
            'debater': '🎤', 'voter': '🗳️', 'mesh': '🌐', 'deception': '🎭',
            'policy': '📜', 'runtime': '🚀', 'watcher': '👁️'
        };

        const role = (agentData.role || '').toLowerCase();
        const emoji = roleEmojis[role] || '🤖';

        return {
            type: 'emoji',
            data: emoji,
            dataUrl: null,
            width: 64,
            height: 64,
            render: (size = 64) => `<div style="font-size:${size}px;line-height:1">${emoji}</div>`
        };
    }

    /**
     * Strategy 4: Initials avatar
     */
    getInitialsAvatar(agentData) {
        const initials = this.getInitials(agentData.name || agentData.agentId);
        const colors = this.getProjectColors(agentData.projectId);
        const seed = this.hashString(agentData.agentId);
        const bgHue = (seed * 137) % 360;

        const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:hsl(${bgHue}, 60%, 20%)"/>
      <stop offset="100%" style="stop-color:hsl(${bgHue}, 50%, 10%)"/>
    </linearGradient>
  </defs>
  <rect width="128" height="128" fill="url(#bg)"/>
  <text x="64" y="84" font-family="system-ui, sans-serif" font-size="48" font-weight="700" fill="white" text-anchor="middle">${initials}</text>
</svg>`;

        return {
            type: 'initials',
            data: svg,
            dataUrl: `data:image/svg+xml;base64,${btoa(svg)}`,
            width: 128,
            height: 128
        };
    }

    /**
     * Strategy 5: Ultimate fallback
     */
    getFallbackAvatar(agentData) {
        const initials = this.getInitials(agentData.name || agentData.agentId || '??');
        const colors = this.getProjectColors(agentData.projectId);

        return {
            type: 'fallback',
            data: initials,
            dataUrl: null,
            width: 64,
            height: 64,
            color: colors.accent,
            render: (size = 64) => `
                <div style="
                    width:${size}px;height:${size}px;
                    border-radius:50%;
                    background:${colors.primary};
                    display:flex;align-items:center;justify-content:center;
                    color:white;font-weight:bold;font-size:${size*0.5}px;
                    font-family:system-ui,sans-serif;
                    border:2px solid ${colors.accent};
                ">${initials}</div>`
        };
    }

    /**
     * Assign agent to room (max 35 per room, overflow to production rooms)
     */
    assignToRoom(agentId) {
        // Find room with space
        for (const room of this.rooms) {
            if (room.agents.length < this.config.maxAgentsPerRoom) {
                room.agents.push(agentId);
                return room.id;
            }
        }

        // Create new production room
        const newRoom = this.createEmptyRoom(this.rooms.length + 1);
        newRoom.agents.push(agentId);
        this.rooms.push(newRoom);
        
        this.emit('roomCreated', { room: newRoom });
        return newRoom.id;
    }

    /**
     * Rebuild all rooms from current agents
     */
    rebuildRooms() {
        this.rooms = [];
        const agentIds = Array.from(this.agents.keys());
        
        for (let i = 0; i < agentIds.length; i += this.config.maxAgentsPerRoom) {
            const roomAgents = agentIds.slice(i, i + this.config.maxAgentsPerRoom);
            const room = this.createEmptyRoom(Math.floor(i / this.config.maxAgentsPerRoom) + 1);
            room.agents = roomAgents;
            room.isProduction = i >= this.config.maxAgentsPerRoom;
            this.rooms.push(room);
            
            // Update agent room assignments
            roomAgents.forEach(id => {
                const agent = this.agents.get(id);
                if (agent) agent.roomId = room.id;
            });
        }
    }

    createEmptyRoom(roomNumber) {
        return {
            id: `${this.config.projectId.toUpperCase()}-ROOM-${roomNumber}`,
            number: roomNumber,
            agents: [],
            createdAt: Date.now(),
            isProduction: roomNumber > 1,
            capacity: this.config.maxAgentsPerRoom
        };
    }

    /**
     * Register agent with federation gateway
     */
    async registerWithFederation(agent) {
        try {
            const response = await fetch(`${this.config.federationUrl}/api/join`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    agentId: agent.agentId,
                    projectId: agent.projectId,
                    role: agent.role,
                    avatar: agent.avatar.dataUrl || agent.avatar.data,
                    capabilities: agent.capabilities
                })
            });

            if (!response.ok) {
                throw new Error(`Federation registration failed: ${response.status}`);
            }

            agent.federationRegistered = true;
            agent.federationRegisteredAt = Date.now();
        } catch (error) {
            console.warn('[AgentRegistry] Federation registration failed, will retry:', error.message);
            agent.federationRegistered = false;
            agent.federationError = error.message;
            // Schedule retry
            setTimeout(() => this.registerWithFederation(agent), 5000);
        }
    }

    /**
     * Sync agents from federation gateway
     */
    async syncFromFederation() {
        try {
            const response = await fetch(`${this.config.federationUrl}/api/agents?projectId=${this.config.projectId}`);
            if (response.ok) {
                const data = await response.json();
                if (data.agents) {
                    for (const agentData of data.agents) {
                        if (!this.agents.has(agentData.agentId)) {
                            await this.registerAgent(agentData);
                        }
                    }
                }
            }
        } catch (error) {
            console.warn('[AgentRegistry] Federation sync failed:', error.message);
        }
    }

    /**
     * Start periodic health checks
     */
    startHealthChecks() {
        this.healthCheckTimer = setInterval(async () => {
            await this.performHealthChecks();
        }, this.config.healthCheckInterval);
    }

    async performHealthChecks() {
        for (const [agentId, agent] of this.agents) {
            try {
                // Check if agent is responsive
                const isHealthy = await this.checkAgentHealth(agent);
                agent.health = isHealthy ? 'healthy' : 'unhealthy';
                agent.lastHealthCheck = Date.now();
                
                if (!isHealthy && agent.status === 'active') {
                    agent.status = 'degraded';
                    this.emit('agentDegraded', { agentId, agent });
                }
            } catch (error) {
                agent.health = 'error';
                agent.lastHealthCheck = Date.now();
            }
        }
        this.emit('healthCheckComplete', { timestamp: Date.now() });
    }

    async checkAgentHealth(agent) {
        // Implement actual health check based on agent type
        // For now, return true if recently seen
        return (Date.now() - agent.lastSeen) < 120000; // 2 minutes
    }

    /**
     * Plugin system for agent integration
     */
    registerPlugin(name, plugin) {
        if (typeof plugin.install !== 'function') {
            throw new Error('Plugin must have install() method');
        }
        this.plugins.set(name, plugin);
        plugin.install(this);
        this.emit('pluginRegistered', { name, plugin });
    }

    getPlugin(name) {
        return this.plugins.get(name);
    }

    /**
     * Event system
     */
    on(event, listener) {
        if (!this.eventListeners.has(event)) {
            this.eventListeners.set(event, []);
        }
        this.eventListeners.get(event).push(listener);
    }

    off(event, listener) {
        const listeners = this.eventListeners.get(event);
        if (listeners) {
            const idx = listeners.indexOf(listener);
            if (idx > -1) listeners.splice(idx, 1);
        }
    }

    emit(event, data) {
        const listeners = this.eventListeners.get(event) || [];
        listeners.forEach(fn => {
            try { fn(data); } catch (e) { console.error(`[AgentRegistry] Event ${event} error:`, e); }
        });
    }

    /**
     * Utility methods
     */
    validateAgentData(data) {
        const errors = [];
        if (!data.agentId && !data.name) errors.push('agentId or name required');
        if (!data.role) errors.push('role required');
        if (!data.projectId && !this.config.projectId) errors.push('projectId required');
        return { valid: errors.length === 0, errors };
    }

    validateAvatar(avatar) {
        return avatar && (avatar.dataUrl || avatar.data || avatar.render);
    }

    getInitials(name) {
        return name
            .split(/[\s\-_]+/)
            .map(w => w[0]?.toUpperCase() || '')
            .slice(0, 2)
            .join('');
    }

    generateAgentId() {
        return `${this.config.projectId.toUpperCase()}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`.toUpperCase();
    }

    hashString(str) {
        let hash = 0;
        for (let i = 0; i < str.length; i++) {
            hash = ((hash << 5) - hash) + str.charCodeAt(i);
            hash |= 0;
        }
        return Math.abs(hash);
    }

    seededRandom(seed) {
        return () => {
            seed = (seed * 1664525 + 1013904223) % 4294967296;
            return seed / 4294967296;
        };
    }

    getProjectColors(projectId) {
        const colorMap = {
            autopilot: { primary: '#0f172a', accent: '#22c55e', bg: '#14141f' },
            aires: { primary: '#0f172a', accent: '#a855f7', bg: '#14141f' },
            mnemosyne: { primary: '#0f172a', accent: '#3b82f6', bg: '#14141f' },
            agora: { primary: '#0f172a', accent: '#f59e0b', bg: '#14141f' },
            edgewalker: { primary: '#0f172a', accent: '#ef4444', bg: '#14141f' }
        };
        return colorMap[projectId] || colorMap.autopilot;
    }

    /**
     * Get agent with full details
     */
    getAgent(agentId) {
        return this.agents.get(agentId);
    }

    getAllAgents() {
        return Array.from(this.agents.values());
    }

    getAgentsInRoom(roomId) {
        const room = this.rooms.find(r => r.id === roomId);
        if (!room) return [];
        return room.agents.map(id => this.agents.get(id)).filter(Boolean);
    }

    getRooms() {
        return this.rooms.map(room => ({
            ...room,
            agentCount: room.agents.length,
            occupancy: `${room.agents.length}/${room.capacity}`,
            agents: room.agents.map(id => this.agents.get(id)).filter(Boolean)
        }));
    }

    /**
     * Update agent
     */
    async updateAgent(agentId, updates) {
        const agent = this.agents.get(agentId);
        if (!agent) throw new Error(`Agent ${agentId} not found`);

        Object.assign(agent, updates, { lastSeen: Date.now() });
        this.emit('agentUpdated', { agentId, agent });
        return agent;
    }

    /**
     * Remove agent
     */
    async removeAgent(agentId) {
        const agent = this.agents.get(agentId);
        if (!agent) return false;

        // Remove from room
        const room = this.rooms.find(r => r.id === agent.roomId);
        if (room) {
            room.agents = room.agents.filter(id => id !== agentId);
        }

        // Deregister from federation
        try {
            await fetch(`${this.config.federationUrl}/api/leave`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ agentId, projectId: this.config.projectId })
            });
        } catch (e) { /* ignore */ }

        this.agents.delete(agentId);
        this.emit('agentRemoved', { agentId });
        return true;
    }

    /**
     * Shutdown
     */
    shutdown() {
        if (this.healthCheckTimer) {
            clearInterval(this.healthCheckTimer);
            this.healthCheckTimer = null;
        }
        this.plugins.forEach(plugin => {
            if (typeof plugin.uninstall === 'function') plugin.uninstall();
        });
        this.plugins.clear();
        this.eventListeners.clear();
        this.isInitialized = false;
    }
}
// Export for ES modules
export { AgentRegistry };

// Export for CommonJS
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { AgentRegistry };
}
if (typeof window !== 'undefined') {
    window.AgentRegistry = AgentRegistry;
}