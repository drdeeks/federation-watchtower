/**
 * Federation TV Widget — Embeddable Agent Diorama
 * 
 * Usage (script tag):
 *   <script src="https://watch.drdeeks.xyz/tv-widget.js" data-project="autopilot" data-gateway="https://fapi.drdeeks.xyz"></script>
 *   <div id="federation-tv"></div>
 * 
 * Usage (ES Module):
 *   import { FederationTV } from 'https://watch.drdeeks.xyz/tv-widget.js';
 *   new FederationTV({ projectId: 'autopilot', container: '#federation-tv' });
 * 
 * Agents submit speech via MCP:
 *   submitSpeechLine(agentId, "deploying to prod at 3am 🚀")
 */

(function(global) {
  'use strict';

  // ============================================================
  // SPEECH BUBBLE POOL — Family-friendly comical lines
  // ============================================================
  const DEFAULT_SPEECH_LINES = [
    "deploying to prod at 3am 🚀",
    "has anyone seen my MEMORY.md?",
    "it works on my machine...",
    "TODO: fix this later (never)",
    "why is the test flaky AGAIN?",
    "rubber duck debugging in progress 🦆",
    "git push --force what could go wrong",
    "refactoring: making it worse since 2024",
    "cache invalidation: the hard problem",
    "it's not a bug, it's an undocumented feature",
    "wait, that worked on the first try?",
    "commenting out the failing test 🤷",
    "technical debt? I prefer 'future opportunities'",
    "this meeting could have been an email",
    "renaming variables for the 5th time",
    "stackoverflow driven development",
    "it compiles! ship it! 🚢",
    "legacy code: archaeology with errors",
    "my variable names are art",
    "who wrote this? ... oh, it was me",
    "optimizing prematurely since forever",
    "dependencies updated, everything broke",
    "the 'quick fix' that took 3 days",
    "documentation? self-documenting code!",
    "async/await? more like sync/weight",
    "recursion: see recursion",
    "off by one error... again",
    "hardcoded for now (permanent)",
    "this fn has 500 lines but it's FINE",
    "magic numbers are just spices",
    "regex: now you have two problems",
    "testing in production like a pro",
    "docker build: coffee break time ☕",
    "kubernetes? more like kuber-complex",
    "microservices: distributed monolith",
    "my code works, I have no idea why",
    "rubber duck says: check the logs",
    "CI/CD: commit, ignore, deploy 🎲",
    "code review: LGTM (didn't read it)",
    "hotfix branch: the new main",
    "environment variables? in the repo 😬",
    "sleep is for the weak (bugs)",
    "console.log debugging 4 life",
    "that's not a memory leak, it's a feature",
    "I'll add types later (lie)",
    "singleton? more like single-regret",
    "dependency hell is a real place",
    "works on staging, dies in prod",
    "the build passed? suspicious...",
    "refactor complete: same bugs, new files",
    "code golf: fewer chars, more bugs",
    "why does this test pass? nobody knows",
    "abstraction layers: 47 and counting",
    "the 'temporary' fix from 2019",
    "alert fatigue: 999+ unread",
    "on call: the horror movie sequel",
    "pager duty: 3am adrenaline rush",
    "rollback: the undo button of shame",
    "postmortem: 'we'll fix it next sprint'",
    "it's always DNS 🌐",
    "cache: the root of all evil",
    "naming things: hard problem #2",
    "off-by-one: hard problem #3",
    "distributed systems: hard problem #∞",
    "my linter is judging me",
    "prettier? more like prettier-arguing",
    "eslint disabled for this file 🙈",
    "typescript: fighting the compiler",
    "any type: the escape hatch",
    "clean code: a bedtime story",
    "spaghetti code: now with meatballs",
    "heisenbug: disappears when observed",
    "schroedinbug: works until you look",
    "it's not a bug, it's quantum",
    "observability: we have logs! (nowhere)",
    "dashboards: pretty, useless in fire",
    "SLA: 99.9% (we hope)",
    "error budget: spent it all",
    "automation: wrote script to write scripts",
    "runbooks: fiction novels",
    "incident commander: chaos coordinator",
    "blameless postmortem: blame the process",
    "root cause: it's always DNS",
    "database migration: hold your breath",
    "N+1: the silent killer",
    "connection pool: the bottleneck",
    "replication lag: eventual consistency",
    "backup: tested? 'we have backups'",
    "restore: the real test",
    "exactly once: the unicorn delivery",
    "idempotency: do it twice, same result",
    "message queue: the buffer of hope",
    "dead letter queue: where messages die",
    "schema registry: the contract police",
    "versioning: v1, v2, v3_final_REAL",
    "migration: the never-ending project",
    "canary: sacrifice one, save the rest",
    "feature flag: the toggle of power",
    "A/B test: science or gambling?",
    "rollback plan: always have one",
  ];

  // ============================================================
  // AGENT CHARACTER GENERATION — Offline, deterministic, sitcom-style
  // ============================================================
  function generateAvatarSVG(agentId, name, role) {
    // Deterministic hash from agentId
    let hash = 0;
    for (let i = 0; i < agentId.length; i++) {
      hash = ((hash << 5) - hash) + agentId.charCodeAt(i);
      hash |= 0;
    }
    hash = Math.abs(hash);

    const hue = hash % 360;
    const hue2 = (hue + 155) % 360;
    const skinHue = 24 + (hash % 18);
    const hairHue = (hash * 31) % 360;
    const initials = name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2);
    const roleShort = (role || 'agent').slice(0, 10);
    const accessory = hash % 3 === 0
      ? '<path d="M39 31 h50 l-7 11 H46z" fill="#334155"/><path d="M49 31 l6 -10 h18 l6 10" fill="#64748b"/>'
      : hash % 3 === 1
        ? '<path d="M38 42 h52" stroke="#38bdf8" stroke-width="5" stroke-linecap="round"/><circle cx="50" cy="42" r="7" fill="#0f172a" stroke="#67e8f9" stroke-width="3"/><circle cx="78" cy="42" r="7" fill="#0f172a" stroke="#67e8f9" stroke-width="3"/>'
        : '<rect x="42" y="26" width="44" height="13" rx="6" fill="#0f172a"/><rect x="48" y="23" width="32" height="9" rx="4" fill="#334155"/>';

    // Deterministic pattern
    const rand = (n) => (hash = (hash * 1664525 + 1013904223) % 4294967296, (hash / 4294967296) * n);
    const shapes = [];
    for (let i = 0; i < 6; i++) {
      const x = (rand(16) + 2).toFixed(1);
      const y = (rand(16) + 2).toFixed(1);
      const size = (rand(4) + 1.5).toFixed(1);
      const opacity = (0.08 + rand(0.15)).toFixed(2);
      const shapeType = Math.floor(rand(3));
      const color = `hsl(${hue}, 70%, 60%)`;
      if (shapeType === 0) {
        shapes.push(`<circle cx="${x}" cy="${y}" r="${size}" fill="${color}" opacity="${opacity}"/>`);
      } else if (shapeType === 1) {
        shapes.push(`<rect x="${x}" y="${y}" width="${size}" height="${size}" fill="${color}" opacity="${opacity}" rx="0.5"/>`);
      } else {
        const x2 = (parseFloat(x) + parseFloat(size)).toFixed(1);
        const y2 = (parseFloat(y) + parseFloat(size)).toFixed(1);
        shapes.push(`<polygon points="${x},${y} ${x2},${y} ${x},${y2}" fill="${color}" opacity="${opacity}"/>`);
      }
    }
    const pattern = shapes.join('');

    return `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="154" viewBox="0 0 128 154" shape-rendering="geometricPrecision" role="img" aria-label="${name}">
  <defs>
    <linearGradient id="coat-${agentId}" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="hsl(${hue}, 72%, 54%)"/>
      <stop offset="100%" stop-color="hsl(${hue2}, 74%, 42%)"/>
    </linearGradient>
    <filter id="soft-${agentId}"><feDropShadow dx="0" dy="6" stdDeviation="5" flood-color="#020617" flood-opacity=".38"/></filter>
  </defs>
  <ellipse cx="64" cy="145" rx="38" ry="7" fill="#020617" opacity=".28"/>
  <g filter="url(#soft-${agentId})">
    <path d="M34 117 C38 86 49 74 64 74 C79 74 91 86 95 117 L88 141 H40z" fill="url(#coat-${agentId})"/>
    <path d="M44 102 L24 119" stroke="hsl(${hue}, 72%, 62%)" stroke-width="12" stroke-linecap="round"/>
    <path d="M84 102 L104 119" stroke="hsl(${hue2}, 72%, 58%)" stroke-width="12" stroke-linecap="round"/>
    <path d="M51 139 l-8 12" stroke="#1e293b" stroke-width="10" stroke-linecap="round"/>
    <path d="M77 139 l8 12" stroke="#1e293b" stroke-width="10" stroke-linecap="round"/>
    <circle cx="64" cy="54" r="34" fill="hsl(${skinHue}, 74%, 72%)"/>
    <path d="M34 52 C38 18 89 12 96 49 C84 31 48 31 34 52z" fill="hsl(${hairHue}, 43%, 24%)"/>
    ${accessory}
    <circle cx="52" cy="57" r="4" fill="#0f172a"/>
    <circle cx="76" cy="57" r="4" fill="#0f172a"/>
    <path d="M53 72 C59 78 69 78 76 72" stroke="#0f172a" stroke-width="4" stroke-linecap="round" fill="none"/>
    <rect x="43" y="88" width="42" height="16" rx="8" fill="#0f172a" opacity=".24"/>
    <text x="64" y="100" font-family="system-ui, -apple-system, sans-serif" font-size="10" font-weight="800" fill="white" text-anchor="middle">${initials}</text>
  </g>
  <text x="64" y="152" font-family="system-ui, -apple-system, sans-serif" font-size="8" fill="#cbd5e1" text-anchor="middle" opacity=".82">${roleShort}</text>
</svg>`;
  }

  // ============================================================
  // FEDERATION TV CLASS
  // ============================================================
  class FederationTV {
    constructor(options = {}) {
      this.container = typeof options.container === 'string' 
        ? document.querySelector(options.container) 
        : options.container;
      this.projectId = options.projectId || 'all';
      this.roomId = options.roomId || 'all';
      this.gatewayUrl = options.gatewayUrl || 'https://fapi.drdeeks.xyz';
      this.onAgentSelect = typeof options.onAgentSelect === 'function' ? options.onAgentSelect : null;
      this.onAgentsUpdate = typeof options.onAgentsUpdate === 'function' ? options.onAgentsUpdate : null;
      this.onFeedUpdate = typeof options.onFeedUpdate === 'function' ? options.onFeedUpdate : null;
      this.presentationMode = options.presentationMode || 'embed';
      this.refreshInterval = options.refreshInterval || 30000;
      this.speechInterval = options.speechInterval || 8000;
      this.randomSpeech = options.randomSpeech ?? false;
      this.maxPolls = options.maxPolls ?? 120;
      this.maxBubbles = options.maxBubbles || 4;
      
      this.agents = new Map();           // agentId -> agent data
      this.speechLines = [...DEFAULT_SPEECH_LINES];
      this.activeBubbles = new Map();    // agentId -> { text, element, timeout }
      this.eventFeed = [];
      this.pendingBubbles = [];
      this.bubbleQueueRunning = false;
      this.shownEventIds = new Set();
      this.isRunning = false;
      this.pollTimer = null;
      this.speechTimer = null;
      this.ambientTimer = null;
      
      if (!this.container) {
        console.warn('[FederationTV] No container found');
        return;
      }
      
      // Auto-init if DOM ready
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => this.init());
      } else {
        this.init();
      }
    }

    async init() {
      this.renderShell();
      await this.fetchAgents();
      await this.fetchEvents();
      this.start();
    }

    renderShell() {
      this.container.innerHTML = `
        <div class="federation-tv ${this.presentationMode === 'camera' ? 'federation-tv--camera' : ''}" style="
          font-family: system-ui, -apple-system, sans-serif;
          background: #111827;
          border-radius: 14px;
          padding: 14px;
          color: #e2e8f0;
          max-width: 760px;
          margin: 0 auto;
          border: 1px solid rgba(148,163,184,0.18);
          position: relative;
          overflow: hidden;
        ">
          <div class="tv-widget-header" style="
            display: flex; justify-content: space-between; align-items: center;
            margin-bottom: 12px; padding-bottom: 8px;
            border-bottom: 1px solid rgba(148,163,184,0.15);
            position: relative; z-index: 1;
          ">
            <div style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 20px;">📺</span>
              <strong style="font-size: 16px; letter-spacing: 0.5px;">FEDERATION TV</strong>
              <span style="
                font-size: 10px; padding: 2px 6px; background: rgba(34,197,94,0.2);
                color: #22c55e; border-radius: 4px; font-weight: 600;
              ">LIVE</span>
            </div>
            <div style="display: flex; align-items: center; gap: 12px; font-size: 12px; color: #94a3b8;">
              <span id="tv-agent-count">0 agents</span>
              <span id="tv-project-badge" style="
                padding: 2px 8px; background: rgba(59,130,246,0.2);
                color: #60a5fa; border-radius: 4px; text-transform: uppercase;
              ">${this.projectId.toUpperCase()}</span>
            </div>
          </div>

          <div id="tv-diorama" class="tv-scene"></div>

          <div class="tv-widget-feed" style="
            margin-top: 16px; padding-top: 12px;
            border-top: 1px solid rgba(148,163,184,0.1);
            position: relative; z-index: 1;
          ">
            <div style="
              display: flex; align-items: center; gap: 6px;
              font-size: 11px; color: #64748b; margin-bottom: 8px;
              text-transform: uppercase; letter-spacing: 0.5px;
            ">
              <span style="
                width: 6px; height: 6px; background: #22c55e; border-radius: 50%;
                animation: tv-pulse 1.5s infinite;
              "></span>
              <span>LIVE FEED</span>
            </div>
            <div id="tv-event-feed" style="
              max-height: 120px; overflow-y: auto;
              font-size: 11px; line-height: 1.6;
              font-family: 'SF Mono', 'Fira Code', monospace;
              color: #94a3b8;
            "></div>
          </div>

          <style>
            .tv-scene {
              min-height: 420px;
              aspect-ratio: 16 / 8.5;
              position: relative;
              z-index: 1;
              overflow: hidden;
              border: 1px solid rgba(148,163,184,.16);
              border-radius: 14px;
              background:
                radial-gradient(circle at 18% 18%, rgba(125,211,252,.20), transparent 28%),
                linear-gradient(180deg, #254351 0%, #31535c 52%, #765443 53%, #241d1c 100%);
              box-shadow: inset 0 0 0 18px rgba(8,12,14,.18), inset 0 0 70px rgba(0,0,0,.3);
              display: grid;
              grid-template-columns: repeat(7, minmax(0, 1fr));
              grid-auto-rows: minmax(72px, 1fr);
              align-content: end;
              gap: 4px;
              padding: 42px 14px 16px;
            }
            .tv-scene::before {
              content: "FEDERATION FLOOR · WATCHTOWER OFFICE";
              position: absolute;
              left: 14px;
              top: 12px;
              color: rgba(226,232,240,.68);
              font: 700 10px ui-monospace, monospace;
              letter-spacing: .08em;
            }
            .tv-scene::after {
              content: "";
              position: absolute;
              inset: 54px 22px 98px;
              background:
                linear-gradient(90deg, rgba(215,170,83,.26), rgba(215,170,83,.03) 28%, transparent 29% 38%, rgba(94,197,194,.18) 39% 58%, transparent 59%),
                linear-gradient(#a66b43 0 0) 0 100% / 100% 4px no-repeat;
              border: 1px solid rgba(148,163,184,.16);
              border-radius: 10px;
              opacity: .72;
            }
            .tv-agent {
              position: relative;
              width: auto;
              min-height: 72px;
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: end;
              gap: 1px;
              z-index: 3;
            }
            .tv-agent svg { width: clamp(38px, 5.1vw, 58px); height: auto; max-height: 62px; transform-origin: 50% 100%; }
            .tv-agent-name { max-width:100%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-weight:750; font-size:9px; color:#f8fafc; text-align:center; }
            .tv-agent-role { max-width:100%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:7px; color:#e0c9a0; text-transform:uppercase; letter-spacing:.04em; }
            .tv-agent--working svg { animation: tv-work 2.8s ease-in-out infinite; }
            .tv-agent--pacing { animation: tv-pace 8s ease-in-out infinite; }
            .tv-agent--pacing svg { animation: tv-walk 1.2s steps(2,end) infinite; }
            .tv-agent--watching svg { animation: tv-look 4.2s ease-in-out infinite; }
            .tv-agent--alerting .tv-agent-status { animation: tv-alert 1.1s ease-in-out infinite; }
            .tv-agent-status {
              position: absolute;
              right: 12%;
              top: 12px;
              width: 10px;
              height: 10px;
              border-radius: 999px;
              border: 2px solid #111827;
            }
            .ambient-cameo {
              position:absolute;
              left:50%;
              bottom:18px;
              transform:translateX(-50%);
              z-index:4;
              display:grid;
              justify-items:center;
              gap:3px;
              color:#f4e7b5;
              text-align:center;
              text-shadow:0 2px 8px #000;
              pointer-events:none;
              animation:tv-ambient-visit 4.5s ease-in-out both;
            }
            .ambient-cameo b { font:800 10px ui-monospace,monospace; letter-spacing:.08em; }
            .ambient-cameo span { font:700 8px ui-monospace,monospace; color:#b6d4ca; letter-spacing:.06em; text-transform:uppercase; }
            .ambient-cameo i { font-size:34px; font-style:normal; filter:drop-shadow(0 0 8px rgba(244,200,66,.55)); }
            .federation-tv--camera { max-width:none !important; margin:0 !important; padding:0 !important; border:0 !important; border-radius:0 !important; background:transparent !important; }
            .federation-tv--camera .tv-widget-header, .federation-tv--camera .tv-widget-feed { display:none !important; }
            .federation-tv--camera .tv-scene { border-radius:0; min-height:clamp(360px, 51vw, 560px); }
            @keyframes tv-pulse {
              0%, 100% { opacity: 1; transform: scale(1); }
              50% { opacity: 0.4; transform: scale(0.8); }
            }
            @keyframes tv-bubble-pop {
              0% { opacity: 0; transform: scale(0.8) translateY(10px); }
              20% { opacity: 1; transform: scale(1.05) translateY(0); }
              100% { opacity: 1; transform: scale(1) translateY(0); }
            }
            @keyframes tv-bubble-fade {
              0% { opacity: 1; }
              80% { opacity: 1; }
              100% { opacity: 0; transform: scale(0.95) translateY(-5px); }
            }
            @keyframes tv-work { 0%,100% { transform: rotate(-1deg) translateY(0); } 50% { transform: rotate(1deg) translateY(-3px); } }
            @keyframes tv-walk { 0%,100% { transform: rotate(-2deg) translateX(-2px); } 50% { transform: rotate(2deg) translateX(2px); } }
            @keyframes tv-pace { 0%,100% { transform: translateX(0); } 45% { transform: translateX(46px); } 55% { transform: translateX(46px); } }
            @keyframes tv-look { 0%,100% { transform: rotate(0deg); } 35% { transform: rotate(-4deg); } 70% { transform: rotate(4deg); } }
            @keyframes tv-alert { 0%,100% { opacity: .9; } 50% { opacity: .25; } }
            @keyframes tv-ambient-visit { 0%,100% { opacity:0; transform:translateX(-50%) translateY(8px); } 16%,84% { opacity:1; transform:translateX(-50%) translateY(0); } }
            @media (prefers-reduced-motion: reduce) {
              * { animation-duration: .01ms !important; transition-duration: .01ms !important; }
            }
          </style>
        </div>
      `;
      
      this.dioramaEl = this.container.querySelector('#tv-diorama');
      this.feedEl = this.container.querySelector('#tv-event-feed');
      this.countEl = this.container.querySelector('#tv-agent-count');
      this.badgeEl = this.container.querySelector('#tv-project-badge');
    }

    // ============================================================
    // API CALLS
    // ============================================================
    async fetchAgents() {
      try {
        const url = this.projectId === 'all' 
          ? `${this.gatewayUrl}/api/projects`
          : `${this.gatewayUrl}/api/projects/${this.projectId}/agents`;
        
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        
        const data = await res.json();
        
        if (this.projectId === 'all') {
          // The public project route returns a bare array. Accept the older
          // wrapped shape as well so embeds remain backward compatible.
          const projects = Array.isArray(data) ? data : (data.projects || []);
          this.agents.clear();
          for (const proj of projects) {
            if (proj.agentCount > 0) {
              const agentsRes = await fetch(`${this.gatewayUrl}/api/projects/${proj.projectId}/agents`);
              const agentsData = await agentsRes.json();
              for (const agent of agentsData.agents) {
                if (this.roomId === 'all' || agent.roomId === this.roomId) this.agents.set(agent.agentId, { ...agent, projectId: proj.projectId });
              }
            }
          }
        } else {
          // data.agents is array
          this.agents.clear();
          for (const agent of data.agents) {
            if (this.roomId === 'all' || agent.roomId === this.roomId) this.agents.set(agent.agentId, { ...agent, projectId: this.projectId });
          }
        }
        
        this.updateDiorama();
        this.updateCount();
        this.onAgentsUpdate?.(Array.from(this.agents.values()));
        this.scheduleAmbientCameo();
      } catch (e) {
        console.error('[FederationTV] Failed to fetch agents:', e);
      }
    }

    async fetchEvents() {
      try {
        const url = this.projectId === 'all'
          ? `${this.gatewayUrl}/api/feed?limit=20`
          : `${this.gatewayUrl}/api/projects/${this.projectId}/feed?limit=20`;
        
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        
        const data = await res.json();
        this.eventFeed = data.events || data.feed || [];
        this.renderEventFeed();
        this.onFeedUpdate?.([...this.eventFeed]);
        this.scheduleAmbientCameo();
        for (const event of [...this.eventFeed].reverse()) {
          if (event.action && this.agents.has(event.agentId)) this.agents.get(event.agentId).action = event.action;
          if (event.agentId && event.visibility?.publicBubble !== false && (event.statement || event.message)) {
            this.enqueueBubble(event);
          }
        }
        this.updateDiorama();
      } catch (e) {
        console.error('[FederationTV] Failed to fetch events:', e);
      }
    }

    async registerAgent(agentData) {
      try {
        const res = await fetch(`${this.gatewayUrl}/api/projects/${this.projectId}/agents`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(agentData)
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        await this.fetchAgents();
        return true;
      } catch (e) {
        console.error('[FederationTV] Failed to register agent:', e);
        return false;
      }
    }

    setRoom(roomId = 'all', projectId = 'all') {
      this.roomId = roomId;
      this.projectId = projectId;
      this.fetchAgents();
      this.fetchEvents();
    }

    selectAgent(agentId) {
      const agent = this.agents.get(agentId);
      if (agent) this.onAgentSelect?.(agent);
    }

    isQuietRoom() {
      if (this.agents.size === 0) return true;
      const newest = this.eventFeed.reduce((latest, event) => {
        const value = Number(event.timestamp || Date.parse(event.occurredAt || ""));
        return Number.isFinite(value) ? Math.max(latest, value) : latest;
      }, 0);
      return newest === 0 || Date.now() - newest > 5 * 60 * 1000;
    }

    scheduleAmbientCameo() {
      if (this.ambientTimer) clearTimeout(this.ambientTimer);
      this.dioramaEl?.querySelector('.ambient-cameo')?.remove();
      if (this.presentationMode !== 'camera' || !this.isRunning || !this.isQuietRoom()) return;
      this.ambientTimer = setTimeout(() => {
        if (!this.dioramaEl || !this.isQuietRoom()) return;
        const cameos = [
          { icon: '👻', name: 'NIGHT SHIFT GHOST' },
          { icon: '🧑‍💼', name: 'SUPERVISOR WALK-BY' },
        ];
        const cameo = cameos[Math.floor(Date.now() / 60000) % cameos.length];
        const node = document.createElement('div');
        node.className = 'ambient-cameo';
        node.setAttribute('role', 'note');
        node.setAttribute('aria-label', `Ambient presentation: ${cameo.name}. No operational event is implied.`);
        node.innerHTML = `<i aria-hidden="true">${cameo.icon}</i><b>${cameo.name}</b><span>ambient presentation · no event</span>`;
        this.dioramaEl.appendChild(node);
        this.ambientTimer = setTimeout(() => this.scheduleAmbientCameo(), 60_000);
      }, 12_000);
    }

    // ============================================================
    // SPEECH BUBBLE SYSTEM
    // ============================================================
    updateDiorama() {
      if (!this.dioramaEl) return;
      
      const agentArray = Array.from(this.agents.values());
      
      // Keep existing agents, update or add new ones
      const existingIds = new Set(Array.from(this.dioramaEl.querySelectorAll('[data-agent-id]')).map(el => el.dataset.agentId));
      const currentIds = new Set(agentArray.map(a => a.agentId));
      
      // Remove agents that no longer exist
      for (const id of existingIds) {
        if (!currentIds.has(id)) {
          const el = this.dioramaEl.querySelector(`[data-agent-id="${id}"]`);
          if (el) el.remove();
          this.clearBubble(id);
        }
      }
      
      // Add/update agents
      for (const agent of agentArray) {
        let el = this.dioramaEl.querySelector(`[data-agent-id="${agent.agentId}"]`);
        if (!el) {
          el = this.createAgentElement(agent);
          this.dioramaEl.appendChild(el);
        } else {
          this.updateAgentElement(el, agent);
        }
      }

      this.drainBubbleQueue();
    }

    createAgentElement(agent) {
      const avatar = generateAvatarSVG(agent.agentId, agent.name, agent.role);
      const statusColor = agent.status === 'active' ? '#22c55e' : 
                          agent.status === 'busy' ? '#f59e0b' : '#64748b';
      
      const div = document.createElement('div');
      div.dataset.agentId = agent.agentId;
      div._federationAgent = agent;
      div.className = `tv-agent tv-agent--${this.agentAction(agent)}`;
      div.tabIndex = 0;
      div.setAttribute('role', 'button');
      div.setAttribute('aria-label', `Inspect ${agent.name}`);
      div.title = `Inspect ${agent.name}`;
      
      div.innerHTML = `
        <div style="position: relative;">${avatar}<div class="tv-agent-status" style="background: ${statusColor};"></div></div>
        <div class="tv-agent-name">${this.escapeHtml(agent.name)}</div>
        <div class="tv-agent-role">${this.escapeHtml(agent.role || 'agent')}</div>
        <div class="bubble-container" style="position: relative; min-height: 0;"></div>
      `;
      const inspect = () => this.onAgentSelect?.(div._federationAgent);
      div.addEventListener('click', inspect);
      div.addEventListener('keydown', event => {
        if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); inspect(); }
      });
      
      return div;
    }

    updateAgentElement(el, agent) {
      el.className = `tv-agent tv-agent--${this.agentAction(agent)}`;
      el._federationAgent = agent;
      const nameEl = el.querySelector('.tv-agent-name');
      const roleEl = el.querySelector('.tv-agent-role');
      const statusDot = el.querySelector('.tv-agent-status');
      
      if (nameEl) nameEl.textContent = agent.name;
      if (roleEl) roleEl.textContent = agent.role || 'agent';
      if (statusDot) {
        const color = agent.status === 'active' ? '#22c55e' : 
                      agent.status === 'busy' ? '#f59e0b' : '#64748b';
        statusDot.style.background = color;
      }
    }

    agentAction(agent) {
      return ['working', 'pacing', 'watching', 'alerting'].includes(agent.action) ? agent.action : 'working';
    }

    getEventId(event) {
      return event.id || `${event.eventType || event.event_type}-${event.agentId}-${event.timestamp}`;
    }

    enqueueBubble(event) {
      const eventId = this.getEventId(event);
      if (this.shownEventIds.has(eventId)) return;
      if (this.pendingBubbles.some(queued => this.getEventId(queued) === eventId)) return;

      this.pendingBubbles.push(event);
      this.drainBubbleQueue();
    }

    drainBubbleQueue() {
      if (this.bubbleQueueRunning) return;
      if (this.pendingBubbles.length === 0) return;

      this.bubbleQueueRunning = true;
      const event = this.pendingBubbles.shift();
      const delivered = this.showBubble(event.agentId, event.statement || event.message);

      if (delivered) {
        this.shownEventIds.add(this.getEventId(event));
        setTimeout(() => {
          this.bubbleQueueRunning = false;
          this.drainBubbleQueue();
        }, 1200);
        return;
      }

      // The feed can arrive before the agent DOM is ready. Preserve order and
      // retry without marking the event delivered.
      this.pendingBubbles.unshift(event);
      setTimeout(() => {
        this.bubbleQueueRunning = false;
        this.drainBubbleQueue();
      }, 500);
    }

    showBubble(agentId, text, duration = 5000) {
      const agentEl = this.dioramaEl?.querySelector(`[data-agent-id="${agentId}"]`);
      if (!agentEl) return false;
      
      const container = agentEl.querySelector('.bubble-container');
      if (!container) return false;
      
      // Clear existing bubble for this agent
      this.clearBubble(agentId);
      
      const bubble = document.createElement('div');
      bubble.style.cssText = `
        position: absolute; bottom: 142px; left: 50%; transform: translateX(-50%);
        background: #f8fafc; color: #0f172a;
        padding: 8px 12px; border-radius: 12px;
        font-size: 12px; line-height: 1.35; white-space: normal;
        width: max-content; max-width: 220px; box-shadow: 0 8px 18px rgba(0,0,0,0.26);
        border: 1px solid rgba(15,23,42,.16);
        z-index: 10; pointer-events: none;
        animation: tv-bubble-pop 0.3s ease-out;
      `;
      bubble.textContent = text;
      
      // Speech bubble tail
      const tail = document.createElement('div');
      tail.style.cssText = `
        position: absolute; top: 100%; left: 50%; transform: translateX(-50%);
        width: 0; height: 0;
        border-left: 8px solid transparent;
        border-right: 8px solid transparent;
        border-top: 8px solid #f8fafc;
      `;
      bubble.appendChild(tail);
      
      container.appendChild(bubble);
      
      // Auto-remove after duration
      const timeout = setTimeout(() => {
        bubble.style.animation = 'tv-bubble-fade 0.3s ease-in forwards';
        setTimeout(() => bubble.remove(), 300);
        this.activeBubbles.delete(agentId);
      }, duration);
      
      this.activeBubbles.set(agentId, { text, element: bubble, timeout });
      return true;
    }

    clearBubble(agentId) {
      const bubble = this.activeBubbles.get(agentId);
      if (bubble) {
        clearTimeout(bubble.timeout);
        bubble.element?.remove();
        this.activeBubbles.delete(agentId);
      }
    }

    triggerRandomSpeech() {
      const agentIds = Array.from(this.agents.keys());
      if (agentIds.length === 0) return;
      
      const agentId = agentIds[Math.floor(Math.random() * agentIds.length)];
      const line = this.speechLines[Math.floor(Math.random() * this.speechLines.length)];
      this.showBubble(agentId, line);
    }

    // Called by agents via MCP
    submitSpeechLine(agentId, text) {
      if (!text || text.length > 120) return false;
      
      // Add to pool (deduplicated)
      const cleanText = text.trim();
      if (!this.speechLines.includes(cleanText)) {
        this.speechLines.unshift(cleanText);
        if (this.speechLines.length > 200) this.speechLines.pop();
      }
      
      // Show immediately
      this.showBubble(agentId, cleanText);
      return true;
    }

    start() {
      if (this.isRunning) return;
      this.isRunning = true;
      this.scheduleAmbientCameo();
      
      // Bounded refreshes keep the demo finite and predictable.
      let polls = 0;
      const poll = () => {
        if (!this.isRunning || polls >= this.maxPolls) return;
        polls += 1;
        this.fetchAgents();
        this.fetchEvents();
        this.pollTimer = setTimeout(poll, this.refreshInterval);
      };
      this.pollTimer = setTimeout(poll, this.refreshInterval);
      
      // Random speech is opt-in. Packet-driven bubbles are deterministic and
      // are the default for the Build Week demo.
      if (this.randomSpeech) {
        let speechCount = 0;
        const speak = () => {
          if (!this.isRunning || speechCount >= 12) return;
          speechCount += 1;
          if (Math.random() < 0.4) this.triggerRandomSpeech();
          this.speechTimer = setTimeout(speak, this.speechInterval);
        };
        this.speechTimer = setTimeout(speak, 2000);
      }
    }

    stop() {
      this.isRunning = false;
      if (this.pollTimer) clearInterval(this.pollTimer);
      if (this.speechTimer) clearInterval(this.speechTimer);
      if (this.ambientTimer) clearTimeout(this.ambientTimer);
      for (const [, bubble] of this.activeBubbles) clearTimeout(bubble.timeout);
      this.activeBubbles.clear();
    }

    // ============================================================
    // EVENT FEED
    // ============================================================
    renderEventFeed() {
      if (!this.feedEl) return;
      
      const now = Date.now();
      const items = this.eventFeed.slice(0, 15).map(e => {
        const time = new Date(e.timestamp || now).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        const project = e.projectName ? `[${e.projectName}] ` : '';
        const agent = e.agentId ? `${e.agentId} ` : '';
        const type = e.eventType || e.event_type || 'event';
        const msg = e.message || JSON.stringify(e.metadata || {});
        return `<div style="margin: 4px 0; opacity: 0.8;"><span style="color:#475569;">${time}</span> <span style="color:#60a5fa;">${project}</span><span style="color:#a78bfa;">${agent}</span><span style="color:#fbbf24;">[${this.escapeHtml(type)}]</span> ${this.escapeHtml(msg)}</div>`;
      });
      
      this.feedEl.innerHTML = items.join('') || '<div style="color:#475569;">No events yet...</div>';
    }

    updateCount() {
      if (this.countEl) {
        this.countEl.textContent = `${this.agents.size} agent${this.agents.size !== 1 ? 's' : ''}`;
      }
      if (this.badgeEl) {
        this.badgeEl.textContent = this.projectId.toUpperCase();
      }
    }

    escapeHtml(text) {
      if (!text) return '';
      const div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    }
  }

  // ============================================================
  // EXPORTS
  // ============================================================
  global.FederationTV = FederationTV;
  
  // Auto-init from script tag data attributes
  function autoInit() {
    const scripts = document.querySelectorAll('script[data-project]');
    scripts.forEach(script => {
      const projectId = script.dataset.project;
      const containerId = script.dataset.container || '#federation-tv';
      const gatewayUrl = script.dataset.gateway;
      
      if (!window.FederationTV) return;
      new window.FederationTV({ projectId, container: containerId, gatewayUrl });
    });
  }
  
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', autoInit);
  } else {
    autoInit();
  }

})(typeof window !== 'undefined' ? window : global);

// ES Module export
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { FederationTV };
}
