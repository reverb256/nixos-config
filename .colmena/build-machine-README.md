# Colmena Build Machine Configuration

This directory contains Colmena-specific configuration for distributed builds.

## Files

- `ssh-config`: SSH configuration for all cluster nodes
- `heredoc-builder.conf`: NixOS module applied to build machines (disabled by default)

## Deploy with Colmena

```bash
just colmena-deploy                    # Deploy from current host
just colmena-deploy --on nexus        # Deploy to specific host
just colmena-deploy --on nexus forge  # Deploy to multiple hosts
just colmena-deploy --show-trace      # Debug build failures

# Build only (no deployment)
just colmena-build

# Local switch only (no remote deployment)
just colmena-switch
```

## Distributed Build Machines

To enable a node as a distributed build machine, add to its configuration:

```nix
imports = [
  ./.colmena/heredoc-builder.conf
];
```

Build machines must:
- Allow SSH access from deployer
- Have sufficient RAM (Nexus: 46GB, Forge: 16GB)
- Have Nix daemon configured for remote builds

## Architecture

```
colmena.nix
├── mkHost function (deployment.* config)
├── buildOnTarget = false (build local, deploy remote)
├── replaceUnknownProfiles = true (allow profile replacement)
└── nodeNixpkgs mapping (per-host nixpkgs)
```

## Key Differences from Legacy `just deploy`

| Feature | Colmena | Legacy |
|---------|---------|--------|
| Build location | Local (config-driven) | Local (script-driven) |
| Transfer method | SSH + nix-copy-closure (auto) | Manual nix-copy-closure |
| Host isolation | Preserved | Preserved |
| Distributed builds | Native | Manual |
| Profile replacement | Configured | Implicit |

## Fallback

Legacy `just deploy` remains available for node-isolated deployments:
```bash
just deploy nexus
```