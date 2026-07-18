import { DurableObject } from "cloudflare:workers";
import type { WatchtowerEnv } from "./agent-registry";
import { emptyScene, projectAmbientBeat, projectSceneEvent, type RoomSceneSnapshot, type SceneProjectionInput } from "./room-scene-model";

/**
 * The authoritative presentation coordinator for one public Watchtower room.
 * It can add labeled ambient choreography; it cannot change operational truth.
 */
export class RoomScene extends DurableObject<WatchtowerEnv> {
  async project(input: SceneProjectionInput): Promise<RoomSceneSnapshot> {
    const scene = await this.load(input.roomId);
    projectSceneEvent(scene, input);
    await this.save(scene);
    await this.schedule(scene);
    return scene;
  }

  async snapshot(): Promise<RoomSceneSnapshot> {
    return this.load(this.ctx.id.name);
  }

  async alarm(): Promise<void> {
    const scene = await this.load(this.ctx.id.name);
    if (!projectAmbientBeat(scene)) return;
    await this.save(scene);
    await this.schedule(scene);
  }

  private async load(roomId: string): Promise<RoomSceneSnapshot> {
    return (await this.ctx.storage.get<RoomSceneSnapshot>("room-scene")) || emptyScene(roomId);
  }

  private async save(scene: RoomSceneSnapshot): Promise<void> {
    await this.ctx.storage.put("room-scene", scene);
  }

  private async schedule(scene: RoomSceneSnapshot): Promise<void> {
    const active = scene.agents.some(agent => agent.lifecycleState !== "offline");
    if (!active) { await this.ctx.storage.deleteAlarm(); return; }
    const jitter = hash(`${scene.roomId}:${scene.sequence}`) % 30_000;
    await this.ctx.storage.setAlarm(Date.now() + 45_000 + jitter);
  }
}

function hash(value: string): number {
  let result = 2166136261;
  for (let index = 0; index < value.length; index += 1) { result ^= value.charCodeAt(index); result = Math.imul(result, 16777619); }
  return result >>> 0;
}

export type { RoomSceneSnapshot, SceneProjectionInput } from "./room-scene-model";
