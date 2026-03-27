# NixOS Services - Agent Context

**Parent:** `../../AGENTS.md` | **Domain:** Background daemons & services

## Overview
NixOS service modules for cluster infrastructure. Each module follows `services.<name>` namespace pattern.

## Structure
```
services/
├── ai-inference/       # AI gateway with routing (7 subdirs)
├── monitoring/         # Prometheus/Grafana stack
├── hermes-agent/       # Agent orchestration
├── kubernetes/         # K8s-related services
├── opencode-sync/      # Config sync
├── spacebot/           # Discord bot
└── *.nix               # Individual services (40+)
```

## Where To Look

| Task | Location |
|------|----------|
| Add AI/ML service | `ai-inference/default.nix` |
| Configure monitoring | `monitoring/default.nix` |
| Add GPU exporter | `gpu-exporters.nix` |
| Set up storage | `nfs-server.nix`, `garage.nix` |
| Add new daemon | Create `my-service.nix`, add to `../../default.nix` imports |

## Anti-Patterns (THIS DIRECTORY)

| Pattern | Why | Fix |
|---------|-----|-----|
| `ExecStart = "${pkgs.bash}/bin/bash -c '...'"` | Hard to read | Use `writeShellScript` |
| `Path = "${pkgs.bash}/bin:${pkgs.coreutils}/bin"` | Manual concat | Use `lib.makeBinPath` |
| `allowedTCPPorts = [22 80]` | Breaks SSH | Use `lib.mkOptionDefault` |
| Hardcoded hostnames | Not reusable | Use `network-constants.nix` |

## Key Conventions

### Namespace Rules
- `programs.*` → GUI apps (lm-studio, stability-matrix)
- `services.*` → Background daemons (this directory)

### Service Template
```nix
{ config, lib, pkgs, ... }:
let cfg = config.services.my-service;
    inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";
    port = mkOption { type = types.port; default = 8080; };
  };
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
    systemd.services.my-service = { ... };
  };
}
```

## Subdirectories

| Dir | Purpose | Key Files |
|-----|---------|-----------|
| `ai-inference/` | AI gateway + auth | `gateway.nix`, `router.nix`, `auth/` |
| `monitoring/` | Metrics stack | `node-exporter.nix`, `dashboards/` |
| `hermes-agent/` | Agent framework | `default.nix` |
| `spacebot/` | Discord bot | `default.nix` |

## Common Libraries

- `lib.getExe pkgs.package` → Single executable path
- `lib.makeBinPath [pkgs.bash pkgs.coreutils]` → Clean PATH
- `pkgs.writeShellScript "name" ''...''` → Multi-line scripts
