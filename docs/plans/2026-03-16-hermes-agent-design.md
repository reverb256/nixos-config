# Hermes Agent Multi-Node Deployment Design

**Date:** 2026-03-16
**Author:** j_kro + Claude
**Status:** Design Approved

## Overview

Deploy Hermes Agent (self-improving AI agent by Nous Research) across all 4 NixOS cluster nodes with shared skills and memory via NFS storage. Hermes will integrate with the existing AI Inference Gateway for local model inference, eliminating need for external API keys.

## Requirements

### Functional Requirements
- [ ] Hermes Agent CLI available on all 4 nodes (zephyr, nexus, forge, sentry)
- [ ] Shared skills and memory via NFS-mounted storage
- [ ] Integration with existing AI Inference Gateway (localhost:8080/v1)
- [ ] Full terminal access without confirmation requirement
- [ ] Custom NixOS-specific skills auto-generated from existing documentation
- [ ] CLI-only operation (messaging gateway added later)

### Non-Functional Requirements
- [ ] Fully declarative NixOS packaging
- [ ] Reproducible builds via Nix
- [ ] All binaries in Nix store (no manual installer scripts)
- [ ] Easy updates via NixOS rebuild/deploy

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HERMES DATA FLOW                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  USER INPUT                                                                 │
│     │                                                                       │
│     ▼                                                                       │
│  ┌──────────────┐     OpenAI-compatible     ┌──────────────────────────┐   │
│  │   CLI/hermes │ ──────────────────────▶ │  AI Inference Gateway    │   │
│  │   (any node)  │      /v1/chat/completions    │  :8080                 │   │
│  └──────────────┘                          └──────────────────────────┘   │
│        │                                             │                   │
│        │                                             │                   │
│        ▼                                             ▼                   │
│  ┌──────────────┐                          ┌──────────────────────────┐   │
│  │ Terminal     │ ──────────────────────▶ │  LM Studio Backend      │   │
│  │ Execution    │      ssh://node          │  :1234                  │   │
│  └──────────────┘                          └──────────────────────────┘   │
│        │                                                               │   │
│        ▼                                                               │   │
│  ┌──────────────┐                                                          │
│  │  Skills &    │ ◀────────────────────────────────────────────────────────  │
│  │  Memory      │     NFS-mounted shared storage                              │
│  │  (Garage NFS) │     /var/lib/hermes                                          │
│  └──────────────┘                                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Node Deployment

| Node | IP          | Role                        |
|------|-------------|-----------------------------|
| Zephyr | 10.1.1.110  | Control plane, AI Gateway    |
| Nexus  | 10.1.1.120  | Storage, GPU compute        |
| Forge  | 10.1.1.130  | GPU compute, mining         |
| Sentry | 10.1.1.140  | Monitoring, logging         |

---

## Module Structure

```
modules/services/hermes-agent/
├── default.nix           # Main module with options & config
├── package.nix           # Python package definition
├── skills/               # Custom NixOS cluster skills
│   ├── nixos-deployment/
│   │   └── SKILL.md
│   ├── k8s-migration/
│   │   └── SKILL.md
│   ├── ai-gateway-config/
│   │   └── SKILL.md
│   └── cluster-management/
│       └── SKILL.md
└── flake-module.nix      # For flake integration
```

---

## Configuration Options

```nix
services.hermes-agent = {
  enable = true;

  # User account
  user = "hermes";

  # NFS shared storage
  sharedStorage = {
    enable = true;
    mountPoint = "/var/lib/hermes";
    nfsServer = "10.1.1.120";  # Nexus (Garage NFS)
    nfsPath = "/mnt/garage/hermes";
  };

  # AI Gateway integration
  aiGateway = {
    enable = true;
    url = "http://127.0.0.1:8080/v1";
  };

  # Terminal access
  terminal = {
    enable = true;
    requireApproval = false;  # Full access
    allowedCommands = null;   # Allow all
  };

  # Custom skills path
  customSkills = ./skills;
};
```

---

## Package Implementation

### Python Package (`package.nix`)

The Hermes agent will be packaged using `buildPythonApplication` with:

- **Source**: Fetched from GitHub (NousResearch/hermes-agent)
- **Python Version**: 3.11 (required by Hermes)
- **Dependencies**: All Python packages from `pyproject.toml`
- **Submodules**: mini-swe-agent, tinker-atropos
- **Post-install**:
  - Copy custom NixOS skills to `share/hermes-agent/skills/`
  - Wrapper script sets environment variables for AI Gateway URL

### Key Dependencies

```nix
propagatedBuildInputs = with python311Packages; [
  openai python-dotenv fire httpx rich tenacity pyyaml requests jinja2
  pydantic prompt_toolkit firecrawl-py fal-client edge-tts
  litellm typer platformdirs PyJWT
];
```

---

## Shared Storage

### NFS Mount Configuration

```nix
systemd.mounts = [{
  where = "/var/lib/hermes";
  what = "10.1.1.120:/mnt/garage/hermes";
  type = "nfs";
  options = "nofail,_netdev,hard,intr,timeo=600";
  wantedBy = [ "multi-user.target" ];
}];
```

### Directory Structure on NFS

```
/var/lib/hermes/
├── skills/              # Shared skills (custom + bundled sync)
├── memories/            # Persistent memory
├── sessions/            # Session logs
├── logs/                # Agent logs
├── cron/                # Scheduled jobs
└── config.yaml          # Shared configuration
```

### Fallback Behavior

If NFS is unavailable, Hermes falls back to local `~/.hermes` directory.

---

## AI Gateway Integration

### Configuration

Hermes configured to use local AI Gateway via environment variables:

```bash
OPENAI_API_KEY=not-needed
OPENAI_BASE_URL=http://127.0.0.1:8080/v1
```

### Model Configuration

```yaml
# ~/.hermes/config.yaml
model:
  default: "qwen3.5-35b-a3b"  # Or your preferred model
  provider: "main"
  base_url: "http://127.0.0.1:8080/v1"
```

### Benefit

- **No external API keys** for day-to-day operation
- **ZAI/Pollinations fallback** still available if configured
- **Local model inference** with privacy and speed

---

## Custom NixOS Skills

### Skills to Generate

1. **nixos-deployment**
   - Source: `justfile`, `AGENTS.md`
   - Content: `just test`, `just deploy`, `just switch` workflows
   - Safety rules: Always test before deploy

2. **k8s-migration**
   - Source: `ROADMAP.md`
   - Content: 9-week migration plan, phase checklists
   - Status tracking and validation

3. **ai-gateway-config**
   - Source: `modules/services/ai-inference/default.nix`
   - Content: Gateway configuration patterns, routing rules

4. **cluster-management**
   - Source: `AGENTS.md`, cluster documentation
   - Content: Multi-host deployment, Colmena commands

### Skill Format

```yaml
---
name: nixos-deployment
description: Deploy NixOS configurations across the 4-host cluster
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [NixOS, Colmena, Deployment, Cluster]
---

# NixOS Cluster Deployment

[Detailed instructions...]
```

---

## Terminal Access

### Configuration

- **Full access**: No approval required for commands
- **SSH capability**: Can execute commands on remote nodes
- **Working directory**: Defaults to `/etc/nixos` for cluster operations

### Security Considerations

- Hermes user is in `wheel` group for privilege escalation
- Terminal tool can run any command
- Recommended: Use `journalctl` to audit Hermes commands

---

## Testing Strategy

### Phase 1: Package Build
```bash
nix-build -A hermes-agent
nix-shell -p hermes-agent
```

### Phase 2: Single Node (Zephyr)
```bash
just deploy --on zephyr
hermes --help
hermes model
hermes "List files in /etc/nixos/modules"
```

### Phase 3: Multi-Node
```bash
just deploy
ssh zephyr "hermes --version"
ssh nexus "hermes --version"
ssh forge "hermes --version"
ssh sentry "hermes --version"
```

### Phase 4: Integration
```bash
hermes "What models are available?"
hermes "Run 'nixos-version' on all nodes"
hermes skills list
```

### Phase 5: Custom Skills
```bash
hermes skills view nixos-deployment
hermes "Deploy using nixos-deployment skill"
```

---

## Rollback Plan

If deployment fails:

```bash
# Revert changes
git revert HEAD

# Quick rebuild
just switch
```

---

## Success Criteria

- [ ] Hermes CLI available on all 4 nodes
- [ ] Can invoke local models via AI Gateway
- [ ] Skills and memory shared across nodes
- [ ] Terminal access works on all nodes
- [ ] Custom NixOS skills loaded and functional
- [ ] Can run multi-node cluster operations via Hermes

---

## Future Enhancements

1. **Messaging Gateway**: Add Telegram/Discord for mobile access
2. **K8s Migration**: Containerize Hermes for Kubernetes deployment
3. **MCP Integration**: Connect to existing MCP broker for extended tools
4. **More Skills**: Expand custom skill library based on usage patterns
5. **Voice Mode**: Enable TTS/STT for voice interactions

---

## References

- Hermes Agent: https://hermes-agent.nousresearch.com/
- GitHub: https://github.com/NousResearch/hermes-agent
- agentskills.io: https://www.agentskills.io/
- AI Gateway: `/etc/nixos/modules/services/ai-inference/`
