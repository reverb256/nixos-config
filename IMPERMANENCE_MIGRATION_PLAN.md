# NixOS Cluster Impermanence Assessment & Migration Plan

## Current State Assessment

### System Overview
- **Cluster Size:** 4 Nodes (zephyr, nexus, forge, sentry)
- **OS:** NixOS Unstable (26.05)
- **Container Engine:** Podman (Rootless)
- **Networking:** Tailscale Mesh VPN
- **Storage Types:** BTRFS (3 nodes), EXT4 (Forge)

### Current Storage Configuration
```
Zephyr (Master):  BTRFS (/ + /home + /data)
Nexus (Build):    BTRFS (/ + /home)
Forge (Mining):   EXT4 (/)
Sentry (Monitor): BTRFS (/ + /home)
```

### Key Findings
1. **No Impermanence Implementation:** All nodes lack tmpfs mounts, state separation, or automated cleanup
2. **Boot Optimization:** `tmpfiles.cleanOnBoot` disabled (boot time optimization)
3. **Stateful Services:** , MinIO, LM Studio, Mining all store state on disk
4. **User Data:** `/home/j_kro` contains application data and configurations
5. **Filesystem Mix:** BTRFS (supports subvolumes) and EXT4 (Forge)
6. **Existing Backups:** Borgmatic + rclone backups in place

---

## Impermanence Implementation Strategy

### Phase 1: Foundation (Core Impermanence)
**Goal:** Implement basic impermanence with tmpfs for ephemeral data

#### 1.1 Add nix-community/impermanence Flake Input
```nix
# flake.nix
inputs = {
  # ... existing inputs
  impermanence.url = "github:nix-community/impermanence";
  impermanence.inputs.nixpkgs.follows = "nixpkgs";
};
```

#### 1.2 Create Impermanence Module
```nix
# modules/impermanence.nix
{ config, lib, pkgs, inputs, ... }:
with lib;
let
  cfg = config.impermanence;
in {
  options.impermanence = {
    enable = mkEnableOption "Impermanence system";
    persistentStoragePath = mkOption {
      type = types.str;
      default = "/persist";
      description = "Path for persistent storage";
    };
    # Per-node persistent paths configuration
    persistentPaths = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of paths to persist";
    };
  };

  config = mkIf cfg.enable {
    # Ephemeral tmpfs mounts
    fileSystems = {
      "/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = ["size=50%"];
      };
      "/var/log" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = ["size=10%"];
      };
      "/var/cache" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = ["size=20%"];
      };
      "/var/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = ["size=50%"];
      };
    };

    # Persistence configuration using nix-community/impermanence
    imports = [inputs.impermanence.nixosModules.impermanence];
    environment.persistence."${cfg.persistentStoragePath}" = {
      directories = cfg.persistentPaths;
    };
  };
}
```

---

## Phase 2: Per-Node Persistence Configuration

### Node 1: Zephyr (Master Workstation)
**Key Services:** LM Studio, MCP Servers, Steam
**Filesystem:** BTRFS with /data partition

```nix
# hosts/zephyr/configuration.nix
impermanence = {
  enable = true;
  persistentPaths = [
    # User data
    "/home/j_kro/.local/share/lm-studio"
    "/home/j_kro/.local/share/Steam"
    "/home/j_kro/.steam"
    "/home/j_kro/.config"
    
    # System state
    "/var/lib/"
    "/var/lib/mining"
    
    # Data partition (already persistent)
    "/data"
  ];
};
```

### Node 2: Nexus (Build Server)
**Key Services:** MinIO, Ollama, Garnix CI
**Filesystem:** BTRFS

```nix
# hosts/nexus/configuration.nix
impermanence = {
  enable = true;
  persistentPaths = [
    # MinIO/AIStor data
    "/var/lib/minio"
    
    #  state
    "/var/lib/"
    
    # Mining state
    "/var/lib/mining"
    
    # User data
    "/home/j_kro/.config"
  ];
};
```

### Node 3: Forge (Mining Rig)
**Key Services:** Mining (4 GPUs), ROCm
**Filesystem:** EXT4

```nix
# hosts/forge/configuration.nix
impermanence = {
  enable = true;
  persistentPaths = [
    # Mining state
    "/var/lib/mining"
    
    #  state
    "/var/lib/"
    
    # ROCm configuration
    "/opt/rocm"
    
    # User data
    "/home/j_kro/.config"
  ];
};
```

### Node 4: Sentry (Monitoring)
**Key Services:** Prometheus/Grafana, Ollama (CPU)
**Filesystem:** BTRFS

```nix
# hosts/sentry/configuration.nix
impermanence = {
  enable = true;
  persistentPaths = [
    # Monitoring data
    "/var/lib/prometheus"
    "/var/lib/grafana"
    
    #  state
    "/var/lib/"
    
    # Mining state
    "/var/lib/mining"
    
    # User data
    "/home/j_kro/.config"
  ];
};
```

---

## Phase 3: Filesystem Preparation

### BTRFS Subvolume Setup (Zephyr, Nexus, Sentry)
```bash
# Create persistent subvolume
sudo btrfs subvolume create /persist

# Mount persistent subvolume
# Add to hardware-configuration.nix:
fileSystems."/persist" = {
  device = "/dev/disk/by-uuid/<uuid>";
  fsType = "btrfs";
  options = ["subvol=@persist"];
};
```

### EXT4 Partition Setup (Forge)
```bash
# Create persistent directory on EXT4
sudo mkdir -p /persist

# Add to hardware-configuration.nix:
fileSystems."/persist" = {
  device = "/dev/disk/by-uuid/<uuid>";
  fsType = "ext4";
  options = ["defaults" "discard"];
  # Note: Can use separate partition or directory on root
};
```

---

## Phase 4: Backup Integration

### Update Backup Configuration
```nix
# modules/backup.nix
services.borgmatic = {
  # ... existing config
  config = {
    location = {
      source_directories = [
        "/persist"
        # Keep existing sources if needed
      ];
    };
  };
};

# modules/storage.nix - rclone backups
storage.remote.rclone.nexus-backups = {
  "persist" = {
    source = "/persist";
    remote = "nexus";
    path = "backup/persist";
    schedule = "daily";
  };
};
```

---

## Phase 5: Testing & Validation

### Test Strategy
1. **Single Node Test:** Deploy to Sentry first (least critical)
2. **Test Scenarios:**
   - Reboot test - verify persistent data survives
   - Services startup - verify , mining, etc. work
   - Backup test - verify borgmatic/rclone work
3. **Rollback Plan:** Keep snapshots of current system state
4. **Gradual Deployment:** Move to Forge, Nexus, then Zephyr

### Verification Steps
```bash
# Check tmpfs mounts
df -hT | grep tmpfs

# Verify persistent paths
ls -la /persist

# Check systemd units
systemctl status impermanence*

# Test backup
borgmatic create --verbosity 1
```

---

## Phase 6: Advanced Optimization

### Optional Enhancements
1. **BTRFS Snapshot Management:** Auto-snapshot /persist
2. **State Versioning:** Add version control to persistent configs
3. **Cleanup Rules:** Add systemd timers for temporary file cleanup
4. **Metrics:** Monitor tmpfs usage and persistence
5. **Encryption:** Encrypt /persist partition

---

## Implementation Timeline

| Phase | Estimated Time | Description |
|-------|----------------|-------------|
| 1. Foundation | 2 hours | Add flake input, create module |
| 2. Per-Node Config | 3 hours | Configure persistence per node |
| 3. Filesystem Prep | 2 hours | Create /persist subvolumes/directories |
| 4. Backup Update | 1 hour | Update backup configuration |
| 5. Testing | 4 hours | Test on Sentry, debug issues |
| 6. Deployment | 2 hours | Deploy to remaining nodes |
| **Total** | **14 hours** | Full implementation |

---

## Risk Assessment

### Low Risk
- Tmpfs mounts are reversible
- /persist creation is non-destructive
- Backups remain intact

### Medium Risk
- Services may fail to start initially
- Configuration drift in persistent data
- Storage space issues on small partitions

### Mitigation Strategies
- Test incrementally
- Keep system snapshots
- Monitor disk space usage
- Have rollback plan ready

---

## Success Criteria

✅ **Core Functionality:**
- All nodes boot successfully with tmpfs mounts
- Persistent data survives reboots
- Services (, MinIO, mining) function correctly
- Backups continue to operate

✅ **Performance:**
- No significant boot time regression
- Tmpfs mounts operate within size limits
- Storage I/O remains acceptable

✅ **Maintainability:**
- Configuration is declarative
- Documentation updated
- Easy to modify persistence rules

---

## Next Steps

1. **Approve Plan:** Verify approach with team
2. **Set Up Flake Input:** Add nix-community/impermanence to flake.nix
3. **Create Module:** Develop modules/impermanence.nix
4. **Configure Per-Node:** Update each host's configuration.nix
5. **Prepare Filesystems:** Create /persist partitions/subvolumes
6. **Test:** Deploy to Sentry and validate

This plan provides a structured, low-risk approach to implementing Impermanence while maintaining system functionality and data safety.
