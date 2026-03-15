# Unified Storage Architecture - Strategic Refactoring Plan

**Created:** 2026-03-15 | **Status:** Draft | **Owner:** j_kro

## Executive Summary

**Current State:** Storage configuration is scattered across 7+ modules with overlapping responsibilities, unclear separation of concerns, and no unified abstraction layer.

**Target State:** A unified storage architecture with clear layers, centralized configuration, and seamless integration across systemd, Kubernetes, and cloud providers.

---

## Current Architecture Analysis

### Module Proliferation Problem

| Module | Purpose | Overlap |
|--------|---------|---------|
| `garage.nix` | Garage S3 cluster | S3 configuration, backup |
| `backup-to-garage.nix` | Backup to Garage S3 | Duplicates backup logic |
| `rclone.nix` | Cloud sync (NEW) | S3, cloud backup |
| `nfs-server.nix` | NFS server | Shared storage |
| `nfs-client.nix` | NFS client | Mount configuration |
| `nixos-share.nix` | Config NFS sharing | NFS (special case) |
| `syncthing.nix` | P2P config sync | Backup |

**Issues:**
1. **No single source of truth** for storage backends
2. **Tight coupling** - backup logic embedded in individual modules
3. **No tier abstraction** - every module defines its own storage path
4. **Backup fragmentation** - multiple independent backup mechanisms
5. **K8s integration gaps** - manifests duplicate NixOS storage config

---

## Proposed Architecture: "Storage Profiles"

### Layered Design

```
┌─────────────────────────────────────────────────────────────────┐
│                    STORAGE ARCHITECTURE v2.0                     │
└─────────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────────┐
  │                  APPLICATION LAYER                             │
  │  (systemd services, Kubernetes pods, user applications)       │
  │  Declare: "I need tier=fast, type=object, replicas=3"        │
  └──────────────────┬───────────────────────────────────────────┘
                     │
  ┌──────────────────▼───────────────────────────────────────────┐
  │                  STORAGE PROFILES LAYER (NEW)                  │
  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │
  │  │ fast-local  │ │ shared-nfs  │ │ cold-cloud  │            │
  │  │ (SSD, NVMe) │ │ (NFS/BCache)│ │ (S3, B2)    │            │
  │  └─────────────┘ └─────────────┘ └─────────────┘            │
  │                                                                 │
  │  Profiles provide:                                               │
  │  - Capacity, performance, cost characteristics               │
  │  - Automatic routing based on data access patterns          │
  │  - Backup/retention policies by default                     │
  └──────────────────┬───────────────────────────────────────────┘
                     │
  ┌──────────────────▼───────────────────────────────────────────┐
  │                 STORAGE BACKENDS LAYER                         │
  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐         │
  │  │ Garage  │ │  NFS    │ │ Local   │ │  Cloud  │         │
  │  │ S3      │ │ v4      │ │ FS      │ │ (rclone)│         │
  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘         │
  │                                                                 │
  │  Backend drivers handle:                                          │
  │  - Connection management, health checks, failover              │
  │  - Replication, compression, encryption                       │
  └───────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Consolidate Storage Modules (Week 1-2)

### Create Unified Module Structure

```
modules/storage/
├── default.nix                 # Master import
├── profiles.nix                # Storage profiles (NEW)
├── backends/
│   ├── default.nix            # Backend aggregation
│   ├── garage.nix             # Garage S3 (refactored)
│   ├── nfs.nix                # NFS (server + client merged)
│   ├── local.nix              # Local filesystem abstraction
│   └── cloud.nix              # rclone wrapper (refactored)
├── backup/
│   ├── default.nix            # Backup coordinator (NEW)
│   ├── policies.nix           # Retention/scheduling
│   └── targets.nix            # Backup destinations
└── monitoring/
    ├── default.nix            # Storage metrics
    ├── alerts.nix             # Health checks
    └── dashboard.nix          # Grafana dashboards
```

### Migration Path

**Step 1:** Create `modules/storage/profiles.nix`

```nix
# Storage profiles provide tier-based abstraction
{
  options.storage.profiles.fast-local = {
    enable = lib.mkEnableOption "Fast local storage profile";

    tier = lib.mkOption {
      type = lib.types.enum ["fast" "medium" "slow" "cold"];
      default = "fast";
      description = "Storage tier classification";
    };

    backend = lib.mkOption {
      type = lib.types.enum ["local" "garage" "nfs" "cloud"];
      default = "local";
      description = "Primary storage backend";
    };

    # Fast local: Zephyr NVMe, direct I/O
    path = lib.mkOption {
      type = lib.types.path;
      default = "/data/fast";
      description = "Mount path for this profile";
    };

    # Automatic backup to Garage
    backup = {
      enable = lib.mkDefault true;
      schedule = lib.mkDefault "hourly";
      target = lib.mkDefault "garage:fast-backup";
    };
  };
}
```

**Step 2:** Refactor `garage.nix` to be backend-only

```nix
# Remove backup logic, focus on S3 cluster management
{ config, lib, pkgs, ... }: {
  options.storage.backends.garage = {
    enable = lib.mkEnableOption "Garage S3 backend";

    cluster = {
      nodes = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule { /* ... */ });
        description = "Garage cluster nodes";
      };

      replicationMode = lib.mkOption {
        type = lib.types.enum ["consistent" "degraded" "dangerous"];
        default = "consistent";
      };
    };

    buckets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule { /* ... */ });
      description = "S3 bucket definitions";
    };
  };
}
```

**Step 3:** Create `modules/storage/backup/default.nix`

```nix
# Unified backup coordinator
{ config, lib, pkgs, ... }: {
  options.storage.backup = {
    enable = lib.mkEnableOption "Unified backup system";

    # Define backup sources
    sources = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options.name = lib.mkOption { type = lib.types.str; };
        options.path = lib.mkOption { type = lib.types.path; };
        options.schedule = lib.mkOption { type = lib.types.str; default = "daily"; };
        options.retention = lib.mkOption { type = lib.types.str; default = "30d"; };
        options.compression = lib.mkOption { type = lib.types.bool; default = true; };
      });
    };

    # Define backup destinations
    destinations = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options.name = lib.mkOption { type = lib.types.str; };
        options.backend = lib.mkOption { type = lib.types.enum ["garage" "cloud" "nfs"]; };
        options.target = lib.mkOption { type = lib.types.str; }; # e.g., "garage:backups"
        options.encryption = lib.mkOption { type = lib.types.bool; default = true };
      });
    };

    # Backup policies
    policies = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.sources = lib.mkOption { type = lib.types.listOf lib.types.str; };
        options.destinations = lib.mkOption { type = lib.types.listOf lib.types.str; };
        options.frequency = lib.mkOption { type = lib.types.str; };
        options.retention = lib.mkOption { type = lib.types.str; };
      });
    };
  };
}
```

---

## Phase 2: Storage Tier Autoselection (Week 3-4)

### Intelligent Routing Logic

```nix
# modules/storage/router.nix (NEW)
{
  options.storage.router = {
    enable = lib.mkEnableOption "Intelligent storage routing";

    # Access pattern-based routing
    rules = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options.match = lib.mkOption {
          type = lib.types.submodule {
            options.path = lib.mkOption { type = lib.types.nullOr lib.types.str; };
            options.size = lib.mkOption { type = lib.types.nullOr lib.types.str; };
            options.access = lib.mkOption {
              type = lib.types.enum ["sequential" "random" "write-once"];
            };
            options.age = lib.mkOption { type = lib.types.str; }; # e.g., "7d", "30d"
          };
        };
        options.target = lib.mkOption { type = lib.types.str; }; # Profile to use
      });
    };

    # Example: Move files >30 days old to slow storage
    defaultRules = [
      {
        match = { age = "30d"; };
        target = "storage.profiles.cold-storage";
      }
      {
        match = { access = "write-once"; };
        target = "storage.profiles.archive";
      }
    ];
  };
}
```

---

## Phase 3: Kubernetes Integration (Week 5-6)

### Unified StorageClass Generator

```nix
# modules/storage/kubernetes.nix (NEW)
{ config, lib, pkgs, ... }: {
  config = lib.mkIf config.storage.profiles.enable {
    # Generate StorageClasses from profiles
    environment.etc."kubernetes/storage-classes.yaml".text = lib.generateStorageClasses [
      {
        name = "fast-local-ssd";
        profile = config.storage.profiles.fast-local;
        parameters = {
          tier = "fast";
          fsType = "ext4";
        };
      }
      {
        name = "shared-nfs";
        profile = config.storage.profiles.shared-nfs;
        parameters = {
          tier = "medium";
          fsType = "nfs4";
        };
      }
      {
        name = "garage-s3";
        profile = config.storage.profiles.object-storage;
        parameters = {
          tier = "object";
          s3Endpoint = "http://10.1.1.110:3900";
        };
      }
    ];
  };
}
```

### Sidecar Pattern for S3 Credentials

```nix
# Inject Garage credentials into pods via sidecar
{ config, ... }: {
  # Kubernetes manifests can reference: secretRef: garage-credentials
  # Sidecar mounts: /run/secrets/garage from /run/agenix/garage-s3
}
```

---

## Phase 4: Disaster Recovery & Compliance (Week 7-8)

### 3-2-1 Backup Strategy

``┌─────────────────────────────────────────────────────────────┐
│                   3-2-1 BACKUP STRATEGY                       │
├─────────────────────────────────────────────────────────────┤
│  3. OFFSITE (Cloud)                                           │
│     - Backblaze B2 or Wasabi (cost-effective)               │
│     - Rclone sync from Garage:backups bucket                │
│     - Immutable backups, 7-year retention                    │
│                                                              │
│  2. ONSITE (Garage distributed)                              │
│     - 3-way replication across zephyr/nexus/sentry          │
│     - Automatic healing, versioning                          │
│     - 30-day retention                                      │
│                                                              │
│  1. LOCAL (Snapshots)                                        │
│     - BTRFS snapshots on Nexus bcache0                       │
│     - Hourly automated, 24-hour retention                    │
│     - Instant recovery                                       │
└─────────────────────────────────────────────────────────────┘
```

### Compliance Framework

```nix
# modules/storage/compliance.nix (NEW)
{
  options.storage.compliance = {
    # GDPR: Right to erasure, data portability
    # HIPAA: Encryption at rest, access logs
    # SOC2: Change management, monitoring

    encryption = {
      atRest = lib.mkDefault true;  # Garage S3 encryption
      inTransit = lib.mkDefault true;  # TLS, VPN
      keyRotation = lib.mkDefault "quarterly";
    };

    retention = {
      backups = lib.mkDefault "7y";  # Cloud
      audits = lib.mkDefault "7y";
      logs = lib.mkDefault "90d";
    };

    dataClassification = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.confidentiality = lib.mkOption {
          type = lib.types.enum ["public" "internal" "confidential" "restricted"];
        };
        options.retention = lib.mkOption { type = lib.types.str; };
        options.encryption = lib.mkOption { type = lib.types.bool; };
      });
    };
  };
}
```

---

## Phase 5: Observability & Automation (Week 9-10)

### Unified Storage Dashboard

```nix
# modules/storage/monitoring/default.nix
{
  config = lib.mkIf config.storage.monitoring.enable {
    services.prometheus = {
      scrapeConfigs = [
        {
          job_name = "garage-metrics";
          static_configs = [{ targets = ["10.1.1.110:3903" "10.1.1.120:3903" "10.1.1.140:3903"]; };
        }
        {
          job_name = "nfs-exporter";
          static_configs = [{ targets = ["10.1.1.120:2050"]; }];
        }
        {
          job_name = "backup-jobs";
          static_configs = [{ targets = ["127.0.0.1:9100"]; }];  # Custom exporter
        }
      ];
    };

    # Grafana dashboard
    services.grafana.provisionedDashboards = [{
      name = "Storage Cluster Overview";
      options.path = "/etc/grafana/dashboards/storage.json";
    }];
  };
}
```

### Self-Healing Capabilities

```nix
# modules/storage/healing.nix (NEW)
{
  options.storage.healing = {
    enable = lib.mkEnableOption "Storage self-healing";

    # Detect and respond to failures
    monitors = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options.name = lib.mkOption { type = lib.types.str; };
        options.condition = lib.mkOption { type = lib.types.str; };
        options.action = lib.mkOption {
          type = lib.types.enum ["alert" "failover" "rebalance" "repair"];
        };
      });
    };

    # Example: Rebalance Garage when node fails
    defaultMonitors = [
      {
        name = "garage-node-down";
        condition = "garage_node_down()";
        action = "failover";
      }
      {
        name = "nfs-server-unreachable";
        condition = "nfs_ping_timeout() > 30s";
        action = "alert";
      }
      {
        name = "disk-space-low";
        condition = "disk_usage() > 90%";
        action = "rebalance";
      }
    ];
  };
}
```

---

## Implementation Priority

### Quick Wins (This Week)

1. **Consolidate rclone modules** - Already done with `rclone.nix`
2. **Create storage top-level directory** - `modules/storage/`
3. **Document current state** - Update `storage-architecture.md`

### High Impact (Next 2 Weeks)

1. **Create `profiles.nix`** - Tier abstraction layer
2. **Unified backup coordinator** - Single backup module
3. **Garage cluster layout optimization** - Fix zone imbalance

### Strategic (Next 2 Months)

1. **Kubernetes StorageClass generator** - K8s integration
2. **3-2-1 backup implementation** - Cloud offloading
3. **Observability dashboard** - Unified metrics

---

## Migration Path: Minimal Disruption

### Step 1: Create Parallel Structure (No Breaking Changes)

```bash
mkdir -p modules/storage/{backends,backup,monitoring}
# Keep existing modules, add new unified modules alongside
```

### Step 2: Migrate One Service at a Time

```nix
# Old way (still works)
services.backup-to-garage.enable = true;

# New way (coexist)
storage.backup = {
  enable = true;
  policies.s3-to-cloud = {
    sources = ["garage:backups"];
    destinations = ["b2:cluster-backups"];
    frequency = "daily";
  };
};
```

### Step 3: Deprecate Old Modules (After Validation)

```nix
# Add warnings, then remove after 2-release cycle
warnings = [
  "services.backup-to-garage is deprecated, use storage.backup instead"
];
```

---

## Success Metrics

| Metric | Before | Target | Measurement |
|--------|--------|--------|-------------|
| **Modules** | 7 scattered | 3 unified | File count |
| **Config LOC** | ~1500 lines | ~800 lines | `cloc modules/storage` |
| **Backup coverage** | 60% | 95% | Audit checklist |
| **Time to restore** | 2-4 hours | <30 min | Drill results |
| **K8s integration** | Manual | Declarative | `kubectl get sc` |

---

## Open Questions

1. **Migration timing** - Should we wait until K8s migration is further along?
2. **Data reorganization** - Do we restructure existing data or new data only?
3. **Cloud provider** - B2 vs Wasabi for offsite backup?
4. **Monitoring stack** - Continue with Prometheus/Grafana or switch to Loki/VictoriaLogs?

---

## Next Steps

1. **Review this plan** - Feedback and priorities
2. **Create Phase 1 PR** - `modules/storage/` skeleton
3. **Update ROADMAP.md** - Add storage track
4. **Test on non-production data** - Validate before migrating

**Last Updated:** 2026-03-15
**Discussion:** Create issue for feedback and iteration
