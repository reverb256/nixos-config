# Personal Clawdinators Architecture

**Status:** Draft
**Date:** 2026-02-17
**Based on:** NanoClaw + Clawdinators + Quadlets

---

## Overview

Personal Clawdinators is a local AI assistant platform running on your 4-node NixOS cluster. It provides:
- Multi-channel messaging (WhatsApp, Discord, Telegram)
- Agent spawning for parallel task execution
- Shared memory across nodes
- Integration with your projects (/data/@projects/)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    PERSONAL CLAWDINATORS                         │
│  Messaging Bridges · Agent Orchestrator · Skills · Shared Memory │
├─────────────────────────────────────────────────────────────────┤
│                    NIXOS + QUADLETS LAYER                        │
│  Declarative containers · Systemd services · Agenix secrets      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Node Distribution

| Node | IP | Role | Services |
|------|-----|------|----------|
| **zephyr** | 10.1.1.110 | Primary | Agent gateway, orchestrator, messaging |
| **nexus** | 10.1.1.120 | Storage | Shared memory (AI DB), container builds |
| **forge** | 10.1.1.130 | Compute | GPU tasks, heavy workloads |
| **sentry** | 10.1.1.140 | Monitor | Health checks, logging, alerts |

---

## Components

### 1. Messaging Layer

**Quadlet Containers:**
- `clawdinator-whatsapp.container` - Baileys-based WhatsApp bridge
- `clawdinator-discord.container` - Discord.js bridge
- `clawdinator-telegram.container` - Telegraf bridge

**Alternative:** Matrix Synapse as unified bridge (single container)

### 2. Agent Orchestrator

**Primary Service (zephyr):**
- Based on NanoClaw architecture
- Claude Agent SDK for LLM calls
- Zhipu AI via Anthropic-compatible endpoint
- Spawning capability for parallel tasks

**Container:**
- `clawdinator-agent.container` - Main agent runtime
- `clawdinator-spawner.container` - Sub-agent factory

### 3. Shared Memory

**Options (researching):**
1. **Qdrant** - Vector database for semantic memory
2. **LiteFS** - Distributed SQLite
3. **Dragonfly** - Redis-compatible in-memory DB

**Mount Point:** `/var/lib/clawdinator/memory`

### 4. Skills System

**Built-in Skills:**
- `web-design` - HTML/CSS/React/Tailwind assistance
- `nixos-config` - Nix module generation and editing
- `project-manager` - Manage /data/@projects/ workspace
- `personal-assistant` - Scheduling, reminders, research

**Structure:**
```
/var/lib/clawdinator/skills/
├── web-design/
│   └── SKILL.md
├── nixos-config/
│   └── SKILL.md
├── project-manager/
│   └── SKILL.md
└── personal-assistant/
    └── SKILL.md
```

---

## Quadlet Definitions

### clawdinator-agent.container

```ini
[Unit]
Description=Clawdinator Agent Gateway
After=network-online.target
Requires=clawdinator-memory.service

[Container]
ContainerName=clawdinator-agent
Image=localhost/clawdinator-agent:latest
Environment=ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
EnvironmentFile=/run/agenix/zhipu-api-key
Volume=/var/lib/clawdinator:/data:Z
Volume=/data/@projects:/workspace:ro
Volume=/etc/nixos:/nixos-config:ro
Network=clawdinator.network
PublishPort=18789:18789

[Service]
Restart=always
RestartSec=10s

[Install]
WantedBy=default.target
```

### clawdinator-memory.container (Qdrant)

```ini
[Unit]
Description=Clawdinator Vector Memory

[Container]
ContainerName=clawdinator-memory
Image=docker.io/qdrant/qdrant:latest
Volume=clawdinator-memory:/qdrant/storage:Z
PublishPort=6333:6333

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### clawdinator.network

```ini
[Network]
NetworkName=clawdinator
Driver=bridge
Subnets=10.89.0.0/24

[Install]
WantedBy=default.target
```

---

## NixOS Module Options

```nix
services.clawdinator = {
  enable = mkEnableOption "Personal Clawdinators AI assistant";
  
  role = mkOption {
    type = types.enum [ "primary" "storage" "compute" "monitor" ];
    default = "primary";
  };
  
  channels = {
    whatsapp.enable = mkEnableOption "WhatsApp bridge";
    discord.enable = mkEnableOption "Discord bridge";
    telegram.enable = mkEnableOption "Telegram bridge";
  };
  
  spawning = {
    enable = mkEnableOption "Agent spawning capability";
    maxAgents = mkOption {
      type = types.int;
      default = 5;
    };
  };
  
  memory = {
    backend = mkOption {
      type = types.enum [ "qdrant" "sqlite" "redis" ];
      default = "qdrant";
    };
    mountPoint = mkOption {
      type = types.path;
      default = "/var/lib/clawdinator/memory";
    };
  };
  
  llm = {
    provider = mkOption {
      type = types.enum [ "zhipu" "anthropic" "openai" ];
      default = "zhipu";
    };
    apiTokenFile = mkOption {
      type = types.path;
      default = "/run/agenix/zhipu-api-key";
    };
  };
};
```

---

## Secrets (Agenix)

Required secrets:
- `zhipu-api-key.age` - Zhipu AI API token (already exists)
- `clawdinator-discord-token.age` - Discord bot token
- `clawdinator-telegram-token.age` - Telegram bot token

---

## Integration Points

### /data/@projects/ Access

Agent has read-only access to workspace:
- `reverb256.github.io/` - Web development
- `hairathome/` - Client project
- `trovesandcoves/` - E-commerce
- `skills/` - Custom skills library

### /etc/nixos/ Access

Read-only access to NixOS configuration for:
- Generating new modules
- Modifying existing configs
- Deploying to other nodes

---

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Create clawdinator.nix module
- [ ] Define Quadlet containers
- [ ] Set up shared memory (Qdrant)
- [ ] Configure on zephyr

### Phase 2: Messaging
- [ ] WhatsApp bridge (Baileys)
- [ ] Discord bridge
- [ ] Telegram bridge
- [ ] Message routing to agent

### Phase 3: Spawning
- [ ] Agent orchestrator service
- [ ] Sub-agent container factory
- [ ] Task distribution

### Phase 4: Skills
- [ ] web-design skill
- [ ] nixos-config skill
- [ ] project-manager skill
- [ ] personal-assistant skill

### Phase 5: Multi-Node
- [ ] Deploy to nexus (storage)
- [ ] Deploy to forge (compute)
- [ ] Deploy to sentry (monitor)
- [ ] Shared memory replication

---

## File Structure

```
/etc/nixos/
├── modules/
│   ├── clawdinator.nix          # Main module
│   ├── clawdinator/
│   │   ├── agent.nix            # Agent service
│   │   ├── messaging.nix        # Messaging bridges
│   │   ├── memory.nix           # Shared memory
│   │   ├── spawning.nix         # Agent spawning
│   │   └── skills.nix           # Skills integration
│   └── default.nix              # Add clawdinator import
├── secrets/
│   ├── zhipu-api-key.age        # (exists)
│   ├── clawdinator-discord-token.age
│   └── clawdinator-telegram-token.age
└── hosts/
    └── zephyr/
        └── configuration.nix    # Enable services.clawdinator
```

---

## Commands

| Command | Description |
|---------|-------------|
| `clawdinator-auth` | Authenticate messaging channels |
| `clawdinator-logs` | View all clawdinator logs |
| `clawdinator-status` | Check service status |
| `clawdinator-restart` | Restart all services |
| `clawdinator-spawn` | Manually spawn a sub-agent |
| `clawdinator-memory` | Query shared memory |

---

## Next Steps

1. Research completes (AI databases, messaging, spawning)
2. Finalize technology choices
3. Implement clawdinator.nix module
4. Test on zephyr
5. Deploy to other nodes

---

**Research Tasks Running:**
- AI-native databases for shared memory
- Multi-channel messaging architecture
- Agent spawning frameworks
