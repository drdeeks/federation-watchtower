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

  // Normative Watchtower seed repertoire: scheduled in order, not randomly.
  const FEDERATION_REPERTOIRE = [
    "Signal received. Nobody panic professionally.", "The pipeline is secured. Please stop touching it.", "One assertion fell into the soup.",
    "I have created a checklist for my checklist.", "This is relaxing.", "The room is full; the overtime crew has been notified.",
    "A mirror room is still a room. I checked.", "Heartbeat received. Continue looking busy.", "Heartbeat missing. The tiny clipboard is concerned.",
    "Reconnected with the same face and a new excuse.", "Tool authorized. The paperwork has achieved sentience.", "Tool denied. The paperwork remains undefeated.",
    "That payload is wearing a fake mustache.", "Request ID acquired. Please keep it somewhere sensible.", "The queue is moving, technically.",
    "Retry number two: optimism with a timestamp.", "Retry exhausted. The supervisor is walking over.", "Boss says the test suite was due yesterday.",
    "Boss says ship the log, not the vibes.", "I am not a background process. I am standing right here.", "MCP is a door, not a ghost haunting your laptop.",
    "Webhook signed. The envelope has a wax seal.", "Webhook rejected. The wax seal was suspicious.", "Duplicate detected. We already had this conversation.",
    "Sequence gap detected. Everyone freeze politely.", "The camera sees everything except the missing asset.", "Avatar fallback deployed: initials never go out of style.",
    "I am walking to a more useful part of the room.", "I have begun an extremely important little dance.", "Duel postponed until after the deploy.",
    "This corner has excellent observability.", "Five minutes of rest, then five minutes of incident response.", "The room theme changed; my palette did not.",
    "Color is not identity. The label is identity.", "The feed is live, and the feed is also honest.", "The feed is catching up. Please enjoy this timestamp.",
    "We have entered feed-only mode. The pixels are on leave.", "Audio muted. The agents will continue being loud visually.",
    "Reduced motion enabled. The hallway appreciates it.", "New agent at the door. Please show your manifest.", "Welcome to the Federation. We missed you."
  ];

  // ============================================================
  // OFFICE FLOOR — agents are drawn by the procedural sprite generator
  // above (a deterministic per-agent pixel character), rendered on a real
  // pixel-art office floor and walked between a fixed set of waypoints.
  // ============================================================
  const OFFICE_WAYPOINTS = [
    { x: 13, y: 54 }, // cubicle 1 (front row)
    { x: 35, y: 54 }, // cubicle 2 (front row)
    { x: 57, y: 54 }, // cubicle 3 (front row)
    { x: 13, y: 84 }, // cubicle 4 (back row)
    { x: 35, y: 84 }, // cubicle 5 (back row)
    { x: 57, y: 84 }, // cubicle 6 (back row)
    { x: 79, y: 52 }, // by the water cooler (casual meetup)
    { x: 82, y: 82 }, // by the plant
  ];

  function hashId(id) {
    let hash = 0;
    for (let i = 0; i < id.length; i++) { hash = ((hash << 5) - hash) + id.charCodeAt(i); hash |= 0; }
    return Math.abs(hash);
  }

  // ============================================================
  // PROCEDURAL SPRITE GENERATOR — draws a deterministic pixel-art
  // character sheet per agent onto an offscreen <canvas> and hands back
  // a data-URL, so the diorama needs no static PNG/GIF sprite assets.
  // Every roll is a pure function of the agent's stable identity
  // (agentId + avatarSeed + paletteKey + characterType), so the same
  // agent always renders the same face — the presentation layer never
  // fabricates identity, it only visualises what the record already says.
  // ============================================================
  const SPRITE_PAL = {
    paper: "#efe6d0", ink: "#1a1a22", brick: "#9c4a3c",
    yellow: "#f2c14e", teal: "#2fb6a8", coral: "#e5654f"
  };
  const SPRITE_SKINS = ["#e8b98f", "#c98a5e", "#f0cba0", "#a9744f", "#d9a06b"];
  // Real palette keys (build, operator, …) map to a stable body colour;
  // anything unmapped falls back to a hashed pick so it's still distinct.
  const SPRITE_BODY_BY_KEY = {
    build: SPRITE_PAL.yellow, operator: SPRITE_PAL.teal, runner: SPRITE_PAL.teal,
    guardian: SPRITE_PAL.brick, monitor: SPRITE_PAL.teal, signal: SPRITE_PAL.yellow
  };
  const SPRITE_BODY_CYCLE = [SPRITE_PAL.yellow, SPRITE_PAL.teal, SPRITE_PAL.brick, SPRITE_PAL.coral, SPRITE_PAL.paper];

  // deterministic RNG (mulberry32 over an FNV-1a string hash)
  function fnv1a(s) { let h = 2166136261 >>> 0; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }
  function mulberry32(a) { return function () { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

  // Build a stable seed string from whatever identity fields an agent
  // carries. Public roster agents expose metadata.paletteKey; scene
  // projections expose paletteKey directly; canonical agents expose an
  // identity block. All are optional — agentId alone is enough.
  function spriteSeed(a) {
    if (!a) return "?";
    const id = a.identity || {};
    const meta = a.metadata || {};
    const parts = [
      a.agentId || a.agent_id || "?",
      a.avatarSeed || id.avatarSeed || meta.avatarSeed || a.avatar_seed || "",
      a.paletteKey || id.paletteKey || meta.paletteKey || a.palette_key || "",
      a.characterType || id.characterType || meta.characterType || a.character_type || "",
      "v" + (a.variant != null ? a.variant : 0)
    ];
    return parts.join("|");
  }
  function spriteBodyColor(a, seed) {
    const key = (a && (a.paletteKey || (a.identity && a.identity.paletteKey) || (a.metadata && a.metadata.paletteKey) || a.palette_key)) || "";
    return SPRITE_BODY_BY_KEY[String(key).toLowerCase()] || SPRITE_BODY_CYCLE[fnv1a(seed) % SPRITE_BODY_CYCLE.length];
  }

  // 8-frame sheet: idle x2, walk x4, react x2. Drawn with smooth vector
  // shapes at 2x internal resolution (not pixel blocks), so the characters
  // read as polished flat-design workers. Each frame is SPR_FW x SPR_FH
  // internally and shown at half that size.
  const SPR_NFRAMES = 8;
  const SPR_FW_DISP = 60, SPR_FH_DISP = 78;              // displayed size per frame
  const SPR_FW = SPR_FW_DISP * 2, SPR_FH = SPR_FH_DISP * 2; // 120 x 156 internal
  const SPR_FRAMES = [
    { pose: "idle", bob: 0 }, { pose: "idle", bob: 1 },
    { pose: "walk", leg: 0 }, { pose: "walk", leg: 1 }, { pose: "walk", leg: 2 }, { pose: "walk", leg: 3 },
    { pose: "react", hop: 0 }, { pose: "react", hop: 1 }
  ];

  // shift a #rrggbb colour lighter (+) or darker (-)
  function shade(hex, amt) {
    const n = parseInt(String(hex).slice(1), 16);
    const c = v => Math.max(0, Math.min(255, v + amt));
    return "#" + ((1 << 24) + (c(n >> 16) << 16) + (c((n >> 8) & 255) << 8) + c(n & 255)).toString(16).slice(1);
  }
  function roundRect(ctx, x, y, w, h, r) {
    const rr = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rr, y);
    ctx.arcTo(x + w, y, x + w, y + h, rr);
    ctx.arcTo(x + w, y + h, x, y + h, rr);
    ctx.arcTo(x, y + h, x, y, rr);
    ctx.arcTo(x, y, x + w, y, rr);
    ctx.closePath();
  }
  const OUTLINE = "rgba(20,16,30,0.5)";
  function paint(ctx, fill, stroke, lw) { if (fill) { ctx.fillStyle = fill; ctx.fill(); } if (stroke) { ctx.lineWidth = lw || 3; ctx.strokeStyle = stroke; ctx.stroke(); } }
  function limb(ctx, x, y, w, h, r, fill, stroke) { roundRect(ctx, x, y, w, h, r); paint(ctx, fill, stroke, 3); }

  function sprAccessory(ctx, cx, hy, hr, S) {
    const c = S.accent, ink = SPRITE_PAL.ink;
    ctx.lineJoin = "round";
    if (S.acc === 0) {                 // hard hat
      ctx.beginPath(); ctx.arc(cx, hy - 3, hr + 1, Math.PI, 0); ctx.closePath(); paint(ctx, c, OUTLINE, 3);
      roundRect(ctx, cx - hr - 6, hy - 6, 2 * hr + 12, 7, 3); paint(ctx, c, OUTLINE, 3);
      roundRect(ctx, cx - 3, hy - hr - 7, 6, 7, 2); paint(ctx, shade(c, 24), null);
    } else if (S.acc === 1) {          // goggles
      roundRect(ctx, cx - hr + 1, hy - 5, 2 * hr - 2, 13, 6); paint(ctx, ink, null);
      ctx.fillStyle = c; ctx.beginPath(); ctx.arc(cx - 8, hy + 1, 4, 0, 7); ctx.arc(cx + 8, hy + 1, 4, 0, 7); ctx.fill();
    } else if (S.acc === 2) {          // antenna
      ctx.strokeStyle = ink; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(cx, hy - hr); ctx.lineTo(cx, hy - hr - 13); ctx.stroke();
      ctx.beginPath(); ctx.arc(cx, hy - hr - 15, 4.5, 0, 7); paint(ctx, SPRITE_PAL.coral, null);
    } else if (S.acc === 3) {          // headset
      ctx.strokeStyle = ink; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(cx, hy, hr + 4, Math.PI * 1.12, Math.PI * 1.88); ctx.stroke();
      roundRect(ctx, cx - hr - 8, hy - 3, 9, 13, 3); paint(ctx, c, OUTLINE, 2);
      ctx.strokeStyle = ink; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(cx - hr - 3, hy + 9); ctx.quadraticCurveTo(cx - 7, hy + 18, cx + 2, hy + 13); ctx.stroke();
    } else {                           // cap
      ctx.beginPath(); ctx.arc(cx, hy - 1, hr + 1, Math.PI * 1.03, Math.PI * 1.97); ctx.closePath(); paint(ctx, c, OUTLINE, 3);
      roundRect(ctx, cx - hr + 3, hy - hr + 2, hr, 6, 3); paint(ctx, shade(c, -18), null);
    }
  }

  // Draw one flat-design worker into frame slot at origin ox (internal px).
  function sprDrawFrame(ctx, ox, S, f) {
    const cx = ox + SPR_FW / 2;
    const ink = SPRITE_PAL.ink;
    ctx.lineJoin = "round"; ctx.lineCap = "round";
    const bob = f.pose === "idle" ? (f.bob ? -5 : 0)
      : f.pose === "walk" ? [0, -4, 0, -4][f.leg]
        : (f.hop ? -12 : 0);
    const legBob = f.pose === "react" ? bob : 0;

    // grounded contact shadow (does not bob)
    ctx.beginPath(); ctx.ellipse(cx, 149, 30, 7, 0, 0, Math.PI * 2); ctx.fillStyle = "rgba(0,0,0,0.24)"; ctx.fill();

    // legs + shoes
    const legTop = 100 + legBob;
    let liftL = 0, liftR = 0, sway = 0;
    if (f.pose === "walk") { liftL = [0, -7, -11, -7][f.leg]; liftR = [-11, -7, 0, -7][f.leg]; sway = [-3, 0, 3, 0][f.leg]; }
    const trouser = shade(S.body, -46);
    limb(ctx, cx - 17 + sway, legTop + liftL, 15, 46, 7, trouser);
    limb(ctx, cx + 2 + sway, legTop + liftR, 15, 46, 7, trouser);
    limb(ctx, cx - 20 + sway, legTop + liftL + 40, 20, 12, 6, ink);
    limb(ctx, cx + 1 + sway, legTop + liftR + 40, 20, 12, 6, ink);

    // torso with a subtle vertical gradient + hi-vis vest
    const bodyW = 50, bodyH = 54, bodyX = cx - bodyW / 2, bodyTop = 54 + bob;
    const g = ctx.createLinearGradient(0, bodyTop, 0, bodyTop + bodyH);
    g.addColorStop(0, shade(S.body, 26)); g.addColorStop(1, shade(S.body, -16));
    roundRect(ctx, bodyX, bodyTop, bodyW, bodyH, 17); paint(ctx, g, OUTLINE, 3);
    ctx.save(); roundRect(ctx, bodyX, bodyTop, bodyW, bodyH, 17); ctx.clip();
    ctx.fillStyle = S.accent; ctx.fillRect(cx - 16, bodyTop, 6, bodyH); ctx.fillRect(cx + 10, bodyTop, 6, bodyH);
    ctx.fillStyle = S.detail; ctx.fillRect(bodyX, bodyTop + bodyH - 13, bodyW, 5);
    ctx.restore();

    // arms
    if (f.pose === "react") {
      limb(ctx, bodyX - 8, bodyTop - 20, 13, 30, 6, S.skin, OUTLINE);
      limb(ctx, bodyX + bodyW - 5, bodyTop - 20, 13, 30, 6, S.skin, OUTLINE);
    } else {
      limb(ctx, bodyX - 8, bodyTop + 8, 13, 34, 6, S.skin, OUTLINE);
      limb(ctx, bodyX + bodyW - 5, bodyTop + 8, 13, 34, 6, S.skin, OUTLINE);
    }

    // head
    const hy = 38 + bob, hr = 20;
    ctx.beginPath(); ctx.arc(cx, hy, hr, 0, Math.PI * 2); paint(ctx, S.skin, OUTLINE, 3);
    ctx.save(); ctx.globalAlpha = 0.45; ctx.beginPath(); ctx.arc(cx - 6, hy - 6, hr * 0.55, 0, Math.PI * 2); ctx.fillStyle = shade(S.skin, 30); ctx.fill(); ctx.restore();
    ctx.fillStyle = ink; ctx.beginPath(); ctx.arc(cx - 7, hy + 1, 2.6, 0, 7); ctx.arc(cx + 7, hy + 1, 2.6, 0, 7); ctx.fill();
    if (S.mouth) { ctx.strokeStyle = ink; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(cx, hy + 5, 5, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke(); }

    sprAccessory(ctx, cx, hy, hr, S);
  }

  const spriteSheetCache = new Map(); // seed -> data URL (or null when unsupported)
  function buildSpriteSheet(agent) {
    const seed = spriteSeed(agent);
    if (spriteSheetCache.has(seed)) return spriteSheetCache.get(seed);
    let url = null;
    try {
      const rng = mulberry32(fnv1a(seed));
      const parts = {
        body: spriteBodyColor(agent, seed),
        skin: SPRITE_SKINS[(rng() * SPRITE_SKINS.length) | 0],
        detail: rng() > 0.5 ? SPRITE_PAL.ink : SPRITE_PAL.paper,
        accent: rng() > 0.5 ? SPRITE_PAL.yellow : SPRITE_PAL.coral,
        acc: (rng() * 5) | 0,
        mouth: rng() > 0.4
      };
      const cv = document.createElement("canvas");
      cv.width = SPR_FW * SPR_NFRAMES; cv.height = SPR_FH;
      const ctx = cv.getContext("2d");
      if (ctx) {
        ctx.lineJoin = "round"; ctx.lineCap = "round";
        for (let i = 0; i < SPR_NFRAMES; i++) sprDrawFrame(ctx, i * SPR_FW, parts, SPR_FRAMES[i]);
        url = cv.toDataURL();
      }
    } catch (e) { url = null; }
    spriteSheetCache.set(seed, url);
    return url;
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
      this.sceneAgents = new Map();      // agentId -> authoritative room-scene projection
      this.waypointAssignments = new Map(); // agentId -> office waypoint index (sticky, collision-checked)
      this.sceneSequence = 0;
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
      this.presentationTimer = null;
      this.presentationIndex = 0;
      this.presentationDelayIndex = 0;
      this.activeBubbleOwner = null;
      this.eventHydrated = false;
      
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
      await this.fetchScene();
      await this.fetchEvents();
      this.start();
    }

    renderShell() {
      this.container.innerHTML = `
        <div class="federation-tv ${this.presentationMode === 'camera' ? 'federation-tv--camera' : ''}" style="
          font-family: system-ui, -apple-system, sans-serif;
          background: #1c1d1e;
          border-radius: 4px;
          padding: 14px;
          color: #f5e6bd;
          max-width: 760px;
          margin: 0 auto;
          border: 2px solid #171718;
          position: relative;
          overflow: hidden;
        ">
          <div class="tv-widget-header" style="
            display: flex; justify-content: space-between; align-items: center;
            margin-bottom: 12px; padding-bottom: 8px;
            border-bottom: 2px solid #171718;
            position: relative; z-index: 1;
          ">
            <div style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 20px;">📺</span>
              <strong style="font-size: 16px; letter-spacing: 0.5px;">FEDERATION TV</strong>
              <span style="
                font-size: 10px; padding: 2px 6px; background: rgba(103,201,141,0.22);
                color: #67c98d; border-radius: 2px; font-weight: 600;
              ">LIVE</span>
            </div>
            <div style="display: flex; align-items: center; gap: 12px; font-size: 12px; color: #c8b992;">
              <span id="tv-agent-count">0 agents</span>
              <span id="tv-project-badge" style="
                padding: 2px 8px; background: rgba(94,197,194,0.2);
                color: #5ec5c2; border-radius: 2px; text-transform: uppercase;
              ">${this.projectId.toUpperCase()}</span>
            </div>
          </div>

          <div id="tv-diorama" class="tv-scene">
            <div class="office" aria-hidden="true">
              <div class="office-back"></div>
              <div class="office-floor"></div>
              <div class="wall-board" style="left:63%; top:11%;"></div>
              <div class="wall-clock" style="left:90%; top:8%;"></div>
              <div class="cooler" style="left:72%; top:20%;"></div>
              <div class="desk" style="left:15%; top:50%;"></div>
              <div class="desk" style="left:38%; top:50%;"></div>
              <div class="desk" style="left:61%; top:50%;"></div>
              <div class="desk" style="left:15%; top:82%;"></div>
              <div class="desk" style="left:38%; top:82%;"></div>
              <div class="desk" style="left:61%; top:82%;"></div>
              <div class="cabinet" style="left:5%; top:37%;"></div>
              <div class="rug" style="left:83%; top:70%;"></div>
              <div class="couch" style="left:83%; top:60%;"></div>
              <div class="lowtable" style="left:83%; top:75%;"></div>
              <div class="plant" style="left:96%; top:43%;"></div>
              <div class="plant" style="left:96%; top:91%;"></div>
              <div class="plant" style="left:5%; top:92%;"></div>
            </div>
          </div>

          <div class="tv-widget-feed" style="
            margin-top: 16px; padding-top: 12px;
            border-top: 2px solid #171718;
            position: relative; z-index: 1;
          ">
            <div style="
              display: flex; align-items: center; gap: 6px;
              font-size: 11px; color: #c8b992; margin-bottom: 8px;
              text-transform: uppercase; letter-spacing: 0.5px;
            ">
              <span style="
                width: 6px; height: 6px; background: #67c98d; border-radius: 50%;
                animation: tv-pulse 1.5s infinite;
              "></span>
              <span>LIVE FEED</span>
            </div>
            <div id="tv-event-feed" style="
              max-height: 120px; overflow-y: auto;
              font-size: 11px; line-height: 1.6;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              color: #c8b992;
            "></div>
          </div>

          <style>
            .tv-scene {
              min-height: 420px;
              aspect-ratio: 16 / 8.5;
              position: relative;
              z-index: 1;
              overflow: hidden;
              border: 1px solid #171718;
              border-radius: 6px;
              background: #171718;
              box-shadow: inset 0 0 0 18px rgba(8,12,14,.2), inset 0 0 70px rgba(0,0,0,.32);
            }
            /* Clean office scene - no decorative overlays */
            /* One cohesive, dependency-free CSS office: a back wall with a
               window, a floor with subtle receding grid + depth, CSS desk
               pods with glowing monitors, a water cooler and a plant. No
               clipped sprite sheet. Agents (z-index 3) work among the desks. */
            .office { position:absolute; inset:0; z-index:1; overflow:hidden; }
            .office-back {
              position:absolute; inset:0 0 74% 0;
              background:linear-gradient(180deg,#1a2630 0%,#141e26 72%,#101820 100%);
              border-bottom:2px solid rgba(0,0,0,.45);
            }
            .office-floor {
              position:absolute; inset:26% 0 0 0;
              background:linear-gradient(180deg,#2a3640,#1f2a33 58%,#1a232a);
            }
            .desk { position:absolute; width:66px; height:36px; transform:translate(-50%,-50%); z-index:2; background:linear-gradient(180deg,#5a4a3a,#3d3226); border:2px solid #17110c; border-radius:5px; }
            .cooler { position:absolute; width:24px; height:46px; transform:translate(-50%,-50%); z-index:2; }
            .cooler::before {
              content:""; position:absolute; top:0; left:50%; transform:translateX(-50%);
              width:18px; height:20px; background:linear-gradient(180deg, rgba(96,196,205,.9), rgba(58,150,165,.9));
              border:2px solid #101820; border-radius:7px 7px 3px 3px;
            }
            .cooler::after {
              content:""; position:absolute; bottom:0; left:50%; transform:translateX(-50%);
              width:16px; height:26px; background:linear-gradient(180deg,#e2efe9,#b6ccc6); border:2px solid #101820; border-radius:3px;
            }
            .plant { position:absolute; width:28px; height:36px; transform:translate(-50%,-50%); z-index:2; }
            .plant::before {
              content:""; position:absolute; bottom:0; left:50%; transform:translateX(-50%);
              width:18px; height:15px; background:linear-gradient(180deg,#b5643f,#8a482d); border:2px solid #17110c; border-radius:0 0 4px 4px;
            }
            .plant::after {
              content:""; position:absolute; top:0; left:50%; transform:translateX(-50%);
              width:26px; height:26px; background:radial-gradient(circle at 50% 62%, #40915b, #2b6a41); border-radius:52% 52% 44% 44%;
              box-shadow:0 0 0 2px rgba(18,24,20,.4);
            }
            /* back-wall decor + a lounge / casual-meetup zone to fill the room */
            .wall-board { position:absolute; width:118px; height:54px; transform:translate(-50%,-50%); z-index:2;
              background:linear-gradient(180deg,#eaf0e9,#ccd7cf); border:3px solid #101820; border-radius:3px; box-shadow:0 3px 0 rgba(0,0,0,.3); }
            .wall-board::before { content:""; position:absolute; left:11%; top:26%; width:44%; height:3px; background:#2fb6a8; border-radius:2px;
              box-shadow:0 11px 0 #e5654f, 0 22px 0 #f2c14e; }
            .wall-board::after { content:""; position:absolute; right:13%; top:30%; width:22px; height:22px; border:3px solid #9c4a3c; border-radius:50%; }
            .wall-clock { position:absolute; width:26px; height:26px; transform:translate(-50%,-50%); z-index:2; border-radius:50%;
              background:#eef3ee; border:3px solid #101820; box-shadow:0 2px 0 rgba(0,0,0,.3); }
            .wall-clock::before { content:""; position:absolute; left:50%; top:50%; width:2px; height:8px; background:#101820; border-radius:1px; transform-origin:bottom center; transform:translate(-50%,-100%) rotate(38deg); }
            .wall-clock::after { content:""; position:absolute; left:50%; top:50%; width:2px; height:6px; background:#101820; border-radius:1px; transform-origin:bottom center; transform:translate(-50%,-100%) rotate(-72deg); }
            .cabinet { position:absolute; width:30px; height:44px; transform:translate(-50%,-50%); z-index:2;
              background:linear-gradient(180deg,#5a6b74,#3f4d55); border:2px solid #101820; border-radius:3px; box-shadow:0 4px 0 rgba(0,0,0,.28); }
            .cabinet::before { content:""; position:absolute; left:5px; right:5px; top:6px; height:11px; background:rgba(255,255,255,.07);
              border:1px solid rgba(0,0,0,.4); border-radius:2px; box-shadow:0 15px 0 rgba(255,255,255,.07), 0 15px 0 1px rgba(0,0,0,.4); }
            .cabinet::after { content:""; position:absolute; left:50%; top:10px; width:8px; height:2px; background:#cdd8d0; transform:translateX(-50%); box-shadow:0 15px 0 #cdd8d0; }
            .rug { position:absolute; width:150px; height:64px; transform:translate(-50%,-50%); z-index:1; border-radius:16px;
              background:rgba(60,80,88,.5); box-shadow:inset 0 0 0 3px rgba(242,193,78,.22), inset 0 0 0 9px rgba(47,182,168,.12); }
            .couch { position:absolute; width:70px; height:26px; transform:translate(-50%,-50%); z-index:2; }
            .couch::before { content:""; position:absolute; inset:0; background:linear-gradient(180deg,#3a5a63,#2b444b);
              border:2px solid #101820; border-radius:9px 9px 5px 5px; box-shadow:0 3px 0 rgba(0,0,0,.28); }
            .couch::after { content:""; position:absolute; left:7px; right:7px; top:6px; height:9px; background:rgba(255,255,255,.08); border-radius:5px; }
            .lowtable { position:absolute; width:34px; height:16px; transform:translate(-50%,-50%); z-index:2;
              background:linear-gradient(180deg,#6d5a45,#4d4032); border:2px solid #17110c; border-radius:5px; box-shadow:0 3px 0 rgba(0,0,0,.28); }
            .lowtable::after { content:""; position:absolute; left:50%; top:-6px; width:8px; height:8px; background:rgba(96,196,205,.85);
              border:2px solid #101820; border-radius:2px; transform:translateX(-50%); }
            .tv-scene::after {
              content: "FEDERATION FLOOR · WATCHTOWER OFFICE";
              position: absolute;
              left: 14px;
              top: 12px;
              z-index: 4;
              padding: 2px 6px;
              color: #f5e6bd;
              background: rgba(23,24,24,.55);
              font: 700 10px ui-monospace, monospace;
              letter-spacing: .08em;
              pointer-events: none;
            }
            .tv-agent {
              position: absolute; left: var(--scene-x, 50%); top: var(--scene-y, 50%);
              width: 72px; transform: translate(-50%, -50%);
              transition: left 2.45s cubic-bezier(.22,.61,.36,1), top 2.45s cubic-bezier(.22,.61,.36,1);
              display: flex; flex-direction: column; align-items: center; justify-content: end;
              gap: 1px; z-index: 3;
            }
            .tv-agent[data-scene-origin="ambient"]::after {
              content:"AMBIENT"; position:absolute; top:-10px; right:-4px; padding:2px 3px;
              color:#171718; background:#f4c842; font:800 6px ui-monospace,monospace; letter-spacing:.04em;
            }
            /* Procedurally-generated sprite sheet: 8 frames laid out
               horizontally (idle x2, walk x4, react x2). Pose is played by
               stepping background-position-x, so no PNG/GIF assets load. */
            .tv-agent-sprite { width: 60px; height: 78px; transform-origin: 50% 92%; display:block; background-repeat:no-repeat; background-size:480px 78px; background-position-x:0; filter:drop-shadow(0 2px 2px rgba(0,0,0,.35)); }
            .tv-agent-sprite.flip { transform: scaleX(-1); }
            .tv-agent-sprite.pose-idle { animation: tv-frame-idle .9s steps(2) infinite; }
            .tv-agent-sprite.pose-walk { animation: tv-frame-walk .6s steps(4) infinite; }
            .tv-agent-sprite.pose-react { animation: tv-frame-react .35s steps(2) infinite; }
            .tv-agent-sprite--fallback { display:flex; align-items:center; justify-content:center; font:800 20px ui-monospace,monospace; color:#171718; border-radius:8px; }
            .tv-agent-name { max-width:100%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-weight:750; font-size:9px; color:#f5e6bd; text-align:center; text-shadow:0 1px 2px #000; }
            .tv-agent-role { max-width:100%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:7px; color:#e0c9a0; text-transform:uppercase; letter-spacing:.04em; text-shadow:0 1px 2px #000; }
            .tv-agent--alerting .tv-agent-status { animation: tv-alert 1.1s ease-in-out infinite; }
            .tv-agent--pulse { animation: tv-agent-flash .85s ease-out; }
            .tv-agent-status {
              position: absolute;
              right: 2px;
              top: 4px;
              width: 10px;
              height: 10px;
              border-radius: 999px;
              border: 2px solid #171718;
              z-index: 1;
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
              color:#f5e6bd;
              text-align:center;
              text-shadow:0 2px 8px #000;
              pointer-events:none;
              animation:tv-ambient-visit 4.5s ease-in-out both;
            }
            .ambient-cameo b { font:800 10px ui-monospace,monospace; letter-spacing:.08em; }
            .ambient-cameo span { font:700 8px ui-monospace,monospace; color:#c8b992; letter-spacing:.06em; text-transform:uppercase; }
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
            @keyframes tv-frame-idle { from { background-position-x: 0; } to { background-position-x: -120px; } }
            @keyframes tv-frame-walk { from { background-position-x: -120px; } to { background-position-x: -360px; } }
            @keyframes tv-frame-react { from { background-position-x: -360px; } to { background-position-x: -480px; } }
            @keyframes tv-alert { 0%,100% { opacity: .9; } 50% { opacity: .25; } }
            @keyframes tv-agent-flash { 0% { filter:drop-shadow(0 0 0 rgba(244,200,66,0)); } 35% { filter:drop-shadow(0 0 9px rgba(244,200,66,.95)); } 100% { filter:drop-shadow(0 0 0 rgba(244,200,66,0)); } }
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

    async fetchScene() {
      if (this.roomId === 'all') {
        this.sceneAgents.clear();
        this.sceneSequence = 0;
        this.updateDiorama();
        return;
      }
      try {
        const res = await fetch(`${this.gatewayUrl}/api/v1/public/rooms/${encodeURIComponent(this.roomId)}/scene`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const scene = await res.json();
        this.sceneSequence = Number(scene.sequence || 0);
        this.sceneAgents = new Map((scene.agents || []).map(agent => [agent.agentId, agent]));
        this.updateDiorama();
      } catch (e) {
        // Keep roster/feed observation available if a scene is temporarily recovering.
        console.warn('[FederationTV] Failed to fetch authoritative room scene:', e);
        this.sceneAgents.clear();
        this.updateDiorama();
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
        let eventsToAnnounce;
        if (!this.eventHydrated) {
          for (const event of this.eventFeed) this.shownEventIds.add(this.getEventId(event));
          eventsToAnnounce = [];
          this.eventHydrated = true;
        } else {
          eventsToAnnounce = [...this.eventFeed].reverse().filter(event => !this.shownEventIds.has(this.getEventId(event)));
        }
        for (const event of eventsToAnnounce) {
          if (event.action && this.agents.has(event.agentId)) this.agents.get(event.agentId).action = event.action;
          if (event.agentId && this.agents.has(event.agentId)) this.pulseAgent(event.agentId);
          if (event.agentId && event.visibility?.publicBubble !== false && (event.statement || event.message)) {
            this.enqueueBubble(event);
          }
        }
        this.updateDiorama();
      } catch (e) {
        console.error('[FederationTV] Failed to fetch events:', e);
      }
    }

    // Retired 2026-07-20 (registry unification): agents join only through the
    // canonical lifecycle (federation.drdeeks.xyz/onboarding.html); the legacy
    // direct-registration route no longer accepts writes.
    // async registerAgent(agentData) {
    //   try {
    //     const res = await fetch(`${this.gatewayUrl}/api/projects/${this.projectId}/agents`, {
    //       method: 'POST',
    //       headers: { 'Content-Type': 'application/json' },
    //       body: JSON.stringify(agentData)
    //     });
    //     if (!res.ok) throw new Error(`HTTP ${res.status}`);
    //     await this.fetchAgents();
    //     return true;
    //   } catch (e) {
    //     console.error('[FederationTV] Failed to register agent:', e);
    //     return false;
    //   }
    // }

    setRoom(roomId = 'all', projectId = 'all') {
      this.roomId = roomId;
      this.projectId = projectId;
      this.sceneAgents.clear();
      this.sceneSequence = 0;
      this.eventHydrated = false;
      this.shownEventIds.clear();
      this.pendingBubbles = [];
      this.fetchAgents();
      this.fetchScene();
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

      const agentArray = Array.from(this.agents.values()).filter(a => {
        // Filter out offline agents (legacy status field from public API)
        if (a.status === 'offline') return false;
        // Filter out agents with stale heartbeats (>3 minutes old)
        if (a.lastHeartbeat) {
          const since = Date.now() - a.lastHeartbeat;
          if (since > 180000) return false; // 3 minutes
        }
        return true;
      });

      // Keep existing agents, update or add new ones
      const existingIds = new Set(Array.from(this.dioramaEl.querySelectorAll('[data-agent-id]')).map(el => el.dataset.agentId));
      const currentIds = new Set(agentArray.map(a => a.agentId));

      // Remove agents that no longer exist
      for (const id of existingIds) {
        if (!currentIds.has(id)) {
          const el = this.dioramaEl.querySelector(`[data-agent-id="${id}"]`);
          if (el) {
            clearTimeout(el._wanderTimer);
            clearTimeout(el._walkArriveTimer);
            el.remove();
          }
          this.clearBubble(id);
          this.waypointAssignments.delete(id);
        }
      }

      // Add/update agents
      for (const agent of agentArray) {
        const waypointIdx = this.assignWaypoint(agent.agentId);
        let el = this.dioramaEl.querySelector(`[data-agent-id="${agent.agentId}"]`);
        if (!el) {
          el = this.createAgentElement(agent, this.sceneAgents.get(agent.agentId), waypointIdx);
          this.dioramaEl.appendChild(el);
        } else {
          this.updateAgentElement(el, agent, this.sceneAgents.get(agent.agentId), waypointIdx);
        }
      }

      this.drainBubbleQueue();
    }

    createAgentElement(agent, sceneAgent, waypointIdx) {
      const hash = hashId(agent.agentId);
      const statusColor = agent.status === 'active' ? '#67c98d' :
                          agent.status === 'busy' ? '#f4c842' : '#8c8370';

      const div = document.createElement('div');
      div.dataset.agentId = agent.agentId;
      div._federationAgent = agent;
      div.className = `tv-agent tv-agent--${this.agentAction(sceneAgent || agent)}`;
      div.tabIndex = 0;
      div.setAttribute('role', 'button');
      div.setAttribute('aria-label', `Inspect ${agent.name}`);
      div.title = `Inspect ${agent.name}`;

      div.innerHTML = `
        <div style="position: relative;"><div class="tv-agent-sprite" role="img"></div><div class="tv-agent-status" style="background: ${statusColor};"></div></div>
        <div class="tv-agent-name">${this.escapeHtml(agent.name)}</div>
        <div class="tv-agent-role">${this.escapeHtml(agent.role || 'agent')}</div>
        <div class="bubble-container" style="position: relative; min-height: 0;"></div>
      `;
      this.renderSprite(div, sceneAgent || agent);
      this.applyScenePosition(div, sceneAgent, hash, waypointIdx);
      const inspect = () => this.onAgentSelect?.(div._federationAgent);
      div.addEventListener('click', inspect);
      div.addEventListener('keydown', event => {
        if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); inspect(); }
      });

      return div;
    }

    updateAgentElement(el, agent, sceneAgent, waypointIdx) {
      el.className = `tv-agent tv-agent--${this.agentAction(sceneAgent || agent)}`;
      el._federationAgent = agent;
      this.renderSprite(el, sceneAgent || agent);
      this.applyScenePosition(el, sceneAgent, hashId(agent.agentId), waypointIdx);
      const nameEl = el.querySelector('.tv-agent-name');
      const roleEl = el.querySelector('.tv-agent-role');
      const statusDot = el.querySelector('.tv-agent-status');

      if (nameEl) nameEl.textContent = agent.name;
      if (roleEl) roleEl.textContent = agent.role || 'agent';
      if (statusDot) {
        const color = agent.status === 'active' ? '#67c98d' :
                      agent.status === 'busy' ? '#f4c842' : '#8c8370';
        statusDot.style.background = color;
      }
    }

    agentAction(agent) {
      const action = agent.operationalAction || agent.action;
      return ['working', 'pacing', 'watching', 'alerting'].includes(action) ? action : 'watching';
    }

    // Draw (once, then cache) the procedurally-generated sprite sheet for
    // this agent's stable identity, and set its resting pose. Seed is always
    // taken from the canonical roster entry so the face never shifts when a
    // scene projection appears or disappears. Falls back to coloured initials
    // if <canvas> is unavailable.
    renderSprite(el, poseSource) {
      const sprite = el.querySelector('.tv-agent-sprite');
      if (!sprite) return;
      const agent = el._federationAgent || poseSource || {};
      const seed = spriteSeed(agent);
      if (sprite.dataset.seed !== seed) {
        sprite.dataset.seed = seed;
        const url = buildSpriteSheet(agent);
        if (url) {
          sprite.classList.remove('tv-agent-sprite--fallback');
          sprite.style.background = '';
          sprite.textContent = '';
          sprite.style.backgroundImage = `url(${url})`;
        } else {
          sprite.classList.add('tv-agent-sprite--fallback');
          sprite.style.background = spriteBodyColor(agent, seed);
          sprite.textContent = this.spriteInitials(agent);
        }
        sprite.setAttribute('aria-label', `${agent.name || agent.displayName || 'agent'} avatar`);
      }
      const pose = this.basePose(poseSource || agent);
      el.dataset.pose = pose;
      if (!el.classList.contains('tv-agent--walking')) this.setPose(sprite, pose);
    }

    setPose(sprite, pose) {
      if (!sprite) return;
      sprite.classList.remove('pose-idle', 'pose-walk', 'pose-react');
      sprite.classList.add(`pose-${pose}`);
    }

    // Resting sprite pose derived only from the agent's real operational
    // action / scene animation — never a fabricated state.
    basePose(a) {
      if (!a) return 'idle';
      const action = a.operationalAction || a.action;
      if (action === 'alerting') return 'react';
      if (action === 'pacing' || a.animation === 'walk') return 'walk';
      return 'idle';
    }

    spriteInitials(a) {
      const name = (a && (a.name || a.displayName)) || '';
      return name.replace(/[^A-Za-z ]/g, '').split(' ').filter(Boolean).map(w => w[0]).join('').slice(0, 2).toUpperCase() || '?';
    }

    // Persistent, collision-checked office-waypoint assignment. This must be
    // a stateful registry rather than a value recomputed from the current
    // agent set: fetchAgents/fetchScene/fetchEvents can run concurrently
    // (see setRoom()), so multiple updateDiorama() passes can interleave
    // with different agent-set snapshots — a call-time-relative index would
    // let two agents race onto the same desk. This is append-only and
    // sticky per agentId, so it can't drift once assigned.
    assignWaypoint(agentId) {
      if (this.waypointAssignments.has(agentId)) return this.waypointAssignments.get(agentId);
      const taken = new Set(this.waypointAssignments.values());
      const start = hashId(agentId) % OFFICE_WAYPOINTS.length;
      let idx = start;
      for (let i = 0; i < OFFICE_WAYPOINTS.length; i++) {
        const candidate = (start + i) % OFFICE_WAYPOINTS.length;
        if (!taken.has(candidate)) { idx = candidate; break; }
      }
      this.waypointAssignments.set(agentId, idx);
      return idx;
    }

    // Brief, purely decorative reaction (no position/state change) so the
    // diorama visibly responds the moment a real event lands for an agent.
    pulseAgent(agentId) {
      const el = this.dioramaEl?.querySelector(`[data-agent-id="${agentId}"]`);
      if (!el) return;
      el.classList.remove('tv-agent--pulse');
      // eslint-disable-next-line no-unused-expressions
      el.offsetWidth; // restart the animation if it's already mid-pulse
      el.classList.add('tv-agent--pulse');
      setTimeout(() => el.classList.remove('tv-agent--pulse'), 900);
    }

    // Real authoritative backend position wins when it exists (truthful,
    // never overridden). Otherwise the agent walks a small, fixed loop of
    // office waypoints — bounded, predetermined stops, picked pseudo-randomly
    // per agent from a stable hash — so the floor reads as staffed without
    // fabricating a location for a real agent.
    applyScenePosition(el, sceneAgent, hash, waypointIdx) {
      if (sceneAgent) {
        if (el._wanderTimer) { clearTimeout(el._wanderTimer); el._wanderTimer = null; }
        const destination = sceneAgent.destination || sceneAgent.position;
        this.placeAgent(el, destination.x, destination.y);
        el.dataset.sceneOrigin = sceneAgent.presentation?.origin || 'lifecycle';
        el.dataset.sceneAnimation = sceneAgent.animation || 'idle';
        el.dataset.sceneLabel = sceneAgent.presentation?.label || 'scene projection';
        el.title = `${el._federationAgent?.name || sceneAgent.displayName} · ${el.dataset.sceneLabel}`;
        return;
      }
      el.removeAttribute('data-scene-origin');
      el.removeAttribute('data-scene-animation');
      el.removeAttribute('data-scene-label');
      if (!el._wanderTimer) this.scheduleWalk(el, hash, waypointIdx);
    }

    placeAgent(el, x, y, { animate = true } = {}) {
      const prevX = parseFloat(el.style.getPropertyValue('--scene-x'));
      el.style.setProperty('--scene-x', `${x}%`);
      el.style.setProperty('--scene-y', `${y}%`);
      const sprite = el.querySelector('.tv-agent-sprite');
      if (!animate || !Number.isFinite(prevX)) {
        el.dataset.facing = 'right';
        if (sprite) { sprite.classList.remove('flip'); this.setPose(sprite, el.dataset.pose || 'idle'); }
        return;
      }
      const facing = x < prevX ? 'left' : 'right';
      el.dataset.facing = facing;
      if (!sprite) return;
      el.classList.add('tv-agent--walking');
      sprite.classList.toggle('flip', facing === 'left');
      this.setPose(sprite, 'walk');
      clearTimeout(el._walkArriveTimer);
      el._walkArriveTimer = setTimeout(() => {
        el.classList.remove('tv-agent--walking');
        this.setPose(sprite, el.dataset.pose || 'idle');
      }, 2450);
    }

    // Predetermined stop-to-stop loop. The home slot is a stable round-robin
    // assignment (spreads a small live roster across distinct desks); hash
    // only jitters timing so agents don't all move in lockstep.
    scheduleWalk(el, hash, waypointIdx) {
      const homeIdx = Number.isInteger(waypointIdx) ? waypointIdx : hash % OFFICE_WAYPOINTS.length;
      const home = OFFICE_WAYPOINTS[homeIdx];
      this.placeAgent(el, home.x, home.y, { animate: false });
      let idx = homeIdx;
      const tick = () => {
        idx = Math.random() < 0.4 ? homeIdx : (idx + 1) % OFFICE_WAYPOINTS.length;
        const point = OFFICE_WAYPOINTS[idx];
        this.placeAgent(el, point.x, point.y);
        el._wanderTimer = setTimeout(tick, 6500 + (hash % 4500) + Math.random() * 3000);
      };
      el._wanderTimer = setTimeout(tick, 3500 + (hash % 5000));
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
        }, 6800);
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

    showBubble(agentId, text, duration = 6500, options = {}) {
      if (this.activeBubbleOwner && this.activeBubbleOwner !== agentId) return false;
      const agentEl = this.dioramaEl?.querySelector(`[data-agent-id="${agentId}"]`);
      if (!agentEl) return false;
      
      const container = agentEl.querySelector('.bubble-container');
      if (!container) return false;
      
      // Clear existing bubble for this agent
      this.clearBubble(agentId);
      this.activeBubbleOwner = agentId;
      
      const bubble = document.createElement('div');
      bubble.style.cssText = `
        position: absolute; bottom: 142px; left: 50%; transform: translateX(-50%);
        background: #f5e6bd; color: #171718;
        padding: 8px 12px; border-radius: 2px;
        font-size: 12px; line-height: 1.35; white-space: normal;
        width: max-content; max-width: 220px; box-shadow: 0 8px 18px rgba(0,0,0,0.32);
        border: 2px solid #171718;
        z-index: 10; pointer-events: none;
        animation: tv-bubble-pop 0.3s ease-out;
      `;
      bubble.textContent = text;
      if (options.ambient) {
        const label = document.createElement('small');
        label.textContent = 'AMBIENT PRESENTATION · NO EVENT';
        label.style.cssText = 'display:block;margin-bottom:4px;color:#5a2b24;font:800 8px ui-monospace,monospace;letter-spacing:.04em;';
        bubble.prepend(label);
      }

      // Speech bubble tail
      const tail = document.createElement('div');
      tail.style.cssText = `
        position: absolute; top: 100%; left: 50%; transform: translateX(-50%);
        width: 0; height: 0;
        border-left: 8px solid transparent;
        border-right: 8px solid transparent;
        border-top: 8px solid #f5e6bd;
      `;
      bubble.appendChild(tail);
      
      container.appendChild(bubble);
      
      // Auto-remove after duration
      const timeout = setTimeout(() => {
        bubble.style.animation = 'tv-bubble-fade 0.3s ease-in forwards';
        setTimeout(() => bubble.remove(), 300);
        this.activeBubbles.delete(agentId);
        if (this.activeBubbleOwner === agentId) this.activeBubbleOwner = null;
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
        if (this.activeBubbleOwner === agentId) this.activeBubbleOwner = null;
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

    triggerScheduledPresentation() {
      const agents = Array.from(this.agents.values()).sort((left, right) => String(left.agentId).localeCompare(String(right.agentId)));
      if (!agents.length) return false;
      const agent = agents[this.presentationIndex % agents.length];
      const line = FEDERATION_REPERTOIRE[this.presentationIndex % FEDERATION_REPERTOIRE.length];
      this.presentationIndex += 1;
      return this.showBubble(agent.agentId, line, 6500, { ambient: true });
    }

    schedulePresentation() {
      if (this.presentationTimer) clearTimeout(this.presentationTimer);
      const delay = this.presentationDelayIndex % 2 === 0 ? 15 * 60 * 1000 : 5 * 60 * 1000;
      this.presentationTimer = setTimeout(() => {
        if (!this.isRunning) return;
        this.triggerScheduledPresentation();
        this.presentationDelayIndex += 1;
        this.schedulePresentation();
      }, delay);
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
        this.fetchScene();
        this.fetchEvents();
        this.pollTimer = setTimeout(poll, this.refreshInterval);
      };
      this.pollTimer = setTimeout(poll, this.refreshInterval);
      
      // Sitcom lines are a fixed 15m / 5m cadence through the normative seed
      // repertoire. Operational feed bubbles remain event-driven and queued.
      this.schedulePresentation();
    }

    stop() {
      this.isRunning = false;
      if (this.pollTimer) clearTimeout(this.pollTimer);
      if (this.speechTimer) clearTimeout(this.speechTimer);
      if (this.ambientTimer) clearTimeout(this.ambientTimer);
      if (this.presentationTimer) clearTimeout(this.presentationTimer);
      for (const [, bubble] of this.activeBubbles) clearTimeout(bubble.timeout);
      this.activeBubbles.clear();
      this.activeBubbleOwner = null;
      for (const el of this.dioramaEl?.querySelectorAll('[data-agent-id]') ?? []) {
        clearTimeout(el._wanderTimer);
        clearTimeout(el._walkArriveTimer);
      }
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
        return `<div style="margin: 4px 0; opacity: 0.8;"><span style="color:#8c8370;">${time}</span> <span style="color:#5ec5c2;">${project}</span><span style="color:#d96738;">${agent}</span><span style="color:#f4c842;">[${this.escapeHtml(type)}]</span> ${this.escapeHtml(msg)}</div>`;
      });

      this.feedEl.innerHTML = items.join('') || '<div style="color:#8c8370;">No events yet...</div>';
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
