import { DurableObject } from "cloudflare:workers";
import type { WatchtowerEnv } from "./agent-registry";
import type { AgentRegistry } from "./agent-registry";
import type { ProjectGuardrail } from "./project-guardrail";

interface HeartbeatDeadline {
  projectId: string;
  agentId: string;
  deadlineAt: number;
  nonce: string;
}

export class AgentWatchdog extends DurableObject<WatchtowerEnv> {
  async recordHeartbeat(input: Omit<HeartbeatDeadline, "nonce">): Promise<void> {
    const heartbeat: HeartbeatDeadline = { ...input, nonce: crypto.randomUUID() };
    await this.ctx.storage.put("heartbeat", heartbeat);
    await this.ctx.storage.setAlarm(heartbeat.deadlineAt);
  }

  async disconnect(input: Pick<HeartbeatDeadline, "projectId" | "agentId">): Promise<void> {
    const current = await this.ctx.storage.get<HeartbeatDeadline>("heartbeat");
    if (current && (current.projectId !== input.projectId || current.agentId !== input.agentId)) return;
    await this.ctx.storage.delete("heartbeat");
    await this.ctx.storage.deleteAlarm();
  }

  async alarm(): Promise<void> {
    const heartbeat = await this.ctx.storage.get<HeartbeatDeadline>("heartbeat");
    if (!heartbeat) return;
    if (heartbeat.deadlineAt > Date.now()) {
      await this.ctx.storage.setAlarm(heartbeat.deadlineAt);
      return;
    }

    const guardrail = this.env.PROJECT_GUARDRAIL.get(
      this.env.PROJECT_GUARDRAIL.idFromName(heartbeat.projectId)
    ) as DurableObjectStub<ProjectGuardrail>;
    const result = await guardrail.raiseHeartbeatMissed({
      projectId: heartbeat.projectId,
      agentId: heartbeat.agentId,
      deadlineAt: heartbeat.deadlineAt,
    });
    const registry = this.env.AGENT_REGISTRY.get(
      this.env.AGENT_REGISTRY.idFromName(`${heartbeat.projectId}-registry`)
    ) as DurableObjectStub<AgentRegistry>;
    await registry.setAgentStatus(heartbeat.agentId, "offline");
    const now = Date.now();
    await this.env.DB.prepare("UPDATE federation_agents SET lifecycle_state = 'offline', disconnected_at = ?, updated_at = ? WHERE id = ?")
      .bind(now, now, `${heartbeat.projectId}:${heartbeat.agentId}`).run();
    await this.env.DB.prepare("INSERT OR IGNORE INTO federation_lifecycle_events (id, agent_id, event_type, idempotency_key, detail, occurred_at) VALUES (?, ?, 'heartbeat.missed', ?, ?, ?)")
      .bind(`life-${crypto.randomUUID()}`, `${heartbeat.projectId}:${heartbeat.agentId}`, `watchdog-${heartbeat.deadlineAt}`, JSON.stringify({ deadlineAt: heartbeat.deadlineAt }), now).run();
    if (result.alerts.length > 0) await this.env.WATCHTOWER_ALERTS.sendBatch(result.alerts.map(alert => ({ body: alert })));

    // Do not delete a newer heartbeat that arrived while the alert path awaited I/O.
    const current = await this.ctx.storage.get<HeartbeatDeadline>("heartbeat");
    if (current?.nonce === heartbeat.nonce) await this.ctx.storage.delete("heartbeat");
  }
}
