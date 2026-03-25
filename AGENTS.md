# NixOS Cluster - Agent Guidelines

## Quick Start

```bash
just check              # Quick flake validation (no build)
just test               # Build all hosts (verify config)
just switch             # Apply to local host
just deploy [<host>]    # Deploy to all or specific host
just rollback           # Rollback local host
```

## Project Overview

| Host | IP | Role |
|------|-----|------|
| Zephyr | 10.1.1.110 | Control plane, gaming, AI |
| Nexus | 10.1.1.120 | Storage, GPU computing |
| Forge | 10.1.1.130 | GPU computing, mining |
| Sentry | 10.1.1.140 | Monitoring, logging |

**Resources**: 78 cores, 123GB RAM, 7 GPUs, 8.4TB storage

## Project Structure

```
/etc/nixos/
├── flake.nix              # Main flake
├── colmena.nix            # Multi-host deployment
├── hosts/<hostname>/      # Host configs (never edit hardware-configuration.nix)
├── modules/               # Reusable modules (default.nix imports all)
│   ├── profiles/          # Hardware/role/network profiles
│   ├── system/            # Core system modules
│   └── services/          # Background services
└── secrets/               # Agenix encrypted secrets
```

## ⚠️ Critical Safety Rules

### mkOptionDefault (MANDATORY for extensible options)

```nix
# ❌ WRONG - Replaces node configs (breaks SSH!)
networking.firewall.allowedTCPPorts = [22 53 6443];

# ✅ CORRECT - Merges with node configs
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];
```

| Use `mkOptionDefault` | Use Direct Assignment |
|-----------------------|----------------------|
| Lists (ports, packages) | Booleans |
| Attrs that merge (systemd.services) | Strings (hostName) |

### Workload Scheduling (ZEPHYR OOM PREVENTION)

**⚠️ CRITICAL: ZEPHYR HAS CONSTANT OOM EXHAUSTION (31GB RAM running control plane + AI + gaming)**

**Default ALL non-infrastructure, non-mining workloads to NEXUS (46GB RAM)**

**Valid scheduling targets:**

| Node | RAM | Purpose |
|------|-----|---------|
| **Nexus** | 46GB | ✅ DEFAULT for ALL workloads except: |
| | | - Infrastructure (control plane, Calico, storage, monitoring) |
| | | - Mining (must be on nodes with GPUs: forge, nexus, zephyr) |
| **Zephyr** | 31GB | ⚠️ ONLY infrastructure + mining: |
| | | - Control plane: kube-apiserver, etcd, kube-scheduler, kube-controller-manager |
| | | - CNI: Calico components (calico-node, tigera-operator) |
| | | - Mining: gpu-miner-zephyr, xmrig-zephyr (RTX 3090 GPU 1) |
| | | - ❌ NO OTHER WORKLOADS |

**Enforce nexus scheduling in Kubernetes manifests:**

```yaml
# Option 1: nodeName (simple, direct)
spec:
  template:
    spec:
      nodeName: nexus  # Force scheduling to nexus

# Option 2: nodeAffinity (flexible, preferred)
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - nexus

# ❌ NEVER use nodeSelector without checking target node capacity FIRST
# ALWAYS run: kubectl top nodes && kubectl describe node <target>
```

### Stop Immediately If
- SSH breaks on any node
- Multiple nodes affected
- `nix flake check` fails

## Code Style

- **2-space indentation**, trailing semicolons
- **kebab-case** for files: `gpu-exporters.nix`
- **Line length**: 80-100 chars

### Lib Functions Best Practices

**ExecStart Declarations**

✅ **PREFERRED**: Use `lib.getExe` for single executables
```nix
serviceConfig.ExecStart = lib.getExe pkgs.lm_sensors + " -s";
```

❌ **AVOID**: Direct path construction
```nix
serviceConfig.ExecStart = "${pkgs.lm_sensors}/bin/sensors -s";
```

**Complex Multi-Line Scripts**

✅ **PREFERRED**: Use `writeShellScript` for clarity
```nix
ExecStart = pkgs.writeShellScript "my-script" ''
  # Multi-line shell logic
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config not found"
    exit 1
  fi
  echo "Starting service..."
'';
```

❌ **AVOID**: Inline bash -c with complex logic
```nix
ExecStart = "${pkgs.bash}/bin/bash -c 'if [ ! -f $CONFIG_FILE ]; then echo \"Config not found\"; exit 1; fi';
```

**PATH Construction**

✅ **PREFERRED**: Use `lib.makeBinPath` for clean PATH construction
```nix
serviceConfig.Path = lib.makeBinPath [pkgs.bash pkgs.coreutils pkgs.curl];
```

❌ **AVOID**: Manual PATH string concatenation
```nix
export PATH="${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.curl}/bin:$PATH"
```

**Systemd Helper Functions**

✅ **PREFERRED**: Use helpers from `systemd-helpers.nix`
```nix
systemd.services.my-service = mkSimpleService {
  description = "My service";
  execStart = lib.getExe pkgs.my-package;
  pathPackages = [pkgs.bash pkgs.coreutils];
};
```

**Functional Data Transformation (lib.pipe)**

✅ **PREFERRED**: Use `lib.pipe` for multi-stage transformations
```nix
# Clean pipeline: data flows top-to-bottom
uid = lib.pipe dashboardTitle [
  (builtins.replaceStrings ["🏠"] [""])  # Remove emoji
  (builtins.replaceStrings [" " "/"] ["-" "-"])  # Normalize spaces/slashes
  lib.strings.trim  # Clean whitespace
  lib.toLower  # Lowercase for UID
];
```

❌ **AVOID**: Nested function calls (hard to read)
```nix
uid = lib.toLower (lib.strings.trim (builtins.replaceStrings [" " "/"] ["-" "-"] (builtins.replaceStrings ["🏠"] [""] title)));
```

**Debug Output Infrastructure**

✅ **PREFERRED**: Use ExecStartPre for sanitized configuration logging
```nix
serviceConfig.ExecStartPre = pkgs.writeShellScript "my-service-debug" ''
  echo "[my-service] Configuration:" >&2
  echo "[my-service]   Port: ${toString cfg.port}" >&2
  echo "[my-service]   API Key: ${
    if cfg.apiKey != null then "***REDACTED***" else "Not configured"
  }" >&2
'';
```

**Advanced Type System (types.either, types.oneOf)**

✅ **PREFERRED**: Use `types.either` for flexible option types
```nix
# Accepts either port number (int) or service name (str)
port = mkOption {
  type = types.either types.int types.str;
  default = 5432;
  description = "Database port or service name (e.g., 5432 or \"postgresql\")";
};

# Accepts URL or Unix socket path using types.oneOf
connection = mkOption {
  type = types.oneOf [
    (types.str // {description = "Database URL";})
    (types.path // {description = "Unix socket path";})
  ];
  default = "postgresql:///db";
  description = "Connection string or socket path";
};
```

❌ **AVOID**: Manual type validation in assertions
```nix
# Don't do this - use types.either instead
port = mkOption { type = types.int; };
config = mkIf cfg.enable {
  assertions = [
    {
      assertion = builtins.isString cfg.port || builtins.isInt cfg.port;
      message = "Port must be string or int";
    }
  ];
};
```

### Module Template

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";
    port = mkOption { type = types.port; default = 8080; };
  };
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
    systemd.services.my-service = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.my-package}/bin/my-service";
    };
  };
}
```

### Naming Conventions

| Namespace | Usage |
|-----------|-------|
| `services.*` | Background daemons |
| `programs.*` | Interactive GUI apps |
| `hardware.*` | Hardware config |
| `profiles.*` | Composable profiles |

## Deployment Workflow

1. Edit config on Zephyr (source of truth)
2. `git add` new files (Nix only sees git-tracked files!)
3. `just check` → `just switch` → `just deploy`

### Testing Checklist

| File Changed | Test On |
|--------------|---------|
| `modules/networking/*` | zephyr AND nexus |
| `modules/system/ssh.nix` | ALL 4 nodes |
| `modules/system/users.nix` | ALL 4 nodes |
| `modules/default.nix` | Entire cluster |

## Profile System

```nix
hardware.profiles = { amd.zen = true; nvidia.enable = true; };
profiles.role = { workstation = true; gaming = true; };
profiles.network.tailscale.enable = true;
```

## Reference

| Document | Purpose |
|----------|---------|
| `AGENT_INCIDENT_REPORT.md` | Post-mortems of past incidents |
| `ROADMAP.md` | Kubernetes migration plan |
| `modules/README.md` | Module development guide |

---

**Version**: 3.1 | **Updated**: 2026-03-18
