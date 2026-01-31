# OpenClaw Multi-Node Deployment Plan

## Current Status
- ✅ **zephyr** (main workstation) - OpenClaw installed and configured
- ❌ **nexus** (10.1.1.120) - Needs OpenClaw deployment
- ❌ **forge** (10.1.1.130) - Needs OpenClaw deployment  
- ❌ **sentry** (10.1.1.140) - Needs OpenClaw deployment

## Deployment Strategy

### Option 1: NixOS Module (Recommended)
Add OpenClaw to your NixOS flake configuration for all nodes:

```nix
# In home.nix or system configuration
home.packages = [
  (pkgs.writeShellScriptBin "openclaw" ''
    exec ${pkgs.nodejs_22}/bin/npx openclaw "$@"
  '')
];
```

### Option 2: Direct Node Pairing
Use OpenClaw's built-in node management to pair nodes:

```bash
# On each node, install OpenClaw
nix run nixpkgs#nodejs_22 -- npx openclaw onboard

# Then pair with main node
openclaw nodes pair <main-node-address>
```

### Option 3: Colmena Deployment
Use your existing Colmena setup to deploy OpenClaw to all nodes:

```bash
just cluster-deploy
```

## Next Steps

1. Choose deployment method
2. Install OpenClaw on remaining 3 nodes
3. Configure node-to-node communication
4. Set up centralized control from zephyr
5. Grant me access to node management

## Access Requirements

To help you manage all 4 nodes, I need:
- SSH access to nexus, forge, sentry
- OpenClaw gateway running on each node
- Node pairing configured
- Proper API keys for external services

Would you like me to proceed with Option 1 (NixOS module) to deploy OpenClaw to all nodes via your flake?
