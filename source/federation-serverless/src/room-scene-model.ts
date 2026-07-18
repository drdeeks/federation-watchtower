export type SceneAction = "working" | "pacing" | "watching" | "alerting" | "offline";
export type SceneOrigin = "operational" | "lifecycle" | "ambient";
export interface ScenePosition { x: number; y: number; zone: string; }
export interface SceneAgent {
  agentId: string; displayName: string; role: string; paletteKey: string; lifecycleState: string;
  operationalAction: SceneAction; position: ScenePosition; destination: ScenePosition;
  animation: "idle" | "walk" | "work" | "alert" | "exit";
  presentation: { origin: SceneOrigin; label: string; sourceEventId?: string; sourceEventType?: string };
  updatedAt: number;
}
export interface SceneEvent { sequence: number; eventId: string; agentId: string; origin: SceneOrigin; eventType: string; label: string; occurredAt: number; }
export interface RoomSceneSnapshot { roomId: string; sequence: number; generatedAt: number; agents: SceneAgent[]; events: SceneEvent[]; }
export interface SceneProjectionInput { roomId: string; agentId: string; displayName: string; role?: string; paletteKey?: string; lifecycleState: string; eventType: string; sourceEventId?: string; occurredAt?: number; }

const ZONES: Record<string, ScenePosition[]> = {
  entry: [{ x: 8, y: 82, zone: "entry" }, { x: 15, y: 82, zone: "entry" }],
  workbench: [{ x: 28, y: 61, zone: "workbench" }, { x: 39, y: 62, zone: "workbench" }, { x: 51, y: 61, zone: "workbench" }],
  console: [{ x: 66, y: 47, zone: "console" }, { x: 78, y: 49, zone: "console" }],
  observatory: [{ x: 86, y: 27, zone: "observatory" }, { x: 76, y: 27, zone: "observatory" }],
  incident: [{ x: 90, y: 73, zone: "incident" }, { x: 80, y: 73, zone: "incident" }],
  lounge: [{ x: 31, y: 32, zone: "lounge" }, { x: 43, y: 31, zone: "lounge" }],
  exit: [{ x: 7, y: 91, zone: "exit" }],
};

export function emptyScene(roomId: string): RoomSceneSnapshot { return { roomId, sequence: 0, generatedAt: Date.now(), agents: [], events: [] }; }
function hash(value: string): number { let result = 2166136261; for (let index = 0; index < value.length; index += 1) { result ^= value.charCodeAt(index); result = Math.imul(result, 16777619); } return result >>> 0; }
function placement(zone: string, seed: string, agents: SceneAgent[]): ScenePosition {
  const candidates = ZONES[zone] || ZONES.observatory; const start = hash(seed) % candidates.length;
  for (let offset = 0; offset < candidates.length; offset += 1) { const candidate = candidates[(start + offset) % candidates.length]; if (!agents.some(agent => agent.position.zone !== "exit" && Math.abs(agent.position.x - candidate.x) < 7 && Math.abs(agent.position.y - candidate.y) < 7)) return candidate; }
  return candidates[start];
}
function presentation(input: SceneProjectionInput, previous?: SceneAgent): Pick<SceneAgent, "lifecycleState" | "operationalAction" | "animation" | "presentation"> {
  const event = input.eventType.toLowerCase();
  if (input.lifecycleState === "offline" || event === "heartbeat.missed" || event === "agent.disconnected") return { lifecycleState: "offline", operationalAction: "offline", animation: "exit", presentation: { origin: "lifecycle", label: "lifecycle transition", sourceEventId: input.sourceEventId, sourceEventType: input.eventType } };
  if (event.includes("validation.failed") || event.includes("run.failed") || event.includes("incident") || event.includes("denied")) return { lifecycleState: input.lifecycleState, operationalAction: "alerting", animation: "alert", presentation: { origin: "operational", label: "operational event", sourceEventId: input.sourceEventId, sourceEventType: input.eventType } };
  if (event === "run.started" || event.includes("tool.executed") || event.includes("action.started")) return { lifecycleState: input.lifecycleState, operationalAction: "working", animation: "work", presentation: { origin: "operational", label: "operational event", sourceEventId: input.sourceEventId, sourceEventType: input.eventType } };
  if (event === "run.completed" || event.includes("heartbeat") || event === "agent.connected") return { lifecycleState: input.lifecycleState, operationalAction: previous?.operationalAction === "working" && event.includes("heartbeat") ? "working" : "watching", animation: "idle", presentation: { origin: "lifecycle", label: "lifecycle transition", sourceEventId: input.sourceEventId, sourceEventType: input.eventType } };
  return { lifecycleState: input.lifecycleState, operationalAction: previous?.operationalAction || "watching", animation: previous?.animation || "idle", presentation: { origin: "operational", label: "operational event", sourceEventId: input.sourceEventId, sourceEventType: input.eventType } };
}
function targetZone(action: SceneAction): string { return action === "working" ? "workbench" : action === "alerting" ? "incident" : action === "offline" ? "exit" : "observatory"; }
function record(scene: RoomSceneSnapshot, event: Omit<SceneEvent, "sequence">): void { scene.sequence += 1; scene.events.unshift({ ...event, sequence: scene.sequence }); scene.events.splice(80); scene.generatedAt = event.occurredAt; }
export function projectSceneEvent(scene: RoomSceneSnapshot, input: SceneProjectionInput): RoomSceneSnapshot {
  const occurredAt = input.occurredAt || Date.now(); const index = scene.agents.findIndex(agent => agent.agentId === input.agentId); const previous = index >= 0 ? scene.agents[index] : undefined; const nextPresentation = presentation(input, previous); const destination = placement(targetZone(nextPresentation.operationalAction), `${input.agentId}:${input.eventType}:${scene.sequence}`, scene.agents.filter(agent => agent.agentId !== input.agentId));
  const next: SceneAgent = { agentId: input.agentId, displayName: input.displayName, role: input.role || "agent", paletteKey: input.paletteKey || "operator", lifecycleState: nextPresentation.lifecycleState, operationalAction: nextPresentation.operationalAction, position: previous?.position || placement("entry", input.agentId, scene.agents), destination, animation: nextPresentation.animation, presentation: nextPresentation.presentation, updatedAt: occurredAt };
  if (index >= 0) scene.agents[index] = next; else scene.agents.push(next);
  record(scene, { eventId: input.sourceEventId || `scene-${input.agentId}-${occurredAt}`, agentId: input.agentId, origin: nextPresentation.presentation.origin, eventType: input.eventType, label: nextPresentation.presentation.label, occurredAt }); return scene;
}
export function projectAmbientBeat(scene: RoomSceneSnapshot, occurredAt = Date.now()): RoomSceneSnapshot | null {
  const candidates = scene.agents.filter(agent => agent.lifecycleState !== "offline" && agent.operationalAction !== "alerting"); if (candidates.length === 0) return null;
  const agent = candidates[hash(`${scene.roomId}:${scene.sequence}:${occurredAt}`) % candidates.length]; const action: SceneAction = hash(`${agent.agentId}:${scene.sequence}`) % 2 === 0 ? "pacing" : "watching";
  agent.position = agent.destination; agent.destination = placement(action === "pacing" ? "lounge" : "observatory", `${agent.agentId}:ambient:${scene.sequence}`, scene.agents.filter(item => item.agentId !== agent.agentId)); agent.animation = action === "pacing" ? "walk" : "idle"; agent.presentation = { origin: "ambient", label: "ambient choreography · no operational event" }; agent.updatedAt = occurredAt;
  record(scene, { eventId: `ambient-${scene.sequence + 1}-${agent.agentId}`, agentId: agent.agentId, origin: "ambient", eventType: "presentation.ambient", label: agent.presentation.label, occurredAt }); return scene;
}
