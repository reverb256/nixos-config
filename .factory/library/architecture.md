# Architecture

How the NixOS cluster is organized — components, relationships, and data flows.

## What belongs here
System architecture at a high level. Not implementation details.

---

## Cluster Overview

4-host NixOS cluster managed via flakes + Colmena deployment.

| Host | IP | Role | GPUs |
|------|-----|------|------|
| Zephyr | 10.1.1.110 | Control plane, AI workstation, gaming | 2x NVIDIA (RTX 3090, 3060 Ti) |
| Nexus | 10.1.1.120 | Storage, GPU compute | 1x NVIDIA (RTX 3060 Ti) |
| Forge | 10.1.1.130 | Multi-GPU mining, AI | 2x NVIDIA (RTX 4060) + 2x AMD (RX 5700 XT) |
| Sentry | 10.1.1.140 | Monitoring, logging | 1x AMD (RX 5600 XT) |

## Configuration Architecture

```
/etc/nixos/
├── flake.nix              # Defines hosts, commonModules
├── colmena.nix            # Multi-host deployment (separate commonModules — MUST stay in sync)
├── modules/
│   ├── default.nix        # Imports all shared modules
│   ├── common-host-defaults.nix  # Shared defaults for all hosts (mkDefault)
│   ├── profiles/          # Hardware/role/network profiles
│   ├── system/            # Core system modules (SSH, users, etc.)
│   ├── services/          # Background services (K8s, monitoring, etc.)
│   ├── hardware/          # GPU, monitoring, RGB control
│   └── ...
├── hosts/<hostname>/      # Per-host overrides (import shared modules + add host-specific config)
└── kubernetes-manifests/  # K8s YAML files (not Nix-managed, applied via kubectl)
```

## Key Relationships

- `flake.nix` and `colmena.nix` both define `commonModules` independently — they MUST stay in sync
- `modules/default.nix` imports all shared modules — hosts don't import individual modules
- `common-host-defaults.nix` provides mkDefault values that hosts can override
- Host configs (`hosts/<name>/configuration.nix`) override shared defaults with host-specific values
- NFS architecture: Zephyr is source of truth, remote hosts mount `/run/nixos-shared`

## Deployment Flow

1. Edit configs on Zephyr (source of truth)
2. `nix flake check` validates syntax
3. `nixos-rebuild build` builds local config
4. `colmena build` builds remote configs (via NFS mount)
5. `just deploy` activates on all hosts

## Key Invariants

- `lib.mkDefault` / `lib.mkOptionDefault` for shared defaults (NEVER direct assignment)
- No plaintext secrets in git (agenix for NixOS, K8s Secrets for manifests)
- All K8s workloads default to Nexus (Zephyr has OOM risk)
