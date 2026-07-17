# NixOS Cluster Skills

Custom skills for managing the NixOS multi-host cluster.

## Installed Skills

### Infrastructure & Deployment

| Skill | Description |
|-------|-------------|
| `nixos-deploy` | Multi-host Colmena deployment across zephyr, nexus, forge, sentry |
| `nixos-developer` | NixOS development patterns and best practices |
| `add-service-mcp` | Create systemd service modules |
| `nix-rebuild-mcp` | Safe nixos-rebuild with mining pause |

### Hardware & Mining

| Skill | Description |
|-------|-------------|
| `ai-gateway-manager` | Manage AI inference gateway and LM Studio |
| `lm-studio-manager` | LM Studio model management |
| `hardware-control` | GPU/CPU control for mining and AI workloads |
| `container-native` | Unified Docker/Podman management |

### Business Operations (NEW)

| Skill | Description |
|-------|-------------|
| `cost-optimizer` | Mining profitability tracking vs. power costs with auto-shutdown |
| `sla-tracker` | Cluster uptime monitoring and SLA compliance tracking |
| `capacity-planner` | GPU/CPU capacity forecasting for AI vs. mining workloads |

### Secrets Management

| Skill | Description |
|-------|-------------|
| `agenix-secrets` | Multi-host encrypted secrets management with Age |

## Using Skills

Skills are invoked automatically based on context. The description field in `SKILL.md` determines when a skill triggers.

### Example: Cost Optimizer

```
User: "Is my mining profitable? I have 4 RTX 3090s and electricity is $0.15/kWh"
→ cost-optimizer skill triggers
→ Calculates power costs and break-even analysis
```

### Example: SLA Tracker

```
User: "Check the health of all hosts in my cluster"
→ sla-tracker skill triggers
→ Runs connectivity checks and service status
```

### Example: Capacity Planner

```
User: "I have 8 GPUs and expect 20 concurrent AI users. How should I allocate?"
→ capacity-planner skill triggers
→ Calculates GPU allocation between AI and mining
```

## Cluster Hosts

| Host | Role | GPUs |
|------|------|------|
| zephyr | Workstation + AI + Gaming | Multi-GPU NVIDIA |
| nexus | Gaming + VR + Mining + AI | Multi-GPU NVIDIA |
| forge | Mining + AI | Multi-GPU NVIDIA/AMD |
| sentry | Mining | AMD GPU |

## Development

To create a new skill, use the `skill-creator` skill:

```bash
npx skills create my-new-skill
```

## Adding New Skills to Git

After creating a new skill:
```bash
git add skills/my-new-skill/
git commit -m "feat(skills): add my-new-skill"
```
