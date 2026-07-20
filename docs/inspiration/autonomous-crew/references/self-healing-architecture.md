# Self-Healing Architecture

## Self-Healing Loop (Every 5 Minutes)

```python
async def self_healing_loop(self):
    while self.running:
        # 1. HEARTBEAT: Check enforcer daemon health
        if not await self.enforcer.health_check():
            await self.restart_enforcer()
        
        # 2. CONSTITUTION: Verify hash unchanged
        if self.constitution_hash != hash_constitution(self.constitution_path):
            await self.alert_human("Constitution tampered!")
            await self.restore_constitution()
        
        # 3. CHAIN STATE: Verify chain integrity
        chain_state = await self.chain.check_integrity()
        if chain_state.has_gaps:
            await self.repair_chain_gaps(chain_state)
        
        # 4. MEMORY PIPELINE: Promote daily → weekly → long-term
        await self.memory_curator.promote_all()
        
        # 5. HABIT VIOLATIONS: Check for drift
        violations = await self.check_habit_violations()
        for v in violations:
            await self.remediate_habit(v)
        
        await asyncio.sleep(300)  # Every 5 minutes
```

## Integrity Checks

### Constitution Integrity
- Loaded at t=0, hash stored
- Verified before EVERY tool invocation
- Tampering → immediate alert + restore from git/backup

### Chain Integrity
- `.chain/<name>.json` tracks phase states
- Gaps = locked phase with incomplete prior
- Auto-repair: if prior complete but next locked → unlock

### Memory Pipeline Integrity
- Daily → Weekly promotion every 7 days
- Weekly → Long-term promotion every 30 days
- Knowledge index updated on long-term promotion
- Orphaned entries detected and logged

### Habit Violation Detection
- Logged to `.agent/logs/habit-violations.jsonl`
- Patterns: workspace hygiene drift, chain state bypass, skipped reflection
- Remediation: alert agent, log, auto-correct if possible

## Recovery Procedures

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Enforcer crash | Heartbeat timeout | Restart enforcer, restore socket |
| Constitution tampered | Hash mismatch | Alert human, restore from git |
| Chain gap | Locked phase with complete prior | Unlock next phase |
| Memory corruption | Promote fails | Rebuild index from daily |
| Habit drift | Violation pattern detected | Alert, remediate, log |

## Alerting

- Human alert: Constitution tamper, chain corruption
- Agent alert: Habit violations (logged, self-corrected)
- Metrics: All checks emit to `/metrics` endpoint