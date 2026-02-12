# 🔄 Reverb-OS: Idempotent Cluster Deployment System

## 🎯 **Overview**

The Reverb-OS cluster now features an idempotent deployment system that provides consistent behavior regardless of:

- **Which node** the command is executed from (zephyr, nexus, forge, sentry)
- **Current working directory** when the command is invoked
- **Current state** of the cluster (can run multiple times with same result)

## 🏗️ **Architecture**

### **Deployment Coordinator Pattern**
```
┌─────────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT COORDINATOR                       │
│                                                                     │
│  nexus (10.1.1.120) - Primary deployment coordinator              │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │    │
│  │  │   zephyr        │  │     forge       │  │   sentry    │ │    │
│  │  │   (10.1.1.110)  │  │   (10.1.1.130) │  │(10.1.1.140)│ │    │
│  │  │   Master/VR     │  │   GPU/Mining   │  │ Monitoring  │ │    │
│  │  └─────────────────┘  └─────────────────┘  └─────────────┘ │    │
│  │                              │                              │    │
│  │                              │                              │    │
│  └──────────────────────────────┼──────────────────────────────┘    │
│                                 │                                   │
│  SSH Communication via Tailscale VPN                               │
│  └─────────────────────────────────────────────────────────────────┘
│                                                                     │
│  All deployment commands:                                           │
│  • Build configurations                                             │
│  • Apply changes to nodes                                           │
│  • Update flake inputs                                              │
│  • Execute from nexus regardless of origin                          │
└─────────────────────────────────────────────────────────────────────┘
```

## 🚀 **Command Behavior**

### **Commands Executed on Nexus (Deployment Coordinator)**
| Command | Execution Node | Purpose |
|---------|----------------|---------|
| `just deploy` | nexus | Deploy to all hosts |
| `just cluster-deploy` | nexus | Deploy to all hosts via colmena |
| `just deploy-zephyr` | nexus | Deploy to zephyr only |
| `just deploy-nexus` | nexus | Deploy to nexus only |
| `just deploy-forge` | nexus | Deploy to forge only |
| `just deploy-sentry` | nexus | Deploy to sentry only |
| `just update` | nexus | Update flake + deploy all |
| `just cluster-update` | nexus | Update flake + deploy all |
| `just build` | nexus | Build configs (dry run) |

### **Commands Executed Locally (Current Node)**
| Command | Execution Node | Purpose |
|---------|----------------|---------|
| `just switch` | Current node | Apply configuration to current host |

## 🔧 **Implementation Details**

### **Justfile Integration**
The `justfile` now calls the idempotent wrapper:
```just
# All cluster operations use idempotent wrapper
deploy:
    /etc/nixos/scripts/just-cluster deploy

zephyr:
    /etc/nixos/scripts/just-cluster zephyr

switch:
    # Local operation - runs on current node
    cd /etc/nixos && sudo nixos-rebuild switch --flake ".#$(hostname -s)"
```

### **Idempotent Script (`/etc/nixos/scripts/just-cluster`)**
```bash
#!/bin/bash
# Determines if command should run locally or via SSH to coordinator
CURRENT_HOST=$(hostname -s)
COORDINATOR="nexus"

if [ "$CURRENT_HOST" = "$COORDINATOR" ]; then
    # Run locally on coordinator
    cd /etc/nixos
    sudo /etc/nixos/scripts/colmena-deploy "$1"
else
    # Run via SSH on coordinator
    ssh "$COORDINATOR" "cd /etc/nixos && sudo /etc/nixos/scripts/colmena-deploy $1"
fi
```

## 🌐 **Tailscale Integration**

All SSH communications between nodes use the secure Tailscale mesh VPN:
- **Internal IPs**: 10.1.1.x range
- **Tailscale IPs**: 100.x.x.x range 
- **Encrypted**: All communication via WireGuard
- **Authorized**: SSH keys configured for cross-node access

## ✅ **Idempotent Guarantees**

### **Consistency Properties**
1. **Same Origin**: Commands from zephyr produce same result as from nexus
2. **Any Directory**: Commands work from `/`, `/home`, `/etc/nixos`, etc.
3. **Repeat Safe**: Running same command multiple times produces same result
4. **Network Resilient**: Handles temporary network interruptions gracefully
5. **State Consistent**: Cluster state is consistent after each operation

### **Execution Path Normalization**
```
User runs: just deploy
├── Detects current node (zephyr, nexus, forge, or sentry)
├── Determines execution target (nexus for cluster ops, local for node ops)
├── Normalizes to absolute paths (/etc/nixos/)
├── Executes with consistent environment
└── Returns consistent result regardless of origin
```

## 🧪 **Verification Commands**

### **Check Deployment Consistency**
```bash
# Run from any node - should produce identical results
just deploy
just zephyr
just nexus
just forge
just sentry

# Verify cluster health after deployment
just cluster-status
```

### **Test Idempotency**
```bash
# Run multiple times - should be safe and consistent
just deploy
just deploy  # Should be no-op if already deployed
just deploy  # Should remain consistent

# Check that all nodes are in sync
ssh zephyr 'nixos-rebuild list-generations'
ssh nexus 'nixos-rebuild list-generations' 
ssh forge 'nixos-rebuild list-generations'
ssh sentry 'nixos-rebuild list-generations'
```

## 🚨 **Important Notes**

### **Security Considerations**
- All cluster operations use Tailscale VPN for secure communication
- SSH keys are properly configured between nodes
- Colmena runs with appropriate permissions on coordinator
- No cross-node security bypasses allowed

### **Failure Handling**
- SSH timeouts fall back to error messages
- Colmena operations are atomic per node
- Flake validation occurs before deployment
- Rollback procedures use standard NixOS mechanisms

## 🎯 **Benefits**

### **Developer Experience**
- **Location Independence**: Work from any cluster node
- **Simplified Commands**: Same command works everywhere
- **Consistent Results**: Predictable outcomes
- **Reduced Complexity**: No need to track execution context

### **Operational Benefits** 
- **Reliability**: System behaves consistently regardless of execution environment
- **Maintainability**: Easier troubleshooting (location doesn't matter)
- **Scalability**: Pattern works for additional nodes
- **Security**: All operations routed through coordinator

## 🐙 **Git Integration**

### **Source of Truth**
- **Primary**: GitHub `main` branch
- **Deployment**: GitHub `infra` branch (auto-merged by Actions)
- **Local sync**: `/etc/nixos/` directory on nexus

### **Update Flow**
```bash
# GitHub Actions auto-merge (main → infra)
# Manual deployment: 
just deploy          # Pulls from infra, deploys via colmena
```

---

*Document: REVERB_OS_IDEMPOTENT_DEPLOYMENT.md*  
*System: Reverb-OS Cluster*  
*Pattern: Deployment Coordinator with Idempotent Execution*