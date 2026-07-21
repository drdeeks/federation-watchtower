import { useEffect, useMemo, useRef, useState } from "react";

/**
 * OfficeStage — embeddable retro-cartoon office scene.
 * Agents wander between stations (desk, cooler, coffee, whiteboard, printer),
 * do activities (type, drink, scribble, panic), and react to tool-call events
 * with speech bubbles + lower-third captions.
 *
 * Feed events: window.__officeStage?.push({kind, agent?, text?})
 * or:          window.dispatchEvent(new CustomEvent('office:event', { detail }))
 * or:          Live API feed via gatewayUrl + projectId
 */

export type StageEvent = {
  agent?: string;
  kind:
    | "tool.call"
    | "tool.denied"
    | "tool.authorized"
    | "test.failed"
    | "test.passed"
    | "heartbeat"
    | "deploy"
    | "boiler"
    | "idle";
  text?: string;
};

/**
 * OfficeStageProps — configuration for the office scene.
 * @param gatewayUrl - Federation API gateway (default: https://fapi.drdeeks.xyz)
 * @param projectId - Project to watch (default: autopilot)
 * @param agents - Optional list of agents to render (uses default set if not provided)
 */
export interface OfficeStageProps {
  gatewayUrl?: string;
  projectId?: string;
  agents?: Array<{ agentId: string; name: string; paletteIndex?: number }>;
}

const QUIPS: Record<StageEvent["kind"], string[]> = {
  "tool.call": ["Calling a tool. Wish me luck.", "One tool, coming right up.", "This is fine. This is definitely fine."],
  "tool.denied": ["Watchtower said NO. Rude.", "Denied?? On my BIRTHDAY?", "Fine. I'll ask nicer."],
  "tool.authorized": ["Approved! We ride at dawn.", "The gods have smiled.", "Green light. GREEN LIGHT."],
  "test.failed": ["The test failed. I blame Kevin.", "It works on my machine!", "Rewriting the test until it passes."],
  "test.passed": ["All green. Suspicious.", "Passed on the first try — call the press.", "Putting this on the fridge."],
  heartbeat: ["*ba-dum* still alive.", "Heartbeat check. Yep.", "I made a checklist for my checklist checklist."],
  deploy: ["Shipping to prod. Godspeed.", "Deploy button pressed with vibes only.", "If you see smoke, that's normal."],
  boiler: ["THE BOILER ROOM IS ON FIRE — RUN!", "Who left the toaster on the server?", "Evacuate! Bring snacks!"],
  idle: ["Staring at the water cooler again.", "Do agents dream of electric ToDos?", "I'm just here for the coffee."],
};

const PALETTES = [
  { skin: "#f2c9a1", shirt: "#c94f4f", hair: "#3b2a20", pants: "#2b1608" },
  { skin: "#e0a878", shirt: "#3a6351", hair: "#1a1a1a", pants: "#1a1a1a" },
  { skin: "#f4d3b3", shirt: "#d69f2e", hair: "#6b3a1e", pants: "#2b1608" },
  { skin: "#c98c66", shirt: "#2c5f7f", hair: "#0f0f0f", pants: "#1a1a1a" },
  { skin: "#f0b98a", shirt: "#8e4585", hair: "#4a2e1a", pants: "#2b1608" },
  { skin: "#eabf9f", shirt: "#e07a3c", hair: "#2b1a10", pants: "#1a1a1a" },
];
const NAMES = ["Smitty", "Barb", "Dave", "Marge", "Carl", "Wanda"];

// Stations agents move between. Each has a "stand at" point and activity type.
type StationKind = "desk" | "cooler" | "coffee" | "whiteboard" | "printer" | "window";
type Station = { id: string; kind: StationKind; x: number; y: number; capacity: number; occupants: string[] };

const STATIONS: Station[] = [
  { id: "desk1", kind: "desk", x: 60, y: 175, capacity: 1, occupants: [] },
  { id: "desk2", kind: "desk", x: 150, y: 175, capacity: 1, occupants: [] },
  { id: "desk3", kind: "desk", x: 240, y: 175, capacity: 1, occupants: [] },
  { id: "desk4", kind: "desk", x: 330, y: 175, capacity: 1, occupants: [] },
  { id: "desk5", kind: "desk", x: 105, y: 225, capacity: 1, occupants: [] },
  { id: "desk6", kind: "desk", x: 285, y: 225, capacity: 1, occupants: [] },
  { id: "cooler", kind: "cooler", x: 24, y: 200, capacity: 2, occupants: [] },
  { id: "coffee", kind: "coffee", x: 378, y: 200, capacity: 2, occupants: [] },
  { id: "wb", kind: "whiteboard", x: 325, y: 145, capacity: 1, occupants: [] },
  { id: "printer", kind: "printer", x: 200, y: 145, capacity: 1, occupants: [] },
];

type Agent = {
  id: string;
  name: string;
  palette: (typeof PALETTES)[number];
  x: number;
  y: number;
  targetStation: string;
  path: Array<{ x: number; y: number }>;
  speed: number; // px per frame
  facing: 1 | -1;
  activity: "walking" | "typing" | "drinking" | "sipping" | "scribbling" | "printing" | "gazing" | "panic";
  activityUntil: number;
  bubble?: { text: string; kind: StageEvent["kind"]; until: number };
  panicUntil?: number;
  animOffset: number;
};

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

// Map real API event types to stage event kinds
function mapEventType(eventType: string): StageEvent["kind"] | undefined {
  const map: Record<string, StageEvent["kind"]> = {
    "run.started": "deploy",
    "run.completed": "test.passed",
    "run.failed": "test.failed",
    "validation.passed": "test.passed",
    "validation.failed": "test.failed",
    heartbeat: "heartbeat",
    "heartbeat.missed": "boiler",
    "tool.authorized": "tool.authorized",
    "tool.denied": "tool.denied",
    "policy.blocked": "tool.denied",
    "incident.opened": "boiler",
  };
  return map[eventType] || "idle";
}

function activityFor(kind: StationKind): Agent["activity"] {
  switch (kind) {
    case "desk": return "typing";
    case "cooler": return "drinking";
    case "coffee": return "sipping";
    case "whiteboard": return "scribbling";
    case "printer": return "printing";
    case "window": return "gazing";
  }
}

// Build a simple 2-waypoint path that routes through a "corridor" y so agents
// don't cut diagonally through desks. Corridor is around y=130.
function pathTo(from: {x:number;y:number}, to: {x:number;y:number}) {
  const corridorY = 135;
  return [
    { x: from.x, y: corridorY },
    { x: to.x, y: corridorY },
    { x: to.x, y: to.y },
  ];
}

export default function OfficeStage({ gatewayUrl = 'https://fapi.drdeeks.xyz', projectId = 'autopilot', agents: agentConfig }: OfficeStageProps = {}) {
  const stationsRef = useRef<Station[]>(STATIONS.map((s) => ({ ...s, occupants: [] })));
  const [agents, setAgents] = useState<Agent[]>(() => {
    const now = performance.now();
    return NAMES.map((name, i) => {
      const st = stationsRef.current[i % stationsRef.current.length];
      st.occupants.push(`a${i}`);
      return {
        id: `a${i}`,
        name,
        palette: PALETTES[i % PALETTES.length],
        x: st.x,
        y: st.y,
        targetStation: st.id,
        path: [],
        speed: 0.6 + Math.random() * 0.4,
        facing: (i % 2 === 0 ? 1 : -1) as 1 | -1,
        activity: activityFor(st.kind),
        activityUntil: now + 3000 + Math.random() * 4000,
        animOffset: Math.random() * 10,
      };
    });
  });
  const [captions, setCaptions] = useState<Array<{ id: number; text: string; kind: StageEvent["kind"]; who: string }>>([]);
  const captionId = useRef(0);
  const [tick, setTick] = useState(0);

  // main animation loop
  useEffect(() => {
    let raf = 0;
    let last = performance.now();
    const loop = (now: number) => {
      const dt = Math.min(50, now - last);
      last = now;
      setTick((t) => (t + 1) % 1_000_000);
      setAgents((prev) => stepAgents(prev, stationsRef.current, now, dt));
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);

  const pushEvent = useMemo(
    () => (ev: StageEvent) => {
      const now = performance.now();
      setAgents((prev) => {
        const target = ev.agent
          ? prev.find((a) => a.name.toLowerCase() === ev.agent!.toLowerCase() || a.id === ev.agent)
          : pick(prev);
        if (!target) return prev;
        const text = ev.text ?? pick(QUIPS[ev.kind]);
        return prev.map((a) => {
          if (a.id !== target.id) {
            // boiler makes EVERYONE panic and scatter
            if (ev.kind === "boiler") {
              return { ...a, panicUntil: now + 3500, activity: "panic", speed: 1.6 };
            }
            return a;
          }
          return {
            ...a,
            bubble: { text, kind: ev.kind, until: now + 4200 },
            panicUntil: ev.kind === "boiler" || ev.kind === "test.failed" ? now + 2000 : a.panicUntil,
            activity: ev.kind === "boiler" ? "panic" : a.activity,
            speed: ev.kind === "boiler" ? 1.8 : a.speed,
          };
        });
      });
      const id = ++captionId.current;
      const text = ev.text ?? pick(QUIPS[ev.kind]);
      setCaptions((c) => [...c.slice(-2), { id, text, kind: ev.kind, who: ev.agent ?? "" }]);
      setTimeout(() => setCaptions((c) => c.filter((x) => x.id !== id)), 4800);
    },
    [],
  );

  useEffect(() => {
    (window as unknown as { __officeStage?: { push: (e: StageEvent) => void } }).__officeStage = { push: pushEvent };
    const handler = (e: Event) => pushEvent((e as CustomEvent<StageEvent>).detail);
    window.addEventListener("office:event", handler as EventListener);

    // Fetch real feed events from API
    let pollTimer: ReturnType<typeof setInterval>;
    const fetchFeed = async () => {
      try {
        const res = await fetch(`${gatewayUrl}/api/projects/${projectId}/feed?limit=20`);
        if (!res.ok) return;
        const data = await res.json();
        const events = data.events || [];
        for (const evt of events) {
          const kind = mapEventType(evt.eventType);
          if (kind) {
            pushEvent({ kind, agent: evt.agentId, text: evt.message });
          }
        }
      } catch (e) {
        // Silently fail on fetch errors
      }
    };

    // Initial fetch + periodic polling
    fetchFeed();
    pollTimer = setInterval(fetchFeed, 8000);

    // Ambient simulation when no real events
    const kinds: StageEvent["kind"][] = [
      "tool.call", "tool.denied", "tool.authorized", "test.failed", "test.passed",
      "heartbeat", "deploy", "idle",
    ];
    let timeout: ReturnType<typeof setTimeout>;
    const schedule = () => {
      timeout = setTimeout(() => {
        const kind = Math.random() < 0.04 ? "boiler" : pick(kinds);
        pushEvent({ kind });
        schedule();
      }, 2200 + Math.random() * 2200);
    };
    schedule();

    return () => {
      window.removeEventListener("office:event", handler as EventListener);
      clearInterval(pollTimer);
      clearTimeout(timeout);
    };
  }, [pushEvent, gatewayUrl, projectId]);

  return (
    <div className="stage-wrap">
      <div className="stage">
        <svg viewBox="0 0 400 260" className="stage-svg" preserveAspectRatio="xMidYMid slice">
          <defs>
            <linearGradient id="wall" x1="0" x2="0" y1="0" y2="1">
              <stop offset="0" stopColor="#e9c98a" />
              <stop offset="1" stopColor="#c99a5b" />
            </linearGradient>
            <linearGradient id="floor" x1="0" x2="0" y1="0" y2="1">
              <stop offset="0" stopColor="#8a5432" />
              <stop offset="1" stopColor="#4a2b18" />
            </linearGradient>
            <pattern id="wallpaper" width="20" height="20" patternUnits="userSpaceOnUse">
              <rect width="20" height="20" fill="url(#wall)" />
              <circle cx="10" cy="10" r="1.2" fill="#8a5a2b" opacity="0.35" />
            </pattern>
            <pattern id="floorplanks" width="40" height="8" patternUnits="userSpaceOnUse">
              <rect width="40" height="8" fill="url(#floor)" />
              <line x1="0" y1="0" x2="40" y2="0" stroke="#2b1608" strokeWidth="0.6" />
              <line x1="20" y1="0" x2="20" y2="8" stroke="#2b1608" strokeWidth="0.4" opacity="0.6" />
            </pattern>
            <pattern id="scan" width="2" height="3" patternUnits="userSpaceOnUse">
              <rect width="2" height="1.4" fill="#000" />
            </pattern>
            <radialGradient id="vignette" cx="0.5" cy="0.5" r="0.75">
              <stop offset="0.6" stopColor="#000" stopOpacity="0" />
              <stop offset="1" stopColor="#000" stopOpacity="0.55" />
            </radialGradient>
          </defs>

          {/* walls + floor */}
          <rect x="0" y="0" width="400" height="120" fill="url(#wallpaper)" />
          <rect x="0" y="118" width="400" height="4" fill="#3a1f0e" />
          <rect x="0" y="122" width="400" height="138" fill="url(#floorplanks)" />

          {/* window */}
          <g transform="translate(40,26)">
            <rect width="70" height="52" fill="#7ec8e3" stroke="#3a1f0e" strokeWidth="3" />
            <line x1="35" y1="0" x2="35" y2="52" stroke="#3a1f0e" strokeWidth="2" />
            <line x1="0" y1="26" x2="70" y2="26" stroke="#3a1f0e" strokeWidth="2" />
            <circle cx="52" cy="14" r="6" fill="#fff2a8" />
          </g>
          {/* clock */}
          <g transform="translate(140,50)">
            <circle r="16" fill="#f4ecd8" stroke="#3a1f0e" strokeWidth="2.5" />
            <line x1="0" y1="0" x2="0" y2="-10" stroke="#3a1f0e" strokeWidth="2" />
            <line
              x1="0" y1="0"
              x2={Math.cos(tick * 0.02) * 6}
              y2={Math.sin(tick * 0.02) * 6}
              stroke="#c94f4f" strokeWidth="1.6"
            />
            <circle r="1.6" fill="#3a1f0e" />
          </g>
          {/* motivational poster */}
          <g transform="translate(180,26)">
            <rect width="70" height="52" fill="#fbfaf3" stroke="#3a1f0e" strokeWidth="3" />
            <text x="35" y="22" textAnchor="middle" fontFamily="Georgia, serif" fontSize="10" fontStyle="italic" fill="#c94f4f">
              HANG
            </text>
            <text x="35" y="34" textAnchor="middle" fontFamily="Georgia, serif" fontSize="10" fontStyle="italic" fill="#c94f4f">
              IN THERE
            </text>
            <text x="35" y="46" textAnchor="middle" fontFamily="'Courier New', monospace" fontSize="4" fill="#3a1f0e">
              (SINCE 1978)
            </text>
          </g>
          {/* whiteboard */}
          <g transform="translate(280,26)">
            <rect width="90" height="52" fill="#fbfaf3" stroke="#3a1f0e" strokeWidth="3" />
            <line x1="6" y1="12" x2="80" y2="12" stroke="#4b6db3" strokeWidth="1.4" />
            <line x1="6" y1="22" x2="70" y2="22" stroke="#c94f4f" strokeWidth="1.4" />
            <line x1="6" y1="32" x2="76" y2="32" stroke="#2f6b46" strokeWidth="1.4" />
            <line x1="6" y1="42" x2="60" y2="42" stroke="#3a1f0e" strokeWidth="1.4" />
          </g>

          {/* stations on floor */}
          {/* water cooler */}
          <g transform="translate(14,175)">
            <ellipse cx="10" cy="4" rx="10" ry="5" fill="#7ec8e3" stroke="#3a1f0e" strokeWidth="1.4" />
            <rect x="2" y="6" width="16" height="22" fill="#dcdcdc" stroke="#3a1f0e" strokeWidth="1.4" />
            <rect x="7" y="18" width="6" height="3" fill="#3a1f0e" />
          </g>
          {/* coffee machine */}
          <g transform="translate(366,178)">
            <rect x="0" y="0" width="20" height="24" fill="#3a1f0e" stroke="#111" strokeWidth="1" />
            <rect x="3" y="4" width="14" height="6" fill="#c94f4f" />
            <rect x="6" y="14" width="8" height="6" fill="#f4ecd8" stroke="#111" strokeWidth="0.6" />
            <circle cx="17" cy="6" r="1" fill="#7fd18a" />
          </g>
          {/* printer */}
          <g transform="translate(186,130)">
            <rect x="0" y="0" width="28" height="14" fill="#dcdcdc" stroke="#3a1f0e" strokeWidth="1.2" />
            <rect x="4" y="4" width="20" height="3" fill="#3a1f0e" />
            <rect x="6" y="10" width="16" height="6" fill="#fbfaf3" stroke="#3a1f0e" strokeWidth="0.6" />
          </g>
          {/* plant */}
          <g transform="translate(390,115)">
            <rect x="-8" y="4" width="16" height="12" fill="#8a4a2b" stroke="#3a1f0e" strokeWidth="1.2" />
            <path d="M0 4 C -12 -8, -8 -20, 0 -16 C 8 -20, 12 -8, 0 4 Z" fill="#2f6b46" stroke="#1e4530" strokeWidth="1" />
          </g>

          {/* desks */}
          {stationsRef.current
            .filter((s) => s.kind === "desk")
            .map((s) => (
              <g key={s.id} transform={`translate(${s.x - 22},${s.y + 6})`}>
                <rect width="44" height="4" fill="#5a3a20" stroke="#2b1608" strokeWidth="0.8" />
                <rect x="2" y="4" width="4" height="14" fill="#5a3a20" />
                <rect x="38" y="4" width="4" height="14" fill="#5a3a20" />
                <rect x="10" y="-14" width="24" height="16" fill="#2b2b2b" stroke="#111" strokeWidth="1" />
                <rect x="12" y="-12" width="20" height="12" fill="#7ec8e3" />
                <rect x="14" y="-10" width="10" height="1.5" fill="#fff" opacity="0.8" />
                <rect x="14" y="-7" width="14" height="1.5" fill="#fff" opacity="0.6" />
                <rect x="14" y="-4" width="8" height="1.5" fill="#fff" opacity="0.6" />
                <rect x="18" y="2" width="8" height="2" fill="#111" />
              </g>
            ))}

          {/* agents sorted by y for depth */}
          {[...agents]
            .sort((a, b) => a.y - b.y)
            .map((a) => {
              const walking = a.activity === "walking" || a.activity === "panic";
              const bob = walking ? Math.abs(Math.sin((tick + a.animOffset * 10) * 0.35)) * 1.6 : Math.sin((tick + a.animOffset * 10) * 0.08) * 0.6;
              return (
                <g key={a.id} transform={`translate(${a.x}, ${a.y - bob})`}>
                  <ellipse cx="0" cy="14" rx="9" ry="2.5" fill="#000" opacity="0.28" />
                  <g transform={`scale(${a.facing},1)`}>
                    <Character
                      palette={a.palette}
                      tick={tick + a.animOffset * 10}
                      activity={a.activity}
                      panic={!!a.panicUntil}
                    />
                  </g>
                  <text
                    x="0" y="26"
                    textAnchor="middle"
                    fontFamily="'Courier New', monospace"
                    fontSize="5.4"
                    fill="#f4ecd8"
                    stroke="#3a1f0e"
                    strokeWidth="0.4"
                    paintOrder="stroke"
                  >
                    {a.name.toUpperCase()}
                  </text>
                </g>
              );
            })}

          {/* speech bubbles on top */}
          {agents.map((a) =>
            a.bubble ? (
              <SpeechBubble key={`b-${a.id}`} x={a.x} y={a.y - 24} text={a.bubble.text} kind={a.bubble.kind} />
            ) : null,
          )}

          {/* CRT scanlines + vignette */}
          <rect x="0" y="0" width="400" height="260" fill="url(#scan)" opacity="0.14" pointerEvents="none" />
          <rect x="0" y="0" width="400" height="260" fill="url(#vignette)" pointerEvents="none" />
        </svg>

        <div className="chrome-top"><span className="rec-dot" /> LIVE · OFFICE CAM</div>
        <div className="chrome-tr">CH-04 · 4:20 PM</div>

        <div className="captions">
          {captions.map((c) => (
            <div key={c.id} className={`caption caption-${c.kind.split(".")[0]}`}>
              <span className="caption-tag">{c.kind.replace(".", " · ").toUpperCase()}</span>
              <span className="caption-text">{c.text}</span>
            </div>
          ))}
        </div>
      </div>

      <style>{`
        .stage-wrap { width:100%; display:flex; justify-content:center; padding:12px; box-sizing:border-box; background:#111; }
        .stage {
          position:relative; width:100%; max-width:760px; aspect-ratio: 400/260;
          border-radius:14px; overflow:hidden;
          box-shadow: 0 0 0 6px #2b1608, 0 0 0 10px #6b3a1e, 0 20px 40px rgba(0,0,0,0.6);
          background:#000; font-family:'Courier New', monospace;
        }
        .stage-svg { width:100%; height:100%; display:block; }
        .chrome-top {
          position:absolute; top:8px; left:10px; font-size:10px; letter-spacing:0.2em;
          color:#f4ecd8; background:rgba(0,0,0,0.55); padding:3px 8px; border-radius:3px;
          display:flex; align-items:center; gap:6px;
        }
        .chrome-tr {
          position:absolute; top:8px; right:10px; font-size:10px; letter-spacing:0.2em;
          color:#f4ecd8; background:rgba(0,0,0,0.55); padding:3px 8px; border-radius:3px;
        }
        .rec-dot { width:8px; height:8px; border-radius:50%; background:#ff3b3b; box-shadow:0 0 6px #ff3b3b; animation:rec 1.1s ease-in-out infinite; }
        @keyframes rec { 50% { opacity:0.25; } }
        .captions { position:absolute; left:10px; right:10px; bottom:10px; display:flex; flex-direction:column; gap:4px; }
        .caption { background:rgba(20,10,4,0.85); border-left:3px solid #e07a3c; color:#f4ecd8;
          padding:4px 8px; font-size:10px; line-height:1.25; border-radius:2px;
          animation:cap-in .25s ease-out; display:flex; gap:8px; align-items:baseline; }
        .caption-tag { color:#e07a3c; font-weight:bold; letter-spacing:0.1em; font-size:8px; white-space:nowrap; }
        .caption-text { flex:1; }
        .caption-test { border-left-color:#c94f4f; } .caption-test .caption-tag { color:#ff8a8a; }
        .caption-heartbeat { border-left-color:#7ec8e3; } .caption-heartbeat .caption-tag { color:#7ec8e3; }
        .caption-deploy { border-left-color:#7fd18a; } .caption-deploy .caption-tag { color:#7fd18a; }
        .caption-boiler { border-left-color:#ffdd55; background:rgba(120,20,0,0.9); }
        .caption-boiler .caption-tag { color:#ffdd55; }
        @keyframes cap-in { from { opacity:0; transform:translateY(6px); } }
      `}</style>
    </div>
  );
}

// --------------------------------------------------------------------------
// Simulation step: move agents along paths, pick new destinations when idle.
// --------------------------------------------------------------------------
function stepAgents(agents: Agent[], stations: Station[], now: number, dt: number): Agent[] {
  const stepPx = dt / 16; // ~1 unit at 60fps

  return agents.map((a) => {
    let next = { ...a };

    // panic override: keep them moving fast to a random station
    if (next.panicUntil && next.panicUntil < now) {
      next.panicUntil = undefined;
      next.speed = 0.6 + Math.random() * 0.4;
      if (next.activity === "panic") next.activity = "walking";
    }

    // if walking, advance along path
    if (next.activity === "walking" || next.activity === "panic") {
      if (next.path.length === 0) {
        // arrived: settle in target station
        const st = stations.find((s) => s.id === next.targetStation);
        if (st) {
          next.activity = activityFor(st.kind);
          next.activityUntil = now + 3500 + Math.random() * 5000;
        } else {
          next.activity = "gazing";
          next.activityUntil = now + 2000;
        }
      } else {
        const wp = next.path[0];
        const dx = wp.x - next.x;
        const dy = wp.y - next.y;
        const dist = Math.hypot(dx, dy);
        const move = next.speed * stepPx;
        if (dist <= move) {
          next.x = wp.x;
          next.y = wp.y;
          next.path = next.path.slice(1);
        } else {
          next.x += (dx / dist) * move;
          next.y += (dy / dist) * move;
          if (Math.abs(dx) > 0.1) next.facing = dx > 0 ? 1 : -1;
        }
      }
    } else {
      // doing an activity — when timer expires, pick a new station
      if (next.activityUntil < now) {
        // release current station
        const current = stations.find((s) => s.occupants.includes(next.id));
        if (current) current.occupants = current.occupants.filter((id) => id !== next.id);

        // pick a new random station with capacity
        const available = stations.filter((s) => s.occupants.length < s.capacity && s.id !== next.targetStation);
        const target = available.length > 0 ? pick(available) : pick(stations);
        target.occupants.push(next.id);
        next.targetStation = target.id;
        next.path = pathTo({ x: next.x, y: next.y }, { x: target.x, y: target.y });
        next.activity = "walking";
      }
    }

    // expire bubble
    if (next.bubble && next.bubble.until < now) next.bubble = undefined;

    return next;
  });
}

// --------------------------------------------------------------------------
// Character sprite (retro cartoon, vector, animated per activity)
// --------------------------------------------------------------------------
function Character({
  palette,
  tick,
  activity,
  panic,
}: {
  palette: (typeof PALETTES)[number];
  tick: number;
  activity: Agent["activity"];
  panic: boolean;
}) {
  const walking = activity === "walking" || activity === "panic";
  const walkPhase = Math.sin(tick * 0.35);
  const legSwing = walking ? walkPhase * 18 : 0;
  const armSwing = walking
    ? -walkPhase * 22
    : activity === "typing"
      ? Math.sin(tick * 0.5) * 6 - 30
      : activity === "scribbling"
        ? Math.sin(tick * 0.4) * 20 - 20
        : activity === "drinking" || activity === "sipping"
          ? -60
          : Math.sin(tick * 0.1) * 4;
  const headBob = walking ? Math.abs(walkPhase) * 0.6 : 0;
  const mouth = panic ? "panic" : activity === "sipping" || activity === "drinking" ? "drink" : activity === "typing" ? "focus" : "smile";

  return (
    <g>
      {/* legs */}
      <g transform={`translate(-3,6) rotate(${legSwing})`}>
        <rect x="-1.4" y="0" width="2.8" height="8" rx="1" fill={palette.pants} />
      </g>
      <g transform={`translate(3,6) rotate(${-legSwing})`}>
        <rect x="-1.4" y="0" width="2.8" height="8" rx="1" fill={palette.pants} />
      </g>
      {/* body */}
      <path
        d="M -7 -1 Q -8 -11 0 -12 Q 8 -11 7 -1 L 6 6 L -6 6 Z"
        fill={palette.shirt}
        stroke="#1a1a1a"
        strokeWidth="0.8"
      />
      {/* tie */}
      <polygon points="0,-10 -1.4,-6 0,-2 1.4,-6" fill="#3a1f0e" opacity="0.7" />
      {/* back arm */}
      <g transform={`translate(-5,-7) rotate(${-armSwing})`}>
        <rect x="-1.2" y="0" width="2.4" height="9" rx="1.2" fill={palette.shirt} stroke="#1a1a1a" strokeWidth="0.6" />
        <circle cx="0" cy="10" r="1.6" fill={palette.skin} stroke="#1a1a1a" strokeWidth="0.5" />
      </g>
      {/* front arm */}
      <g transform={`translate(5,-7) rotate(${armSwing})`}>
        <rect x="-1.2" y="0" width="2.4" height="9" rx="1.2" fill={palette.shirt} stroke="#1a1a1a" strokeWidth="0.6" />
        <circle cx="0" cy="10" r="1.6" fill={palette.skin} stroke="#1a1a1a" strokeWidth="0.5" />
        {/* prop in hand for cooler/coffee */}
        {(activity === "sipping" || activity === "drinking") && (
          <rect x="-1.4" y="6" width="2.8" height="3" fill={activity === "sipping" ? "#c94f4f" : "#7ec8e3"} stroke="#111" strokeWidth="0.4" />
        )}
      </g>
      {/* head */}
      <g transform={`translate(0, ${-15 - headBob})`}>
        <ellipse cx="0" cy="0" rx="5.2" ry="5.8" fill={palette.skin} stroke="#1a1a1a" strokeWidth="0.8" />
        <path
          d="M -5 -2 Q -5 -7 0 -7 Q 5 -7 5 -2 Q 3 -5 0 -5 Q -3 -5 -5 -2 Z"
          fill={palette.hair}
          stroke="#1a1a1a"
          strokeWidth="0.5"
        />
        <circle cx="-1.7" cy="0.4" r="0.6" fill="#1a1a1a" />
        <circle cx="1.7" cy="0.4" r="0.6" fill="#1a1a1a" />
        {mouth === "smile" && <path d="M -1.4 2.2 Q 0 3 1.4 2.2" fill="none" stroke="#1a1a1a" strokeWidth="0.7" strokeLinecap="round" />}
        {mouth === "focus" && <line x1="-1.2" y1="2.4" x2="1.2" y2="2.4" stroke="#1a1a1a" strokeWidth="0.7" strokeLinecap="round" />}
        {mouth === "drink" && <ellipse cx="0" cy="2.4" rx="0.8" ry="0.6" fill="#1a1a1a" />}
        {mouth === "panic" && <ellipse cx="0" cy="2.6" rx="1.2" ry="1.6" fill="#1a1a1a" />}
        {panic && (
          <>
            <text x="-6" y="-8" fontSize="6" fill="#ffdd55" fontFamily="Arial Black">!</text>
            <text x="5" y="-6" fontSize="6" fill="#ffdd55" fontFamily="Arial Black">!</text>
          </>
        )}
      </g>
      {/* activity fx */}
      {activity === "typing" && (
        <g opacity={0.6 + Math.abs(Math.sin(tick * 0.5)) * 0.4}>
          <circle cx="6" cy="-14" r="0.8" fill="#7ec8e3" />
          <circle cx="8" cy="-16" r="0.6" fill="#7ec8e3" />
        </g>
      )}
      {activity === "scribbling" && (
        <g opacity={0.7}>
          <line x1="6" y1="-4" x2="10" y2="-2" stroke="#c94f4f" strokeWidth="0.6" />
          <line x1="7" y1="-6" x2="10" y2="-5" stroke="#c94f4f" strokeWidth="0.6" />
        </g>
      )}
    </g>
  );
}

// --------------------------------------------------------------------------
function SpeechBubble({
  x, y, text, kind,
}: {
  x: number; y: number; text: string; kind: StageEvent["kind"];
}) {
  const alarm = kind === "boiler" || kind === "test.failed";
  const bg = alarm ? "#c94f4f" : "#fbfaf3";
  const fg = alarm ? "#fff8e0" : "#1a1a1a";
  const words = text.split(" ");
  const lines: string[] = [];
  let line = "";
  const maxChars = 22;
  for (const w of words) {
    if ((line + " " + w).trim().length > maxChars) {
      lines.push(line.trim());
      line = w;
    } else line += " " + w;
  }
  if (line.trim()) lines.push(line.trim());
  const w = Math.max(60, Math.min(140, Math.max(...lines.map((l) => l.length)) * 3.4 + 10));
  const h = lines.length * 7 + 8;
  const bx = Math.max(4, Math.min(400 - w - 4, x - w / 2));
  return (
    <g transform={`translate(${bx}, ${y - h})`} style={{ pointerEvents: "none" }}>
      <rect x="0" y="0" width={w} height={h} rx="4" ry="4" fill={bg} stroke="#1a1a1a" strokeWidth="1" />
      <polygon
        points={`${x - bx - 4},${h} ${x - bx + 4},${h} ${x - bx},${h + 5}`}
        fill={bg} stroke="#1a1a1a" strokeWidth="1"
      />
      {lines.map((l, i) => (
        <text
          key={i}
          x={w / 2}
          y={9 + i * 7}
          textAnchor="middle"
          fontFamily="'Courier New', monospace"
          fontSize="5.4"
          fontWeight={alarm ? "bold" : "normal"}
          fill={fg}
        >
          {l}
        </text>
      ))}
    </g>
  );
}
