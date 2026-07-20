# Crew Phases Reference
# Blueprint phase definitions for autonomous crew orchestration

## Phase Overview

| Phase | Order | Description | Required Agents | Checkpoint |
|-------|-------|-------------|-----------------|------------|
| planning | 1 | Define project scope, success criteria, agent assignments | lead, architecture | Yes |
| confirmation | 2 | Validate plan, confirm resources, align team | lead, validation | Yes |
| acting | 3 | Execute work per blueprint, parallel with phase gates | all_assigned | Yes |
| validation | 4 | Validate outputs against success criteria, run tests | validation, lead | Yes |
| completed | 5 | Finalize, archive, promote memory, close crew | lead | No |

## Phase Gate Rules

- No phase transition without all active agents claiming completion
- Completion claim requires reflective-loop habit pass
- Phase transition requires crew-phase-gate habit pass
- Each transition creates checkpoint with rollback capability
- Validation phase requires independent validation agent
- Completed phase requires memory promotion + knowledge index update

## Planning Phase Details

**Deliverables:**
- blueprint.json with phases, checkpoints, success measures
- Agent assignments per phase
- Risk assessment

**Gates:**
- lead_approves_blueprint
- architecture_validates_feasibility

## Confirmation Phase Details

**Deliverables:**
- Validated blueprint
- Resource allocation confirmed
- Initial checkpoint created

**Gates:**
- all_agents_ready
- resources_confirmed

## Acting Phase Details

**Deliverables:**
- Phase-specific outputs per agent
- Daily memory logs
- Progress reports

**Gates:**
- agent_claims_completion (triggers reflective-loop)
- peer_readiness (triggers crew-phase-gate)
- enforcer_validates (identity + tool + workspace)

## Validation Phase Details

**Deliverables:**
- Test results
- Validation report
- Compliance check

**Gates:**
- validation_passes
- lead_accepts

## Completed Phase Details

**Deliverables:**
- Final deliverables packaged
- Memory promoted to long-term
- Lessons learned documented
- Crew archive

**Gates:**
- all_memory_promoted
- archive_verified