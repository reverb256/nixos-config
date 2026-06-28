# Colmena Deployment — Distributed Builds & Build Machines

## Overview

Colmena is now the primary deployment method for the NixOS cluster. It provides:
- Distributed builds across multiple machines
- Automatic dependency resolution and build orchestration
- SSH-based deployment with nix-copy-closure
- Proper build machine configuration and isolation

## Quick Start

```bash
# Deploy from current host (Colmena default)
just deploy                    # Deploy all hosts
just deploy nexus              # Deploy single host
just deploy nexus forge        # Deploy multiple hosts

# Colmena-specific commands
just colmena-build             # Build only (no deploy)
just colmena-switch            # Build + local switch (no remote)

# Legacy fallback (nix-copy-closure)
just deploy-legacy nexus       # Manual node-isolated deploy
```

## Deployment Model

```
┌─────────────────────────────────────────────────────────────────┐
│ Colmena (zephyr)                                              │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ Build Phase (parallel, distributed)                     │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                 │  │
│  │  │ nexus   │  │ forge   │  │ sentry  │                 │  │
│  │  │ 46GB    │  │ 16GB    │  │ 31GB    │                 │  │
│  │  └─────────┘  └─────────┘  └─────────┘                 │  │
│  └─────────────────────────────────────────────────────────┘  │
│                              ↓                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ Deploy Phase (serial, SSH + nix-copy-closure)           │  │
│  │  nexus → forge → sentry (strict order)                 │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration

### colmena.nix

```nix
{
  meta = {
    nixpkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    nodeNixpkgs = {
      zephyr = tunedNixpkgs "x86_64-linux";
      nexus = tunedNixpkgs "x86_64-linux";
      forge = tunedNixpkgs "x86_64-linux";
      sentry = tunedNixpkgs "x86_64-linux";
      krash3 = tunedNixpkgs2605 "x86_64-linux";
    };
    sshUser = "j_kro";
    allowApplyAll = false;
  };

  nexus = mkHost {
    hostName = "nexus";
    targetHost = "10.1.1.120";
    deployment = {
      buildOnTarget = false;
      replaceUnknownProfiles = true;
    };
  };
}
```

### Build Machines

To enable a node as a distributed build machine:

```nix
# hosts/nexus/configuration.nix
imports = [
  /.colmena/heredoc-builder.conf
];
```

Build machine requirements:
- SSH access from deployer (zephyr)
- Sufficient RAM (Nexus: 46GB, Forge: 16GB)
- Nix daemon configured for remote builds
- `trusted-users = [ "j_kro" ]`

## SSH Configuration

Colmena uses `.colmena/ssh-config` for host definitions:

```ssh
Host nexus
    HostName 10.1.1.120
    User j_kro
```

## Deployment Order

Deploy in strict order to avoid service disruption:
1. **nexus** (storage, K8s worker)
2. **forge** (GPU compute, K8s worker)
3. **sentry** (monitoring, K8s worker)

**NEVER deploy zephyr via Colmena** — use `just switch` for local changes.

## Troubleshooting

### Build fails with "connection refused"
```bash
# Check SSH connectivity
ssh nexus 'echo OK'

# Verify Colmena config
nix run .#colmena -- eval --on nexus
```

### Profile replacement blocked
```bash
# Check for unknown profiles
ssh nexus 'nix-env -p /nix/var/nix/profiles/system --list-generations | grep unknown'

# Force replacement (destructive)
nix run .#colmena -- apply --on nexus --force-replace-unknown-profiles
```

### Distributed build not used
```bash
# Verify build machine configuration
nix run .#colmena -- eval --on nexus --show-trace
```

## Legacy Fallback

The `deploy-legacy` command preserves the original nix-copy-closure workflow:

```bash
just deploy-legacy nexus  # Single host
just deploy-legacy all    # All hosts
```

Use this when Colmena fails or for debugging.

## Files

- `colmena.nix`: Colmena configuration (host definitions, build settings)
- `.colmena/ssh-config`: SSH configuration for all nodes
- `.colmena/heredoc-builder.conf`: NixOS module for build machines
- `.colmena/build-machine-README.md`: This file
- `justfile`: Deployment commands (`deploy`, `colmena-build`, `deploy-legacy`)

## Migration from Legacy

| Legacy Command | Colmena Equivalent |
|---------------|-------------------|
| `just deploy nexus` | `just deploy nexus` (now Colmena) |
| `just deploy all` | `just deploy all` (now Colmena) |
| Manual nix-copy-closure | Automatic via Colmena |
| `deploy-drones` | `just deploy-all` |

No workflow changes required — `just deploy` now uses Colmena by default.