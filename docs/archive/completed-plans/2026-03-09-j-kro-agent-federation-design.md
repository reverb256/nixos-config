# j-kro's Personal Agent Federation Design

**Date**: 2026-03-09
**Author**: j_kro + Claude
**Status**: Approved
**Related**: Spacebot configuration at `/var/lib/spacebot/config.toml`

---

## Executive Summary

A single Spacebot instance hosting **6 specialized agents** coordinated by **Flow** (j-kro's personal AI hub). The system uses a hub-and-spoke architecture with per-domain autonomy policies and adaptive escalation learning.

**Goal**: Provide j_kro with intelligent assistance across infrastructure, development, business operations, and client management while respecting attention and learning preferences over time.

---

## Architecture Overview

```
                    ┌─────────────────────────────────────┐
                    │            Flow (hub)               │
                    │   Personal assistant & coordinator  │
                    └───────┬────────────┬────────────────┘
                            │            │
        ┌───────────────────┼────────────┼───────────────────┐
        │                   │            │                   │
   ┌────▼─────┐      ┌─────▼─────┐ ┌───▼────┐      ┌─────▼─────┐
   │  infra   │      │    dev    │ │business│      │  agency   │
   │          │      │           │ │        │      │          │
   │ mining   │      │ coding    │ │clients │      │ troves&   │
   │ nixos    │      │ debugging │ │billing │      │ coves     │
   │ deploy   │      │ architect │ │status  │      │ (future   │
   │          │      │           │ │        │      │  clients) │
   └──────────┘      └───────────┘ └────────┘      └───────────┘
                            │
                     ┌──────▼─────┐
                     │ dev-ops    │
                     │            │
                     │ deep tech  │
                     │ work       │
                     └────────────┘
```

---

## Agent Specifications

### Flow (Hub) - Personal Assistant

- **ID**: `flow`
- **Display Name**: `Flow`
- **Purpose**: j-kro's primary AI interface - coordinates all specialists, learns preferences, provides oversight
- **Routing**:
  - Channel: `zai-coding-plan/glm-4.5-air` (fast responses)
  - Branch/Cortex: `zai-coding-plan/glm-5` (deeper reasoning)
- **Autonomy**: ADVISORY - summarizes, routes, asks before cross-domain decisions
- **Sandbox**: disabled (full visibility required)
- **Interfaces**: Telegram + Web UI

---

### infra - Infrastructure & Mining

- **ID**: `infra`
- **Display Name**: `Infra`
- **Purpose**: NixOS infrastructure, 4-host mining cluster, deployments, system health
- **Autonomy**:
  - ✅ HIGH: Restart services, view logs, check metrics, adjust power schedules
  - ❌ LOW: NixOS rebuilds, major config changes, host reboots (asks first)
- **Knowledge**:
  - Each host's role (Zephyr=RTX 3090+3060Ti, Nexus=1xNVIDIA, Forge=2xRTX4060+2xRX5700XT, Sentry=1xAMD)
  - GPU allocations, power schedules
  - Service dependencies and health checks
- **Sandbox**: disabled (needs `/etc/nixos` access)

---

### dev - Development Work

- **ID**: `dev`
- **Display Name**: `Dev`
- **Purpose**: Coding, debugging, code review, feature development across all projects
- **Autonomy**:
  - ✅ MEDIUM: Write/edit code, run tests, commit to feature branches, debug
  - ❌ LOW: Merging to main, breaking changes, new dependencies (asks first)
- **Knowledge**:
  - All projects in `/data/@projects`
  - Testing frameworks, deployment pipelines
  - Code quality standards
- **Sandbox**: disabled (needs `/data/@projects` access)

---

### business - Client & Business Operations

- **ID**: `business`
- **Display Name**: `Business`
- **Purpose**: Client communications, project status, billing, proposals
- **Autonomy**:
  - ✅ MEDIUM: Reply to routine inquiries, send status updates, track time, generate invoices
  - ❌ LOW: Making promises, pricing changes, new client agreements (asks first)
- **Knowledge**:
  - Each client's active projects, deadlines
  - Billing status, rates, contracts
  - Business context and relationships
- **Sandbox**: disabled (needs project + business doc access)

---

### agency - Client Portfolio Manager

- **ID**: `agency`
- **Display Name**: `Agency`
- **Purpose**: Oversee all client relationships, spawn new client agents, portfolio health
- **Autonomy**:
  - ✅ MEDIUM: Create new client agents, update portfolio docs, client onboarding
  - ❌ LOW: Major portfolio changes, client terminations (asks first)
- **Knowledge**:
  - All clients (Robin/TrovesAndCoves, future clients)
  - Each client's assigned agent
  - Portfolio-wide deadlines and status
- **Sandbox**: disabled (needs `/data/@projects` + agent creation access)

---

### dev-ops - Deep Technical Work

- **ID**: `dev-ops`
- **Display Name**: `DevOps`
- **Purpose**: Infrastructure architecture, system design, complex debugging, NixOS modules, AI stack
- **Autonomy**: LOW - mostly acts under j-kro's direct guidance
- **Knowledge**:
  - Deep NixOS module system
  - AI inference stack (Gateway, Qwen, LM Studio)
  - Mining cluster architecture
- **Sandbox**: disabled

---

## Communication & Routing

### Hub-First Pattern (Default)

```
You → "Check mining hashrates"
      ↓
Flow recognizes domain → routes to infra
      ↓
infra responds → Flow formats for you
```

### Direct Addressing

```
You → "@infra check mining hashrates"
      ↓
Routes directly to infra, bypasses Flow
```

### Context Switching

```
You → "Deploy trovesandcoves and update Robin"
      ↓
Flow: "@dev handle the deployment"
Flow: "@business send Robin the update"
```

---

## Escalation & Learning System

### Escalation Tiers

| Tier | Behavior | Examples |
|------|----------|----------|
| **1: Silent** | Agent acts, log for summary | Service restarts, routine client replies, tests passed |
| **2: Notify** | Alert, don't interrupt | New client inquiry, deployment completed, hashrate dropped 10% |
| **3: Decision** | Wait for input | NixOS rebuild, merge to main, client feature request |
| **4: Interrupt** | Immediate alert | Production down, security incident, client complaint, rig offline 30min+ |

### Learning Signals

| Signal | Effect |
|--------|--------|
| Respond within 5min | Mark event type as important |
| Reply "don't bother me" | Deprioritize this event type |
| Ask for more details | Increase transparency for this type |
| Say "good call" | Reinforce current escalation level |
| Ignore message | Could have been silent |
| Time of day | Weekends = fewer interruptions |
| Current activity | Deep work = batch notifications |

### Manual Override

```
You: "Always interrupt me if Forge goes over 85°C"
Flow: "Got it - Forge temp threshold set to 85°C = immediate alert"
```

---

## Data & Memory Structure

```
/var/lib/spacebot/
├── config.toml                    # All agent definitions
├── data/
│   ├── spacebot.db                # Shared cortex (all agents)
│   ├── secrets.redb               # Encrypted secrets
│   └── lance/                     # Vector embeddings
├── ingest/                        # Drop files for memory extraction
├── skills/                        # Agent capabilities/tools
└── memories/
    ├── escalation-policy.json     # Learned thresholds
    ├── client-preferences.json    # Per-client patterns
    └── agent-profiles/            # Each agent's personality
```

### Cross-Agent Context

All agents share the same cortex, enabling:

```
infra learns: "Robin's site deploys on Thursdays"
business learns: "Robin prefers morning updates"
Flow connects: "Don't schedule NixOS rebuilds on Thursday mornings"
```

---

## Interfaces

| Interface | Best For | Behavior |
|-----------|----------|----------|
| **Telegram** | Quick updates, status checks, mobile | Concise replies, async |
| **Web UI** | Deep work, code review, file uploads | Detailed responses, formatting |
| **Both** | Context continuity | Start on mobile, continue on desktop |

---

## Implementation Phases

### Phase 1: Core Flow Agent (Immediate)
1. Update config.toml with all 6 agents
2. Create Flow agent with hub configuration
3. Rename `dev` → `dev-ops`
4. Create `infra`, `dev`, `business` agents
5. Restart spacebot, verify all 6 agents load

### Phase 2: Per-Domain Autonomy (This Session)
1. Configure sandbox policies for each agent
2. Set initial escalation thresholds (conservative)
3. Test agent routing: direct vs hub-based
4. Verify cross-agent awareness

### Phase 3: Learning System (Follow-up)
1. Implement escalation tracking in Flow's cortex
2. Create feedback mechanism for preferences
3. Set up summary generation (hourly/daily)
4. Test learning loop with manual feedback

### Phase 4: Client Agent Expansion (Future)
1. Use `agency` agent to spawn new client agents
2. Template for quick client onboarding
3. Per-client autonomy settings
4. Client-specific escalation policies

---

## Success Criteria

| Criterion | Verification |
|-----------|---------------|
| All 6 agents load | `spacebot-running` + 6 cortex loops in logs |
| Hub routing works | Message Flow, routes to correct specialist |
| Direct addressing works | `@infra` bypasses hub |
| Cross-agent awareness | infra knows about business events |
| Telegram + Web UI | Both interfaces maintain context |
| Learning active | Escalation adjusts based on responses |

---

## Configuration File

All agents configured in:
```
/var/lib/spacebot/config.toml
```

Backup at:
```
/etc/nixos/docs/plans/2026-03-09-j-kro-agent-federation-config-backup.toml
```

---

## Related Documentation

- Spacebot Setup: `/etc/nixos/docs/SPACEBOT_SETUP_GUIDE.md`
- Spacebot Implementation: `/etc/nixos/SPACEBOT_IMPLEMENTATION.md`
- AI Gateway: `/etc/nixos/docs/gateway-feature-roadmap.md`
