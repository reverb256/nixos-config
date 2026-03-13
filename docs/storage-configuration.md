# Storage Configuration Analysis

## UUID Verification Status: ✅ ALL CORRECT (20/20 UUIDs verified)

All drive UUIDs in NixOS configurations have been verified against actual hardware UUIDs.
Last updated: 2026-03-13

## Summary of All Storage Drives

### Zephyr (10.1.1.110) - Control Plane
- nvme0n1p2 (931.5GB) - Root filesystem with @ and @home subvolumes ✓
- **nvme1n1p2 (921.9GB) - /data BTRFS with @,@games,@projects,@archive ✓** (FIXED 2026-03-13)
  - @ (ID 277) → /data (root subvolume, created as snapshot of ID 5)
  - @games (ID 274) → /data/games (game installations)
  - @projects (ID 275) → /data/projects (project files)
  - @archive (ID 276) → /data/archive (long-term archive)
- **NFS mounts from Nexus** ✓
  - /data/shared (read-write, automount)
  - /data/media (read-only, automount)

### Nexus (10.1.1.120) - Storage Node
- nvme0n1p2 (931.5GB) - Root filesystem with @ and @home subvolumes ✓
- **nvme1n1 (223.6GB) - "worn-storage" - NOT MOUNTED ❌**
- **bcache0 (3.6TB + 465GB cache) - "nexus-storage" - NOT MOUNTED ❌**
  - Contains subvolumes: home, shared, backups, media, containers
- **NFS Server running** ✓ (exports: /data/shared, /data/media, /data/home, /data/backups)
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

### 1. Nexus Storage Configuration (HIGH PRIORITY)
Add mounts for:
- `/dev/bcache0` → Mount subvolumes at /data/{home,shared,backups,media,containers}
- `/dev/nvme1n1` → Mount at /data/worn

### 2. Forge /home Configuration (LOW PRIORITY)
Consider creating @home subvolume on /dev/sdb2 for consistency

### 3. Loki/Promtail Logging (TODO)
- Loki service on Sentry (not found)
- Promtail agents on all nodes (not deployed)

### 4. Syncthing Config Sync (TODO)
- Module not created yet
- Device IDs not generated

### 5. Garage S3 Storage (TODO)
- Module not created yet
- 3-node cluster planned (Zephyr, Nexus, Sentry)

## Storage Mount Point Strategy

### /data Hierarchy
- `/data` - Root subvolume for local data (Zephyr)
- `/data/games` - Game installations (Zephyr local)
- `/data/projects` - Project files (Zephyr local)
- `/data/archive` - Long-term archive (Zephyr local)
- `/data/shared` - Shared files from nexus-storage (NFS, RO on Zephyr)
- `/data/media` - Media files from nexus-storage (NFS, RO on Zephyr)
- `/data/home` - User data from nexus-storage (NFS, when mounted)
- `/data/backups` - Local backups from nexus-storage (NFS, when mounted)
- `/data/containers` - Container storage from nexus-storage (NFS, when mounted)
- `/data/worn` - High-write workloads (worn NVMe, when mounted)

### /storage Hierarchy (Network Mounts)
- `/storage/remote/*` - Network backup mounts (existing on nexus)
- `/storage` - Local storage on sentry

## Implementation Priority

1. **HIGH**: Nexus - Mount bcache0 (nexus-storage) subvolumes
2. **HIGH**: Nexus - Mount nvme1n1 (worn-storage)
3. **MEDIUM**: Deploy Promtail to all nodes for log aggregation
4. **MEDIUM**: Create and deploy Syncthing for /etc/nixos sync
5. **LOW**: Forge - Create @home subvolume on /dev/sdb2
6. **LOW**: Garage S3 object storage deployment

## Completed (2026-03-13)

- ✅ Fixed Zephyr /data subvolume mounts
- ✅ Created @ subvolume as snapshot of root (ID 5)
- ✅ Updated hardware-configuration.nix with subvol=@
- ✅ Verified NFS mounts on Zephyr (/data/shared, /data/media)
