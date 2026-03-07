# Storage Configuration Analysis

## UUID Verification Status: ✅ ALL CORRECT (20/20 UUIDs verified)

All drive UUIDs in NixOS configurations have been verified against actual hardware UUIDs.
Date: 2026-03-06

## Summary of All Storage Drives

### Zephyr (10.1.1.110) - Local
- nvme0n1p2 (931.5GB) - Root filesystem with @ and @home subvolumes ✓
- All storage properly configured ✓

### Nexus (10.1.1.120) - Build/Backup Node
- nvme0n1p2 (931.5GB) - Root filesystem with @ and @home subvolumes ✓
- **nvme1n1 (223.6GB) - "worn-storage" - NOT MOUNTED ❌**
- **bcache0 (3.6TB + 465GB cache) - "nexus-storage" - NOT MOUNTED ❌**
  - Contains subvolumes: home, shared, backups, media, containers
- /storage used for network mounts (box-backups, dropbox-backups, etc.)

### Forge (10.1.1.130) - Mining Rig
- sda3 (229.5GB) - Root filesystem with @ subvolume ✓
- sdb2 (215.6GB) - /home mounted at BTRFS top-level (no named subvolume) ⚠️
  - Works but not best practice
  - Should use @home subvolume for consistency

### Sentry (10.1.1.140) - Monitoring Server
- sdb3 (229.5GB) - Root filesystem with @ and @home subvolumes ✓
- sda (931.5GB) - /storage with @data subvolume ✓
- All storage properly configured ✓

## Required Changes

### 1. Nexus Storage Configuration (PRIORITY)
Add mounts for:
- `/dev/bcache0` → Mount subvolumes at /data/{home,shared,backups,media,containers}
- `/dev/nvme1n1` → Mount at /data/worn

### 2. Forge /home Configuration (LOW PRIORITY)
Consider creating @home subvolume on /dev/sdb2 for consistency

## Storage Mount Point Strategy

### /data Hierarchy
- `/data/home` - User data from nexus-storage
- `/data/shared` - Shared files from nexus-storage
- `/data/backups` - Local backups from nexus-storage
- `/data/media` - Media files from nexus-storage
- `/data/containers` - Container storage from nexus-storage
- `/data/worn` - High-write workloads (worn NVMe)

### /storage Hierarchy (Network Mounts)
- `/storage/remote/*` - Network backup mounts (existing on nexus)
- `/storage` - Local storage on sentry

## Implementation Priority

1. **HIGH**: Nexus - Mount bcache0 (nexus-storage) subvolumes
2. **HIGH**: Nexus - Mount nvme1n1 (worn-storage)
3. **LOW**: Forge - Create @home subvolume on /dev/sdb2
