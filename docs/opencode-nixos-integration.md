# OpenCode NixOS Integration Guide

## Overview

OpenCode is configured through NixOS with dynamic model synchronization from the AI Inference Gateway. The configuration automatically discovers available models and syncs them across all cluster nodes.

## Architecture

```
LM Studio (llmster) → AI Gateway → OpenCode Config → Cluster Nodes
                      (8080)       (~/.config/opencode/)   (zephyr, forge,
                                                              nexus, sentry)
```

## NixOS Configuration

### Module Location
- **Module**: `/etc/nixos/modules/development/opencode.nix`
- **Enabled via**: `profiles.role.aiInference = true` (on zephyr)

### Configuration Options

```nix
services.opencode = {
  enable = true;

  # Gateway connection
  gatewayUrl = "http://127.0.0.1:8080";

  # User configuration
  user = "j_kro";

  # Auto-sync settings
  autoSync = {
    enable = true;
    interval = "5min";  # Sync every 5 minutes
    onGatewayStart = true;  # Trigger when gateway starts
  };

  # Cluster sync
  clusterSync = {
    enable = true;
    nodes = ["forge" "nexus" "sentry"];
  };

  # Fallback providers
  zai = {
    enable = true;
    baseUrl = "https://api.z.ai/api/coding/paas/v4";
  };
};
```

## Systemd Services

### opencode-model-update.service
- **Purpose**: Fetches models from gateway and updates OpenCode config
- **Triggered by**:
  - Boot (30s delay)
  - AI gateway start
  - Manual: `systemctl start opencode-model-update.service`
  - Timer: Every 5 minutes (configurable)

### opencode-model-update.timer
- **Purpose**: Periodic model synchronization
- **Default**: Every 5 minutes
- **Control**: `systemctl {start,stop,status} opencode-model-update.timer`

## Convenience Commands

### opencode-sync
Triggers immediate model sync and shows logs:
```bash
opencode-sync
```

### opencode-status
Shows comprehensive status:
```bash
opencode-status
```

Output includes:
- Gateway health
- Available models from gateway
- OpenCode config status
- Last sync time
- Available commands

## API Keys (Agenix)

OpenCode uses API keys decrypted by agenix:

| Provider | Agenix Path | Environment Variable |
|----------|-------------|---------------------|
| LM Studio | `/run/agenix/lm-studio-api-key` | `LM_STUDIO_API_KEY` |
| ZAI | `/run/agenix/zai-api-key` | `ZAI_API_KEY` |
| Pollinations | `/run/agenix/pollinations-api-key` | `POLLINATIONS_API_KEY` |

### Environment Setup

Run the environment setup script to configure your shell:
```bash
/etc/nixos/scripts/setup-opencode-env.sh
```

This creates:
- `~/.bashrc.d/opencode-gateway.sh` (bash)
- `~/.config/fish/conf.d/opencode-gateway.fish` (fish)

## Configuration Files

### OpenCode Config
- **User**: `~/.config/opencode/opencode.json`
- **Root**: `/root/.config/opencode/opencode.json`

### oh-my-opencode Config
- **User**: `~/.config/opencode/oh-my-opencode.json`
- **Root**: `/root/.config/opencode/oh-my-opencode.json`

### Model Categorization

Models are automatically categorized by oh-my-opencode:

| Category | Description | Typical Models |
|----------|-------------|----------------|
| `ultrabrain` | Strategic thinking, complex problems | 35B A3B Opus, 27B Opus |
| `deep` | Complex algorithms, architecture | 18B Reap, 14B Coding |
| `unspecified-high` | High uncertainty, needs quality | 9B Opus |
| `unspecified-low` | Medium complexity, clear reqs | 9B, 14B, 18B |
| `writing` | Documentation, prose | Unredacted models |
| `quick` | Fast, lightweight tasks | 0.8B, 2B, 4B |
| `visual-engineering` | UI/UX, design (needs vision) | ZAI remote models |
| `artistry` | Creative work (needs vision) | ZAI remote models |

## Cluster Synchronization

Configuration is automatically synced to cluster nodes:
1. Generated on zephyr (primary node)
2. SCP'd to forge, nexus, sentry
3. Copied to root user via sudo

### Manual Sync
```bash
# Trigger immediate sync to all nodes
opencode-sync

# Check sync status on each node
ssh forge "opencode-status"
ssh nexus "opencode-status"
ssh sentry "opencode-status"
```

## Troubleshooting

### Gateway Not Responding
```bash
# Check gateway health
curl http://127.0.0.1:8080/health

# Check gateway models
curl http://127.0.0.1:8080/v1/models | jq

# Check gateway service
systemctl status ai-inference-gateway
journalctl -u ai-inference-gateway -n 50
```

### Missing Models in OpenCode
```bash
# Check model sync service
systemctl status opencode-model-update.service
journalctl -u opencode-model-update.service -n 50

# Manually trigger sync
opencode-sync

# Check for API key issues
ls -l /run/agenix/lm-studio-api-key
cat /run/agenix/lm-studio-api-key | head -c 20
```

### Cluster Sync Issues
```bash
# Check SSH connectivity
ssh forge "hostname"
ssh nexus "hostname"
ssh sentry "hostname"

# Check sudo permissions (for copying to root)
ssh forge "sudo -n whoami"
```

## Development

### Update Script
- **Location**: `/etc/nixos/scripts/update-opencode-models.py`
- **Purpose**: Queries gateway and generates OpenCode config

### Module Development
- **Module**: `/etc/nixos/modules/development/opencode.nix`
- **Rebuild**: `nixos-rebuild switch` or `just switch`
- **Test**: `nix build .#nixosConfigurations.zephyr.config.system.build.toplevel`

## Version History

| Date | Changes |
|------|---------|
| 2026-03-16 | Initial NixOS module with systemd service/timer for auto-sync |
| 2026-03-16 | Added cluster sync to forge, nexus, sentry |
| 2026-03-16 | Added convenience commands: opencode-sync, opencode-status |
| 2026-03-16 | Updated environment setup script for all API keys |

## References

- **oh-my-opencode**: https://github.com/code-yeongyu/oh-my-opencode
- **AI Gateway**: `/etc/nixos/modules/services/ai-inference/`
- **LM Studio Headless**: `/etc/nixos/modules/services/lm-studio-headless.nix`
