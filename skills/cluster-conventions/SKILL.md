---
name: cluster-conventions
description: Use when creating or modifying NixOS modules, Kubernetes manifests (easykubenix), Caddy routes, systemd services, or any configuration in /etc/nixos/. Contains ALL codebase-specific patterns — scratch image deployments, mkOptionDefault safety, GPU scheduling, Caddy auth routing, deployment safety limits, network policies, and agenix secrets. This is the SINGLE SOURCE OF TRUTH for "how we do things here". Always load before editing .nix files in this cluster.
license: MIT
metadata:
  author: https://github.com/Jeffallan
  version: "1.0.0"
  domain: infrastructure
  triggers: NixOS module, nix module, kubernetes manifest, easykubenix, caddy route, systemd service, K8s deployment, NixOS service, nix file, flake, colmena, deploy, firewall port
  role: conventions
  scope: cluster-config
  output-format: nix
  related-skills: kubernetes-specialist, nixos-best-practices, add-service-mcp
---

# Cluster Conventions — Single Source of Truth

**Mandatory reading** before editing ANY `.nix` file in `/etc/nixos/`.

This skill codifies every repeatable pattern in this NixOS cluster. Follow these patterns exactly — they encode hard-won operational knowledge (SSH breakage, pod explosions, OOM kills, GPU conflicts).

## Quick Reference

| Pattern | Skill Section | Critical? |
|---------|---------------|-----------|
| Scratch image for K8s pods | [K8s Scratch Pattern](#1-k8s-scratch-pattern) | Yes |
| mkOptionDefault for lists | [Extensible Lists](#2-extensible-lists-mkoptiondefault) | **BREAKS SSH** |
| Deployment safety limits | [Deployment Safety](#3-deployment-safety) | Yes |
| GPU scheduling | [GPU Scheduling](#4-gpu-scheduling) | Yes |
| Caddy routing | [Caddy Routing](#5-caddy-routing) | Yes |
| Nix module template | [Nix Module Boilerplate](#6-nix-module-boilerplate) | No |
| Lib helpers | [Lib Helpers](#7-lib-helpers) | No |
| Network policies | [Network Policies](#8-k8s-network-policies) | No |
| Agenix secrets | [Agenix Secrets](#9-agenix-secrets) | No |
| Systemd service patterns | [Systemd Services](#10-systemd-service-patterns) | No |
| PSS labels | [PSS Labels](#11-pod-security-standards) | No |
| Easykubenix labels | [Managed-By Labels](#12-easykubenix-managed-by-labels) | No |

---

## 1. K8s Scratch Pattern

**When:** Running ANY Nix-built binary in Kubernetes.

**Why:** No Docker image build needed. The scratch container mounts `/nix/store` from host and runs the Nix-built binary directly. Binary auto-updates on `nixos-rebuild switch`.

### Constants

```nix
let
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
in
```

### Volume Pattern (always needed)

```nix
volumes = {
  _namedlist = true;
  nix.hostPath = {
    path = "/nix";
    type = "Directory";
  };
};
```

### Container Pattern

```nix
containers = {
  _namedlist = true;
  my-app = {
    image = scratchImage;
    imagePullPolicy = "IfNotPresent";
    command = ["${pkgs.my-package}/bin/my-binary"];
    args = ["--port" "8080"];
    volumeMounts = {
      _namedlist = true;
      nix = {
        mountPath = "/nix";
        readOnly = true;
      };
    };
  };
};
```

### NVIDIA GPU Additions

```nix
# Add to volumes:
nvidia-libs.hostPath.path = "/run/opengl-driver/lib";

# Add to volumeMounts:
nvidia-libs = {
  mountPath = "/run/opengl-driver/lib";
  readOnly = true;
};

# Add to env:
LD_LIBRARY_PATH = {
  name = "LD_LIBRARY_PATH";
  value = "/run/opengl-driver/lib:/nix/store";
};
```

### AMD GPU (Vulkan) Additions

```nix
# Add to volumes:
dev-dri.hostPath = { path = "/dev/dri"; type = "Directory"; };
opengl.hostPath.path = "/run/opengl-driver/lib";
vulkan-icd.hostPath.path = "/run/opengl-driver/share/vulkan/icd.d";

# Add to env:
VK_ICD_FILENAMES = {
  name = "VK_ICD_FILENAMES";
  value = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
};
```

### Anti-Patterns

- **NEVER** build custom Docker images for Nix packages — use scratch + hostPath
- **NEVER** copy binaries out of /nix/store into an image — mount /nix read-only
- **NEVER** forget `_namedlist = true` on containers, volumes, volumeMounts, and env blocks

---

## 2. Extensible Lists (mkOptionDefault)

**When:** Setting ANY list option in a shared module (firewall ports, system packages, etc.).

**Why:** Direct assignment **replaces** the list across ALL hosts. Using `mkOptionDefault` **merges** with host-specific values. Getting this wrong breaks SSH on all nodes.

### The Rule

```nix
# ❌ WRONG — Replaces ALL port configs (breaks SSH!)
networking.firewall.allowedTCPPorts = [8080];

# ✅ CORRECT — Merges with existing ports
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [8080];
```

### When to Use Each

| Use `lib.mkOptionDefault` | Use Direct Assignment |
|---------------------------|----------------------|
| `networking.firewall.allowedTCPPorts` | `networking.hostName` |
| `networking.firewall.allowedUDPPorts` | `boot.loader.grub.device` |
| `environment.systemPackages` | Boolean flags |
| Lists that multiple modules contribute to | Strings (unique values) |
| `systemd.services` (attr merge) | Single-source-of-truth settings |

### Shortcut

```nix
inherit (lib) mkOptionDefault;
# Then:
allowedTCPPorts = mkOptionDefault [cfg.port];
```

---

## 3. Deployment Safety

**When:** Creating ANY K8s Deployment via easykubenix.

**Why:** Default K8s settings cause replica accumulation (old ReplicaSets never cleaned) and extra pods during rollouts (maxSurge=1). This cluster has limited RAM.

### Mandatory Settings

```nix
Deployment.my-app = {
  spec = {
    replicas = 1;                    # ALWAYS explicit
    revisionHistoryLimit = 1;        # NOT default 10 — prevents replica set accumulation
    strategy.type = "Recreate";      # For GPU/stateful workloads
    # OR for stateless services:
    # strategy = {
    #   type = "RollingUpdate";
    #   rollingUpdate = {
    #     maxSurge = 0;              # NEVER default 1 — prevents extra pods
    #     maxUnavailable = 1;
    #   };
    # };
  };
};
```

### Strategy Selection

| Workload Type | Strategy | Why |
|---------------|----------|-----|
| GPU inference, stateful | `Recreate` | Must stop old pod before starting new (GPU exclusive) |
| Stateless API, web | `RollingUpdate` with `maxSurge = 0` | Zero-downtime but no extra pods |

### Anti-Patterns

- **NEVER** use default `revisionHistoryLimit: 10` — always set to 1 or 2
- **NEVER** use default `maxSurge: 1` — always set to 0
- **NEVER** use `Recreate` for stateless services (causes downtime)
- **NEVER** use `RollingUpdate` for GPU workloads (two pods fight for same GPU)

---

## 4. GPU Scheduling

**When:** Deploying ANY GPU workload to K8s.

### Workload Placement Rules

| Node | RAM | Allowed Workloads |
|------|-----|-------------------|
| **Nexus** (46GB) | ✅ DEFAULT | All non-infrastructure, non-mining workloads |
| **Zephyr** (31GB) | ⚠️ Infrastructure ONLY | Control plane, K3s, NFS, mining — **NOTHING ELSE** |
| **Forge** (15GB) | Mining + GPU compute | Mining only |
| **Sentry** (31GB) | Monitoring + ROCm AI | Monitoring, AMD inference |

### nodeName Pattern (preferred for GPU)

```nix
spec = {
  nodeName = "nexus";  # Force scheduling — no ambiguity
  hostNetwork = true;   # Often needed for GPU services
};
```

### Zephyr Tolerations (if you MUST schedule there)

```nix
zephyrTolerations = [
  { key = "workstation"; operator = "Exists"; }
  { key = "interactive"; operator = "Exists"; }
  { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
];
```

### GPU Device Selection (NVIDIA)

```nix
# IMPORTANT: CUDA enumeration differs from nvidia-smi order!
# CUDA device 0 on zephyr = RTX 3090, CUDA device 1 = RTX 3060 Ti
env = {
  _namedlist = true;
  NVIDIA_VISIBLE_DEVICES = { name = "NVIDIA_VISIBLE_DEVICES"; value = "1"; };
  CUDA_VISIBLE_DEVICES = { name = "CUDA_VISIBLE_DEVICES"; value = "0"; };
};
```

### Priority Classes

```nix
priorityClassName = "high-priority-ai";  # For AI inference workloads
```

### Anti-Patterns

- **NEVER** schedule non-essential workloads to zephyr — it has constant OOM
- **NEVER** use `nodeAffinity` when `nodeName` suffices — simpler is better
- **NEVER** assume nvidia-smi GPU order matches CUDA order

---

## 5. Caddy Routing

**When:** Exposing a service via `.lan` domain.

### Architecture

- **Zephyr** (`hosts/zephyr/caddy-routes.nix`): `mkRoute` / `mkAuthRoute` helpers
- **Nexus** (`modules/services/cluster-services.nix`): Service registry with `protected = true`
- **DNS**: All `.lan` → VIP 10.1.1.100 (keepalived MASTER on zephyr)
- **Auth**: Caddy `forward_auth` → local `central-auth` (oauth2-proxy) on zephyr + nexus

### Zephyr: Public Route (no auth)

```nix
mkRoute "myapp.lan" "http://127.0.0.1:8080"
```

### Zephyr: Protected Route (SSO required)

```nix
mkAuthRoute "myapp.lan" "http://127.0.0.1:8080"
```

### Nexus: Service Registry

```nix
# In the services attrset:
my-app = {
  domain = "myapp.lan";
  backend = "http://127.0.0.1:8080";
  protected = true;  # Set false for public services
};
```

### Anti-Patterns

- **NEVER** deploy oauth2-proxy as K8s sidecar — use NixOS `central-auth` service
- **NEVER** use `forward_auth` pointing to non-local oauth2-proxy — always `localhost:4180`
- **NEVER** create K8s Ingress resources — Caddy handles all routing via NixOS config

---

## 6. Nix Module Boilerplate

**When:** Creating a new NixOS module in `modules/`.

### Template

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for the web interface";
    };

    # Flexible type for values that can be int or string:
    # port = mkOption { type = types.either types.int types.str; default = 5432; };
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    systemd.services.my-service = {
      wantedBy = ["multi-user.target"];
      serviceConfig.ExecStart = lib.getExe pkgs.my-package;
    };
  };
}
```

### Registration

1. Create file: `modules/services/my-service.nix`
2. Add to imports in `modules/default.nix`
3. Enable in host: `hosts/<hostname>/configuration.nix` → `services.my-service.enable = true;`
4. `git add` new file (Nix only sees git-tracked files!)

### Namespace Selection

| Namespace | When |
|-----------|------|
| `services.*` | Background daemons, systemd services |
| `programs.*` | Interactive GUI apps (LM Studio, etc.) |
| `hardware.*` | Hardware configuration |
| `profiles.*` | Composable profiles (hardware/role/network) |

---

## 7. Lib Helpers

### ExecStart — use lib.getExe

```nix
serviceConfig.ExecStart = lib.getExe pkgs.lm_sensors;
# If you need extra args:
serviceConfig.ExecStart = lib.getExe pkgs.lm_sensors + " -s";
```

### Multi-line scripts — use writeShellScript

```nix
ExecStart = pkgs.writeShellScript "my-script" ''
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Not found"
    exit 1
  fi
  exec ${lib.getExe pkgs.my-package}
'';
```

### PATH — use lib.makeBinPath

```nix
serviceConfig.Path = lib.makeBinPath [pkgs.bash pkgs.coreutils pkgs.jq];
```

### Data transforms — use lib.pipe

```nix
uid = lib.pipe title [
  (builtins.replaceStrings [" "] ["-"])
  lib.strings.trim
  lib.toLower
];
```

### Complex env vars — use lib.generators.toJSON

```nix
environment.etc."my-app/config.json".text =
  lib.generators.toJSON {} {
    port = cfg.port;
    debug = cfg.debug;
  };
```

---

## 8. K8s Network Policies

**When:** Creating a new K8s namespace.

### Default-Deny + Allow-DNS Pattern

```nix
# In common.nix or your namespace module:
Namespace.my-namespace = {
  metadata.labels = {
    name = "my-namespace";
    "pod-security.kubernetes.io/enforce" = "baseline";
    "pod-security.kubernetes.io/audit" = "restricted";
    "pod-security.kubernetes.io/warn" = "restricted";
  };
};
```

### NetworkPolicy (if needed via YAML)

Default deny-all + explicit allow is the standard pattern. See `skills/kubernetes-specialist/SKILL.md` for full NetworkPolicy examples.

---

## 9. Agenix Secrets

**When:** A service needs API keys, passwords, or certificates.

### Reference Pattern

```nix
# Secrets live at /run/agenix/<name> after decryption
# Define in secrets/secrets.nix, encrypt with agenix
environmentFiles = [
  config.age.secrets.my-secret.path  # → /run/agenix/my-secret
];
```

### Secret Registration

1. Add secret file: `secrets/my-secret.age`
2. Register in `secrets/secrets.nix`
3. Reference in module: `config.age.secrets.my-secret.path`
4. The module using it must list it in `age.secrets.*.file`

---

## 10. Systemd Service Patterns

### Standard Service

```nix
systemd.services.my-service = {
  description = "My Service";
  after = ["network.target" "network-online.target"];
  wants = ["network-online.target"];
  wantedBy = ["multi-user.target"];

  serviceConfig = {
    Type = "simple";
    ExecStart = lib.getExe pkgs.my-package;
    Restart = "on-failure";
    RestartSec = "10s";
  };
};
```

### Timer Unit

```nix
systemd.timers.my-service = {
  wantedBy = ["timers.target"];
  timerConfig = {
    OnCalendar = "hourly";
    OnUnitActiveSec = "1h";
    Persistent = true;
  };
};

systemd.services.my-service = {
  script = ''
    ${lib.getExe pkgs.curl} -s http://localhost:8080/health
  '';
  serviceConfig.Type = "oneshot";
};
```

### Service with Shell Script

```nix
systemd.services.my-service = {
  wantedBy = ["multi-user.target"];
  path = lib.makeBinPath [pkgs.bash pkgs.coreutils pkgs.curl];

  serviceConfig = {
    ExecStart = pkgs.writeShellScript "my-service" ''
      set -euo pipefail
      source ''${1:-/run/agenix/my-secret}
      exec ${lib.getExe pkgs.my-package} --config /etc/my-app/config.yaml
    '';
  };
};
```

### Anti-Patterns

- **NEVER** use `"${pkgs.bash}/bin/bash -c '...'"` for ExecStart — use `writeShellScript`
- **NEVER** manually concatenate PATH strings — use `lib.makeBinPath`
- **NEVER** forget `wantedBy = ["multi-user.target"]` — service won't auto-start
- **NEVER** use `systemctl enable` — declare in NixOS config

---

## 11. Pod Security Standards

**When:** Creating a new K8s namespace via easykubenix.

```nix
Namespace.my-namespace = {
  metadata.labels = {
    name = "my-namespace";
    "pod-security.kubernetes.io/enforce" = "baseline";
    "pod-security.kubernetes.io/audit" = "restricted";
    "pod-security.kubernetes.io/warn" = "restricted";
  };
};
```

| Level | Enforce | Audit/Warn |
|-------|---------|------------|
| Standard namespace | `baseline` | `restricted` |
| Privileged (system) | `privileged` | `privileged` |

---

## 12. Easykubenix Managed-By Labels

**When:** Creating ANY K8s resource via easykubenix.

```nix
let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in
{
  Deployment.my-app = {
    metadata.labels = managed // {
      app = "my-app";
      host = "nexus";
    };
    spec.selector.matchLabels = { app = "my-app"; };
    spec.template.metadata.labels = managed // {
      app = "my-app";
    };
  };
}
```

### Labels Convention

| Label | Purpose | Example |
|-------|---------|---------|
| `app.kubernetes.io/managed-by` | Tool that created resource | `"easykubenix"` |
| `app` | Service identifier | `"llama-server-zephyr"` |
| `host` | Target node | `"nexus"`, `"zephyr"` |
| `gpu` | GPU identifier | `"rtx3090"`, `"rtx3060ti"` |

### Annotation Pattern

```nix
metadata.annotations."nix-csi/discard" = "true";  # For scratch-image pods
```

---

## Detailed Reference Files

For deeper examples and edge cases, see:

| Topic | Reference File |
|-------|---------------|
| Full K8s deployment examples | `references/k8s-deployments.md` |
| NixOS module examples | `references/nixos-modules.md` |
| Caddy routing deep-dive | `references/caddy-routing.md` |

## Source Files (canonical implementations)

These files are the ground truth for each pattern:

| Pattern | Source File |
|---------|-------------|
| Scratch image + GPU | `kubernetes/modules/llama-servers.nix` |
| Deployment safety | All files in `kubernetes/modules/` |
| Caddy routes (zephyr) | `hosts/zephyr/caddy-routes.nix` |
| Caddy routes (nexus) | `modules/services/cluster-services.nix` |
| PSS labels | `kubernetes/modules/common.nix` |
| NixOS module template | `modules/services/*.nix` (any file) |
| Systemd service patterns | `modules/services/*.nix` |
| Lib helpers | `modules/` throughout |
