# Cluster Storage Architecture

**Last Updated:** 2026-03-13

## Overview

The cluster uses a hybrid storage architecture combining traditional NFS file sharing with S3-compatible object storage for different use cases.

## Storage Technologies

### 1. NFS (Network File System)
**Server:** Nexus (10.1.1.120)
**Protocol:** NFSv4
**Purpose:** Traditional file sharing, POSIX-compatible storage

**Exports:**
| Path | Size | Clients | Purpose |
|------|------|---------|---------|
| `/data/shared` | 3.7TB | Forge, Sentry | Cluster data, shared projects |
| `/data/home` | 3.7TB | Forge | User home directories |
| `/data/media` | 3.7TB | Forge | Media library |
| `/data/backups` | 3.7TB | Local only | Backup archive (on NFS server) |

**Client Mounts:**
```bash
# Zephyr (control plane)
# Uses local NVMe storage - no NFS mounts for /data
/data (local NVMe)

# Nexus (server)
# Local on /dev/bcache0 (SSD cache + HDD backing)
/data/shared, /data/home, /data/media, /data/backups (local)

# Forge (GPU compute)
/data/shared  → 10.1.1.120:/data/shared  (rw, via NFS)
/data/home    → 10.1.1.120:/data/home    (rw, via NFS)
/data/media   → 10.1.1.120:/data/media   (rw, via NFS)

# Sentry (monitoring)
/data/shared  → 10.1.1.120:/data/shared  (rw, via NFS)
```

### 2. Garage (S3-Compatible Object Storage)
**Architecture:** 3-node distributed cluster
**Replication:** 3-way replication (consistent mode)
**Protocol:** S3 API (port 3900)

**Node Configuration:**
| Node | ID (short) | Storage | Capacity | Speed |
|------|------------|---------|----------|-------|
| **Zephyr** | `35ba2a0bd6db0c86` | `/data/garage` (SSD) | 500GB | Fast |
| **Nexus** | `1ecbbd14ca5ebf32` | `/data/shared/garage` (bcache) | 3TB | Medium |
| **Sentry** | `1c10c1bfb54bcaa5` | `/storage/garage` (HDD) | 900GB | Slow |

**S3 Buckets (configured):**
- `backups` - Backup archives
- `media` - Media library
- `projects` - Project data
- `logs` - Log aggregation
- `test-bucket` - Testing

**Effective Cluster Capacity:** 500GB (limited by smallest zone for 3-way replication)

**Access:** S3 API at `http://10.1.1.110:3900`

**S3 Credentials:**
- **Admin Key ID:** `GKac91d924fc76a30b9bcf6c3e`
- **Secret Key:** Stored in agenix (see `/run/agenix/garage-admin-key`)
- **Region:** `garage`

**S3 Configuration Example:**
```bash
# AWS CLI
aws configure set default.s3.endpoint_url http://10.1.1.110:3900
aws configure set default.s3.addressing-style path

# List buckets
aws --endpoint-url http://10.1.1.110:3900 s3 ls
```

### 5. Kubernetes Storage Integration
**Purpose:** Kubernetes manifests for storage consumption
**Location:** `docs/kubernetes/storage/`
**Status:** Manifests created, pending application

**Storage Classes Defined:**
| Class | Purpose | Backend | Node |
|-------|---------|---------|------|
| `fast-local-ssd` | Databases, ML models | Local SSD | Zephyr |
| `nfs-shared-storage` | Shared data | NFS | Nexus |
| `slow-hdd-storage` | Logs, archive | Local HDD | Sentry |
| `garage-s3` | S3 object storage | S3 API | All |

**Key Point:** Storage is **decoupled from Kubernetes**. The same NFS/S3 infrastructure serves both systemd services and K8s pods.

**Files:**
- `storage-classes.yaml` - StorageClass definitions
- `persistent-volumes.yaml` - PV mappings to cluster storage
- `persistent-volume-claims.yaml` - Example PVCs
- `garage-s3-secret.yaml` - S3 credentials for K8s
- `garage-csi-plan.md` - CSI driver integration plan
- `README.md` - Full documentation

### 3. Syncthing
**Purpose:** Peer-to-peer configuration sync
**Synced:** `/etc/nixos` configuration directory
**Nodes:** All 4 nodes (zephyr, nexus, forge, sentry)
**Versioning:** 10 versions retained
**Ports:** 22000 (TCP), 21027 (UDP), 8384 (Web UI)

### 4. NixOS-Share
**Purpose:** Centralized NixOS configuration read-only mount
**Server:** Zephyr (exports `/etc/nixos`)
**Clients:** Nexus, Forge, Sentry
**Protocol:** NFS (read-only)
**Path (Server):** `/etc/nixos` (exported from Zephyr)
**Path (Clients):** `/run/nixos-shared` (mounted to avoid bubblewrap conflicts)
**Convenience Path:** `/etc/nixos-shared` → symlink to actual mount point
**Environment Variable:** `NIXOS_SHARED_PATH` points to the mount location

**Design Note:** Clients mount to `/run/nixos-shared` instead of `/etc/nixos` to avoid
conflicts with bubblewrap-based sandboxes (steam-run, anime-game-launcher, etc.) that
attempt to bind-mount the entire root filesystem. The `/run` directory is already
excluded by default in bubblewrap, so this approach prevents NFS remount errors.

## Storage Tiers by Speed

### Tier 1: Fast (SSD)
- **Zephyr local:** 922GB NVMe SSD
- **Zephyr Garage:** Fast metadata/data access
- **Use case:** Hot data, frequently accessed files

### Tier 2: Medium (BCache - SSD cache + HDD)
- **Nexus bcache0:** 3.7TB effective storage
- **NFS exports:** Fast read for cached data, HDD for bulk
- **Use case:** Shared datasets, backups

### Tier 3: Slow (HDD)
- **Sentry local:** 930GB HDD
- **Sentry Garage:** Cold storage tier
- **Use case:** Archive, infrequently accessed data

## Cluster Storage Design

```
┌─────────────────────────────────────────────────────────────────┐
│                    STORAGE ARCHITECTURE                         │
└─────────────────────────────────────────────────────────────────┘

  ┌─────────┐      ┌──────────┐      ┌──────────┐
  │ ZEPHYR  │      │  NEXUS   │      │  SENTRY  │
  │  SSD    │      │ Bcache0  │      │   HDD    │
  │  922GB  │      │  3.7TB   │      │  930GB   │
  └────┬────┘      └────┬─────┘      └────┬─────┘
       │                │                 │
       │    ┌───────────┴───────────────────┐
       │    │           NFS Network           │
       │    └───────────┬───────────────────┘
       │                │
       ▼                ▼
  ┌─────────────────────────────────────────────┐
  │              /data/shared (NFS)              │
  │          - Projects, configs, shared       │
  └─────────────────────────────────────────────┘
       │
       ▼
  ┌─────────────────────────────────────────────┐
  │          Garage S3 Cluster                 │
  │  ┌────────┐  ┌────────┐  ┌────────┐      │
  │  │Zephyr  │  │ Nexus  │  │Sentry │      │
  │  │Fast    │  │Medium │  │ Slow   │      │
  │  │cap=4   │  │cap=2   │  │cap=1  │      │
  │  └────────┘  └────────┘  └────────┘      │
  └─────────────────────────────────────────────┘
       │
       ▼
  ┌─────────────────────────────────────────────┐
  │         S3 Buckets                         │
  │  - backups  - media  - projects  - logs   │
  └─────────────────────────────────────────────┘
```

## Configuration Files

| File | Purpose |
|------|---------|
| `modules/services/nfs-server.nix` | NFS server configuration (Nexus) |
| `modules/services/nfs-client.nix` | NFS client configuration (all nodes) |
| `modules/services/garage.nix` | Garage S3 object storage |
| `modules/services/syncthing.nix` | P2P config sync |
| `modules/services/nixos-share.nix` | NixOS config NFS sharing |
| `modules/services/backup-to-garage.nix` | Automated backup service |
| `scripts/backup-to-garage.sh` | Backup script (manual or automated) |
| `docs/kubernetes/storage/*.yaml` | K8s storage manifests |
| `docs/kubernetes/storage/garage-csi-plan.md` | CSI integration plan |

## Maintenance Commands

### NFS Status
```bash
# Check NFS exports on Nexus
showmount -e nexus

# Check NFS mounts on any node
df -h | grep nfs

# Restart NFS server
ssh nexus "sudo systemctl restart nfs-server"
```

### Garage Status
```bash
# Check cluster health
ssh zephyr "sudo garage -c /etc/garage.toml status"

# Show cluster layout
ssh zephyr "sudo garage -c /etc/garage.toml layout show"

# List buckets
ssh zephyr "sudo garage -c /etc/garage.toml bucket list"

# View metrics
curl http://10.1.1.110:3903/metrics
```

### Syncthing Status
```bash
# Check sync status
systemctl status syncthing

# View Web UI
# http://localhost:8384 (on each node)
```

## Troubleshooting

### NFS mount issues
```bash
# Check if NFS server is running
ssh nexus "systemctl status nfs-server"

# Check exports
ssh nexus "showmount -e localhost"

# Test mount manually
mount -t nfs4 10.1.1.120:/data/shared /mnt/test
```

### Garage cluster issues
```bash
# Check if nodes can communicate
# On Zephyr, ping Sentry's RPC port
nc -zv 10.1.1.140 3901

# Check Garage logs
ssh zephyr "journalctl -u garage -f"

# Verify RPC secret matches (must be identical on all nodes)
grep rpcSecret /etc/nixos/hosts/*/configuration.nix
```

### Syncthing not syncing
```bash
# Check connection between nodes
# GUI: Remote Devices → Show ID

# Restart syncthing
systemctl restart syncthing
```

## Deployment Status (2026-03-13)

**✅ COMPLETED:**
- Garage 3-node cluster operational
- Cluster layout applied with proper capacity tiers (500G/3T/900G)
- S3 buckets created: backups, media, projects, logs, test-bucket
- Admin S3 access key configured with full permissions
- Kubernetes storage manifests created:
  - StorageClasses (4 tiers)
  - PersistentVolumes (8 PVs defined)
  - PersistentVolumeClaims (examples)
  - S3 secrets template
- Backup automation script created

**🔄 IN PROGRESS:**
- Agenix secret storage for S3 credentials (needs manual setup)
- K8s directory creation on nodes

**⏳ TODO:**
- Apply Kubernetes storage manifests to cluster
- Install S3 CSI driver (Phase 2)
- Configure applications to use Garage S3
- Enable automated backup systemd timer

## Future Improvements

1. **Garage Multi-Region:** Add remote Garage node for disaster recovery
2. **Tiered S3 Lifecycle:** Auto-transition old data to slow tier
3. **NFS Root Squash:** Consider `no_root_squash` security implications
4. **Backup Automation:** ✅ Script created, enable systemd timer
5. **Monitoring:** Prometheus metrics for NFS and Garage health (already exposing on port 3903)
6. **Increase Zephyr Zone:** Add storage to zephyr zone to balance cluster capacity (currently at 100% utilization)
7. **S3 CSI Driver:** Install for POSIX-compatible S3 mounting (Phase 2)
8. **K8s Storage Classes:** Apply manifests to cluster

## See Also

- [Garage Deployment Status](garage-deployment-status.md)
- [Nix Binary Cache](nix-cache-deployment-status.md)
- [Roadmap](ROADMAP.md)
