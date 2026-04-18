# NixOS Services - Agent Context

**Parent:** `../../AGENTS.md` | **Domain:** Background daemons & services (73 .nix files)

## Overview
NixOS service modules for cluster infrastructure. Each module follows `services.<name>` namespace pattern.

## Structure
```
services/
├── monitoring/         # Prometheus/Grafana stack (13 files)
│   └── dashboards/     # Grafana dashboards (7 files)
├── js/                 # JavaScript runtime services
├── kubernetes/         # K8s-related services
├── opencode-sync/      # Config sync
└── *.nix               # Individual services (49 top-level .nix files)
```

## Where To Look

| Task | Location |
|------|----------|
| Add GPU exporter | `gpu-exporters.nix` |
| Set up storage | `nfs-server.nix`, `nfs-client.nix`, `garage.nix` |
| K8s cluster | `k3s-cluster.nix` |
| Config sync | `nixos-share.nix` (NFS server/client) |
| HA networking | `keepalived-vip.nix`, `haproxy-lb.nix` |
| AI inference | `llamafile.nix`, `lm-studio.nix`, `whisper-dictation.nix` |
| Add new daemon | Create `my-service.nix`, add to `../../default.nix` imports |
| Monitoring dashboards | `host-dashboard.nix`, `monitoring/dashboards/` |

## Key Services (49 top-level modules)

| Category | Services |
|----------|----------|
| **Infrastructure** | `k3s-cluster.nix`, `keepalived-vip.nix`, `nixos-share.nix`, `cluster-ca.nix` |
| **Networking** | `haproxy-ingress.nix`, `haproxy-lb.nix`, `cloudflared.nix`, `unbound-common.nix` |
| **Storage** | `nfs-server.nix`, `nfs-client.nix`, `garage.nix`, `backup-to-garage.nix`, `rclone.nix` |
| **GPU/AI** | `gpu-exporters.nix`, `llamafile.nix`, `lm-studio.nix`, `lm-studio-headless.nix`, `whisper-dictation.nix`, `qwen3-tts-preload.nix` |
| **Monitoring** | `cluster-monitoring.nix`, `host-dashboard.nix`, `health-checks.nix`, `crash-watchdog.nix`, `self-healing-alerts.nix` |
| **Security** | `container-scanning.nix`, `supply-chain-cooldowns.nix`, `auto-secrets.nix` |
| **Containers** | `podman.nix`, `podman-support.nix`, `podman-auto-update.nix` |
| **App Services** | `nextcloud.nix`, `n8n.nix`, `vaultwarden.nix`, `syncthing.nix`, `garnix.nix` |
| **Agent/Dev** | `hermes-cli.nix`, `hermes-dashboard.nix`, `claude-code-router.nix`, `mcp-servers.nix`, `mcp-server-registry.nix` |
| **Gaming/Mining** | `gaming-mining-coordinator.nix`, `tplink-switches.nix` |
| **Auto-update** | `auto-update.nix`, `claude-auto-update.nix`, `podman-auto-update.nix` |

## Anti-Patterns (THIS DIRECTORY)

| Pattern | Why | Fix |
|---------|-----|-----|
| `allowedTCPPorts = [22 80]` | Breaks SSH on other hosts | Use `lib.mkOptionDefault` |
| `ExecStart = "${pkgs.bash}/bin/bash -c '...'"` | Hard to read, fragile | Use `writeShellScript` |
| `Path = "${pkgs.bash}/bin:..."` | Manual concat | Use `lib.makeBinPath` |
| Hardcoded hostnames | Not reusable | Use host configs or network-constants |
| Missing `wantedBy` | Service won't auto-start | Always set `wantedBy = [ "multi-user.target" ]` |

## Conventions

- `programs.*` → GUI apps (lm-studio, stability-matrix)
- `services.*` → Background daemons (this directory)
- Firewall ports: declare in module via `lib.mkOptionDefault`, not in host configs
- Large services (>500 lines): `host-dashboard.nix` (589), `tplink-switches.nix` (519), `self-healing-alerts.nix` (412), `mcp-servers.nix` (441)
