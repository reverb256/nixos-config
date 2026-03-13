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
| `/data/shared` | 3.7TB | All nodes | Cluster data, shared projects |
| `/data/home` | 3.7TB | Forge, others | User home directories |
| `/data/media` | 3.7TB | Zephyr (read-only) | Media library |
| `/data/backups` | 3.7TB | Read-only | Backup archive |

**Client Mounts:**
```bash
# Zephyr
/data/media    → 10.1.1.120:/data/media    (ro)
/data/shared  → 10.1.1.120:/data/shared  (rw)

# Nexus (server)
# Local on /dev/bcache0 (SSD cache + HDD backing)

# Forge
/data/shared  → 10.1.1.120:/data/shared  (rw)
/data/home    → 10.1.1.120:/data/home    (rw)

# Sentry
/data/shared  → 10.1.1.120:/data/shared  (rw)
```

### 2. Garage (S3-Compatible Object Storage)
**Architecture:** 3-node distributed cluster
**Replication:** 3-way replication (consistent mode)
**Protocol:** S3 API (port 3900)

**Node Configuration:**
| Node | ID (short) | Storage | Capacity | Speed |
|------|------------|---------|----------|-------|
| **Zephyr** | `35ba2a0bd6db0c86` | `/data/garage` (SSD) | 4 | Fast |
| **Nexus** | TBD | `/data/shared/garage` (bcache) | 2 | Medium |
| **Sentry** | `1c10c1bfb54bcaa5` | `/storage/garage` (HDD) | 1 | Slow |

**S3 Buckets (planned):**
- `backups` - Backup archives
- `media` - Media library
- `projects` - Project data
- `logs` - Log aggregation

**Access:** S3 API at `http://10.1.1.110:3900`

### 3. Syncthing
**Purpose:** Peer-to-peer configuration sync
**Synced:** `/etc/nixos` configuration directory
**Nodes:** All 4 nodes (zephyr, nexus, forge, sentry)
**Versioning:** 10 versions retained
**Ports:** 22000 (TCP), 21027 (UDP), 8384 (Web UI)

### 4. NixOS-Share
**Purpose:** Centralized NixOS configuration read-only mount
**Server:** Zephyr
**Clients:** Nexus, Forge, Sentry
**Protocol:** NFS (read-only)
**Path:** `/etc/nixos` → mounted from Zephyr

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
| `modules/services/nfs-client.nix` | NFS client mount configuration |
| `modules/services/garage.nix` | Garage S3 object storage |
| `modules/services/syncthing.nix` | P2P config sync |
| `modules/services/nixos-share.nix` | NixOS config NFS sharing |

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

## Future Improvements

1. **Garage Multi-Region:** Add remote Garage node for disaster recovery
2. **Tiered S3 Lifecycle:** Auto-transition old data to slow tier
3. **NFS Root Squash:** Consider `no_root_squash` security implications
4. **Backup Strategy:** Implement Garage-to-NFS backup rotation
5. **Monitoring:** Prometheus metrics for NFS and Garage health

## See Also

- [Garage Deployment Status](garage-deployment-status.md)
- [Nix Binary Cache](nix-cache-deployment-status.md)
- [Roadmap](ROADMAP.md)
