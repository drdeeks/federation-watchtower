---
name: hackathon-manager
description: Manages hackathon participation, project organization, and submission workflows.
tags: []
related_skills: []
---

# Hackathon Manager

> Manages hackathon participation, project organization, and submission workflows.

## Overview

This skill helps manage hackathon participation including project organization, submission workflows, and tracking multiple project ideas across different tracks.

## Core Functions

### Project Organization
- Create project directories for hackathon ideas
- Track project status and progress
- Manage multiple project concepts
- Link projects to specific bounties/tracks

### Submission Management
- Prepare submission metadata
- Track submission deadlines
- Manage team coordination
- Handle on-chain identity integration

### Resource Management
- Track bounties and prize pools
- Map projects to relevant tracks
- Monitor competition landscape
- Manage credentials and API keys

## Key Commands

```bash
# Create project directory
mkdir -p "/home/ubuntu/.openclaw/workspace-titan/hackathon/[project-name]"

# Track project status
# (managed through memory files and project directories)

# Prepare submission
# (handled through submission workflows)
```

## Data Structure

```
hackathon/
├── [project-name]/
│   ├── README.md
│   ├── submission.md
│   ├── credentials.json
│   └── progress.md
├── bounties.json
└── projects.json
```

## Integration

- Uses OpenClaw workspace for file operations
- Integrates with hackathon APIs (Devfolio, etc.)
- Manages ERC-8004 identity through stored credentials
- Tracks multiple bounties and prize pools

## Security

- Credentials stored in `.synth-creds.json` with restricted permissions
- API keys never shared publicly
- Submission data managed through secure workflows
- On-chain identity handled through ERC-8004

## Usage

1. Install skill: `openclaw skill add /path/to/skill`
2. Create project directories: `mkdir -p hackathon/[project-name]`
3. Track progress through memory files
4. Prepare submissions using stored credentials
5. Monitor bounties and prize pools
6. Use on-chain identity for verification

## References

- `references/qwen-cloud-hackathon-2026.md` — Qwen Cloud Global AI Hackathon 2026 details: 5 tracks, submission requirements, prize structure.
- `references/dashscope-provider-pattern.md` — Reusable DashScope provider code with mock/real swap pattern.
- `references/qwen-model-selection.md` — Model tier guide and role-to-model mapping for all 5 tracks.

## Sequential Project Execution (User Preference)

When running multiple hackathon projects, execute ONE project at a time via kanban:
- Queue all projects as kanban tasks with priority ordering
- Complete one project fully before starting the next
- Each project task body includes: track, requirements, model mapping, queue position
- Use `status='ready'` for the current project, keep others as separate tasks
- After completing a project, mark it `done` and promote the next

Kanban task template:
```
id: t_<project>_001
title: <project>: Full hackathon build — Qwen-powered <Name> (<Track>)
assignee: <project>-orchestrator
status: ready (current) | pending (queued)
body: TRACK, DEADLINE, QUEUE POSITION, REQUIREMENTS, MODEL MAPPING, WHAT TO BUILD
workspace_kind: scratch  ← MUST be 'scratch', NOT 'project' (dispatcher rejects 'project')
workspace_path: /home/ubuntu/.hermes/kanban/workspaces/t_<project>_001
```

## Shared Infrastructure Pattern

Build reusable components once, copy/adapt across projects:
- **DashScopeProvider**: OpenAI-compatible wrapper for DashScope API. Reuse across all Qwen projects.
- **MockDashScopeProvider**: Returns realistic responses for demo without valid API key. Swap path: `new DashScopeProvider()` instead of `new MockDashScopeProvider()`.
- **Provider injection**: Accept optional `provider` param in constructors (not just `providerConfig`). Enables mock injection for testing.
- **Model mapping JSON**: Single `hackathon-models.json` mapping roles to Qwen models. Reference from all projects.

Key pattern — constructor accepts both config and instance:
```js
constructor({ providerConfig = {}, provider = null }) {
  this.#provider = provider || new DashScopeProvider(providerConfig);
}
```

## Demo Structure

Each project demo should follow this pattern:
1. **Setup**: Create registries, register connectors, create provider (mock or real)
2. **Scenarios**: 3 distinct end-to-end scenarios showing the agent's capability
3. **Analysis**: Adversarial/quality analysis of each scenario's output
4. **Summary**: Stats (API calls, health score, models used)

Mock provider matching: order patterns from most specific to least specific. Check for domain-specific keywords BEFORE general ones to avoid false matches.

## Qwen Model-to-Role Mapping

Map models to agent roles based on task characteristics:
- **Heavy reasoning** (orchestrator, planning): `qwen3-235b-a22b-thinking-2507`
- **Code generation**: `qwen3-coder-plus` or `qwen3-coder-flash-2025-07-28`
- **Flagship reasoning** (analysis, complex decisions): `qwen3-max-preview`
- **Balanced general** (execution, approval): `qwen-plus-latest`
- **Adversarial analysis** (failure detection): `qwen3-235b-a22b`
- **Structured data** (graph operations): `qwen3-30b-a3b-instruct`
- **Vision-language** (image analysis, storyboarding): `qwen-vl-max-latest`
- **Fast coding** (UI, frontend): `qwen3-coder-flash-2025-07-28`

Store mapping in `hackathon-models.json` at workspace root.

## Best Practices

- Keep credentials secure and permissions restricted
- Track project progress systematically via kanban
- Map projects to relevant bounties early
- Prepare submissions well before deadlines
- Use on-chain identity for verification
- For Qwen Cloud Hackathon: Must use Qwen models on Qwen Cloud; public repo required; demo video 3-5 min; map each project to ≥1 track
- Build shared infra (providers, mocks) once, reuse across projects
- One project at a time — complete before starting next
- Each project needs: README, demo.js, working mock, model mapping

## Quality Standard: Production, Not Demo

**User correction:** "I fucking hate that hackathon especially with me cause that's not how I work a Hackathon does not mean let's get a demo out I do your best to make it robust make an extra extravagant and functional has to be fully functional I try to finish these products not just give a demo half asssed."

Hackathon submissions must be FULLY FUNCTIONAL applications, not demo fluff:
- Every function must actually work, not just return mock data
- Error handling must be enterprise-grade (structured errors, retry, graceful degradation)
- The application must be deployable and runnable on the target platform
- Code quality matters — clean, modular, well-documented
- Tests should exist and pass
- README must explain architecture, setup, and how to run

The demo.js is a showcase of the working application, NOT a replacement for building the real thing.

## Delegation: Use Kanban, Don't Hand-Code

When kanban profiles exist for a project, DISPATCH IMMEDIATELY via `hermes kanban dispatch`. The agents are the workforce — you are the orchestrator. Stay available to the user while agents work in the background.

**User correction:** "why aren't you letting the agents do all this why are you doing it... there's completely separate profiles created for these fuckers. you should be able to test them with by using /autonomous-crew skill and let them run in the background so you're here with me"

## DashScope API Endpoint

The correct DashScope API base URL for the Qwen Cloud Hackathon:
```
https://dashscope-intl.aliyuncs.com/compatible-mode/v1
```
NOT `https://dashscope.aliyuncs.com/compatible-mode/v1` (that's the Chinese endpoint, returns 401 for international keys).