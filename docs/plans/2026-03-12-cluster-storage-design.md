# Cluster Storage Architecture Design

**Date**: 2026-03-12
**Status**: Draft
**Author**: Claude Code + j_kro

## Executive Summary

Design a unified storage architecture for a 4-node NixOS cluster (8.4TB total) supporting:
- Kubernetes workloads (PVCs, CSI driver)
- Distributed data sharing
- Backup and archival
- Log aggregation

**Key Decision**: Skip disko adoption for now. Fix existing subvolume mounts and continue with storage service setup.

---

## 1. Current Storage Inventory

### Zephyr (Control Plane) - 10.1.1.10
| Device | Size | Mount | Use |
|--------|------|-------|-----|
| nvme0n1p2 | 931GB | `/`, `/var/lib/containers` | System + container storage |
| nvme1n1p2 | 921GB | `/data` | BTRFS with subvolumes: |
| | | `/data/games` | Game installations |
| | | `/data/projects` | Project files |
| | | `/data/archive` | Long-term archive |

**Total**: ~1.9TB

### Nexus (Storage Node) - 10.1.1.20
| Device | Size | Mount | Use |
|--------|------|-------|-----|
| bcache0 | 3.6TB | `/data/*` | BTRFS subvolumes: |
| | | `/data/home` | User home directories |
| | | `/data/shared` | Cluster-wide shared data |
| | | `/data/backups` | Backup repository |
| | | `/data/media` | Media library |
| | | `/data/containers` | Container images/layers |
| nvme1n1 | 224GB | `/data/worn` | Fast SSD for hot data (formerly "worn" drive) |

**Total**: ~3.8TB + 224GB SSD

### Forge (GPU Worker) - 10.1.1.30
| Device | Size | Mount | Use |
|--------|------|-------|-----|
| sda3 | 230GB | `/`, `/nix/store` | System + Nix store |
| sdb2 | 216GB | `/home` | User home |

**Total**: ~450GB (no dedicated data storage)

### Sentry (Monitoring) - 10.1.1.40
| Device | Size | Mount | Use |
|--------|------|-------|-----|
| sda3 | 230GB | `/`, `/home` | System + monitoring data |
| sdb | 932GB | `/storage` | BTRFS with `@data` subvolume |

**Total**: ~1.2TB

### Cluster Summary
| Node | Primary Role | Raw Storage |
|------|-------------|-------------|
| Zephyr | Control | ~1.9TB |
| Nexus | Storage | ~4TB |
| Forge | GPU Compute | ~450GB |
| Sentry | Monitoring | ~1.2TB |
| **Total** | | **~8.4TB** |

---

## 2. Storage Mapping by Use Case

### 2.1 Kubernetes Container Storage
| Use Case | Storage Type | Location | Rationale |
|----------|-------------|----------|-----------|
| PVCs (stateful workloads) | Longhorn / CSI | Nexus `/data/containers` | Centralized on storage node |
| Container images | Registry | Nexus `/data/containers` | High capacity, BTRFS snapshots |
| ephemeral overlays | Local | Each node `/var/lib/containers` | Fast local access |

### 2.2 Data Storage by Access Pattern
| Access Pattern | Storage Technology | Location |
|----------------|-------------------|----------|
| **Hot / Random Write** | NFS (from Nexus) | `/data/shared` |
| **Cold / Archive** | BTRFS on Zephyr | `/data/archive` |
| **Large Binary Blobs** | Garage (S3-compatible) | Nexus `/data/shared/garage` |
| **Synced Configs** | Syncthing | Each node `/etc/nixos` |
| **Backups** | Restic + BTRFS snapshots | Nexus `/data/backups` |
| **Logs** | Loki (centralized) | Sentry `/storage/loki` |

### 2.3 Data Location Matrix

| Data Type | Primary Location | Backup | Access Method |
|-----------|------------------|--------|---------------|
| User homes | Nexus `/data/home` | `/data/backups` | NFS |
| Shared projects | Zephyr `/data/projects` | Nexus `/data/backups` | Syncthing |
| Games | Zephyr `/data/games` | None (reinstallable) | Local |
| Media library | Nexus `/data/media` | `/data/backups` | NFS |
| Container images | Nexus `/data/containers` | BTRFS snapshots | Longhorn/CSI |
| Nix configs | Each node `/etc/nixos` | Git repo | Syncthing + Git |
| Logs | Sentry `/storage/loki` | None (rotated) | Loki API |
| Metrics | Prometheus (TSDB) | None (retention 15d) | Prometheus |
| Backups | Nexus `/data/backups` | Offsite (future) | Restic |

---

## 3. Storage Services Implementation

### 3.1 NFS (Network File System)

**Purpose**: Share large datasets (homes, media) across the cluster without replication overhead.

**Exports from Nexus**:
```nix
# /etc/nixos/modules/services/nfs-server.nix (to create)
services.nfs.server = {
  enable = true;
  exports = ''
    /data/shared 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt)
    /data/home 10.1.1.0/24(rw,sync,no_subtree_check)
    /data/media 10.1.1.0/24(ro,sync,no_subtree_check)  # Read-only media share
  '';
};
```

**Client mounts**:
```nix
# On zephyr, forge, sentry
fileSystems."/data/shared" = {
  device = "10.1.1.20:/data/shared";
  fsType = "nfs";
  options = ["x-systemd.automount" "x-systemd.idle-timeout=600" "_netdev"];
};
```

### 3.2 Syncthing

**Purpose**: P2P sync of critical configs (NixOS) and selected user data.

**Configuration**:
```nix
# /etc/nixos/modules/services/syncthing.nix (to create)
services.syncthing = {
  enable = true;
  user = "j_kro";
  dataDir = "/home/j_kro/Sync";
  config = {
    devices = {
      zephyr = { id = "..."; addresses = ["10.1.1.10:22000"]; };
      nexus = { id = "..."; addresses = ["10.1.1.20:22000"]; };
      forge = { id = "..."; addresses = ["10.1.1.30:22000"]; };
      sentry = { id = "..."; addresses = ["10.1.1.40:22000"]; };
    };
    folders = {
      "nixos-configs" = {
        path = "/etc/nixos";
        devices = ["zephyr" "nexus" "forge" "sentry"];
        versioning = { type = "simple"; params = { keep = "10"; }; };
      };
    };
  };
};
```

### 3.3 Garage (S3-Compatible Object Storage)

**Purpose**: Store large binary blobs (ML models, datasets) with S3 API compatibility.

**Deployment**:
```nix
# /etc/nixos/modules/services/garage.nix (to create)
services.garage = {
  enable = true;
  package = pkgs.garage;
  settings = {
    metadata_dir = "/data/shared/garage/meta";
    data_dir = "/data/shared/garage/data";
    db_engine = "lmdb";
    replication_factor = 2;  # Start with 2, expand to 3

    rpc_bind_addr = "[::]:3901";
    rpc_public_addr = "10.1.1.20:3901";

    s3_api = {
      s3_region = "us-cluster";
      api_bind_addr = "[::]:3900";
      s3_root_domain = ".s3.cluster.local";
    };

    s3_web = {
      bind_addr = "[::]:3902";
      root_domain = ".web.cluster.local";
    };
  };
};
```

**Cluster nodes** (3-node Garage cluster):
- Zephyr: `10.1.1.10:3901`
- Nexus: `10.1.1.20:3901`
- Sentry: `10.1.1.40:3901`

**Use cases**:
- ML model storage (HuggingFace mirror)
- Dataset archives
- Large file attachments

---

## 4. Log Aggregation Strategy

### 4.1 Centralized Logging Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Zephyr    │    │   Nexus     │    │   Forge     │    │   Sentry    │
│  Promtail   │    │  Promtail   │    │  Promtail   │    │    Loki     │
│  (journald) │    │  (journald) │    │  (journald) │    │  + Grafana  │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └─────────────┘
       │                  │                  │                  │
       └──────────────────┴──────────────────┴──────────────────> │
                          10.1.1.40:3100 (Loki HTTP API)
```

### 4.2 Implementation

**Sentry (Loki server)**:
```nix
# Already exists in modules/services/monitoring/loki.nix
# Configuration to verify:
# - HTTP listen: 10.1.1.40:3100
# - Storage: /storage/loki
# - Retention: 30 days
```

**All nodes (Promtail clients)**:
```nix
# modules/services/monitoring/promtail.nix
services.promtail = {
  enable = true;
  configuration = {
    server = { listen_addr = "127.0.0.1"; http_listen_port = 9080; };
    clients = [{
      url = "http://10.1.1.40:3100/loki/api/v1/push";
    }];
    scrape_configs = [{
      job_name = "journal";
      journal = {
        max_age = "12h";
        labels = { host = "${config.networking.hostName}"; };
      };
      relabel_configs = [
        { source_labels = ["__journal__systemd_unit"]; target_label = "unit"; }
        { source_labels = ["__journal__hostname"]; target_label = "host"; }
      ];
    }];
  };
};
```

**Log file separation** (optional future enhancement):
- Application logs → Loki
- Audit logs → Separate file (`/var/log/audit/`)
- Crash dumps → Sentry (already exists via crash-watchdog)

---

## 5. Backup Strategy

### 5.1 Backup Layers

| Layer | Tool | Target | Schedule |
|-------|------|--------|----------|
| BTRFS snapshots | `btrfs-progs` | All subvolumes | Hourly (24h retention) |
| Restic | `restic` | Nexus `/data/backups` | Daily (30d retention) |
| Offsite | `rclone` | Wasabi / B2 | Weekly (90d retention) |

### 5.2 Restic Configuration

```nix
# modules/services/restic.nix (to create)
services.restic.backups = {
  daily = {
    paths = [
      "/data/home"
      "/data/shared"
      "/data/projects"  # Via NFS from zephyr
      "/etc/nixos"
    ];
    exclude = [
      "/data/home/*/Games"
      "/data/home/*/Cache"
      "/nix/store"
    ];
    repository = "sftp:backup-server:/backups/cluster";
    passwordFile = "/run/agenix/restic-password";
    timerConfig = { OnCalendar = "daily"; };
  };
};
```

---

## 6. Migration Plan

### Phase 1: Immediate (This Week)
- [x] Fix zephyr `/data` subvolume mounts
- [x] Remove duplicate sentry `/storage` declaration
- [ ] Deploy Promtail to all nodes
- [ ] Configure Loki retention policy

### Phase 2: Storage Services (Next 2 Weeks)
- [ ] Deploy NFS server on nexus
- [ ] Mount NFS shares on zephyr, forge, sentry
- [ ] Configure Syncthing for `/etc/nixos`
- [ ] Deploy Garage (3-node cluster)

### Phase 3: Kubernetes Integration (Future)
- [ ] Install Longhorn for CSI
- [ ] Configure StorageClass for `nexus-shared`
- [ ] Migrate stateful workloads to PVCs

---

## 7. open Questions

1. **Garage replication factor**: Start with 2 or go straight to 3?
   - Recommendation: Start with 2, add third node when workload demands
2. **NFS vs Garage for shared data**: Use both or consolidate?
   - Recommendation: NFS for small files, Garage for large blobs
3. **Restic backend**: Use existing storage or external provider?
   - Recommendation: Local backup to nexus `/data/backups`, then sync offsite

---

## Appendix A: Storage Performance Considerations

| Storage Type | Throughput | IOPS | Latency | Best For |
|--------------|-----------|------|---------|----------|
| Nexus bcache | ~500MB/s | ~10k | ~5ms | Large sequential |
| Zephyr NVMe | ~3GB/s | ~500k | ~0.1ms | Hot data, databases |
| Sentry SSD | ~500MB/s | ~100k | ~0.5ms | Logs, metrics |
| Forge SSD | ~500MB/s | ~100k | ~0.5ms | Scratch, temp |

---

**Document Version**: 1.0
**Next Review**: After Phase 1 completion
