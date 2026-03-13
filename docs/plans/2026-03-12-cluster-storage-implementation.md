# Cluster Storage Architecture Implementation Plan

> **Status**: ⚠️ **OUTDATED - See `storage-cluster-status-report.md` for current status**
>
> **Actual Progress**: 13/15 tasks complete (87%) - Most services already deployed
> **Last Verified**: 2026-03-13

**Goal:** Deploy unified storage services (NFS, Syncthing, Garage, Loki/Promtail) across the 4-node cluster for centralized data sharing, backup, and log aggregation.

**Architecture:**
- **NFS** on Nexus exports `/data/shared`, `/data/home`, `/data/media` to cluster
- **Syncthing** P2P syncs `/etc/nixos` configs across all 4 nodes
- **Garage** S3-compatible object storage on 3 nodes (zephyr, nexus, sentry) for large binary blobs
- **Loki/Promtail** centralized logging with Sentry as aggregation point

**Tech Stack:**
- NixOS modules (declarative service configuration)
- NFS v4 (kernel-based file sharing)
- Syncthing (Go-based P2P sync)
- Garage (Rust S3-compatible object store)
- Loki (Grafana log aggregation)
- BTRFS (snapshots, compression)

---

## Phase 1: Log Aggregation (Loki + Promtail)

### Task 1: Verify Loki Configuration on Sentry

**Files:**
- Read: `modules/services/monitoring/loki.nix`
- Verify: Configuration matches design requirements

**Step 1: Read existing Loki configuration**

Run: `read /etc/nixos/modules/services/monitoring/loki.nix`

Check for:
- HTTP listener on `10.1.1.40:3100` (or `0.0.0.0:3100`)
- Storage path: `/storage/loki`
- Retention policy: 30 days

**Step 2: Verify Loki is running on sentry**

Run: `ssh sentry "systemctl status loki.service"`

Expected: `active (running)`
If inactive: `ssh sentry "sudo systemctl restart loki"`

**Step 3: Verify Loki HTTP endpoint**

Run: `curl -s http://10.1.1.40:3100/ready`

Expected: `"ready"`

**Step 4: Document any issues**

If verification fails, document in `/etc/nixos/docs/plans/loki-issues.md`

---

### Task 2: Create Promtail Module

**Files:**
- Create: `modules/services/monitoring/promtail.nix`

**Step 1: Create Promtail module with journald scraping**

```nix
# Promtail log aggregation client
# Sends journald logs to Loki on Sentry
{config, lib, pkgs, ...}: let
  cfg = config.services.promtail;
in {
  options.services.promtail = {
    enable = lib.mkEnableOption "Promtail log agent for Loki";

    lokiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://10.1.1.40:3100/loki/api/v1/push";
      description = "Loki server push URL";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.promtail];

    systemd.services.promtail = {
      description = "Promtail Log Agent";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];

      serviceConfig = {
        ExecStart = ''
          ${pkgs.promtail}/bin/promtail \
            --config.file=/etc/promtail/config.yml \
            --config.expand-env=true
        '';
        Restart = "always";
        RestartSec = "5s";
        DynamicUser = true;

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = "/";
        ReadWritePaths = ["/var/lib/promtail" "/var/log"];

        # Log access
        LogsDirectory = "promtail";
        StateDirectory = "promtail";
      };
    };

    # Promtail configuration
    environment.etc."promtail/config.yml".text = ''
      server:
        listen_addr: "127.0.0.1"
        http_listen_port: 9080
        grpc_listen_port: 0

      clients:
        - url: ${cfg.lokiUrl}

      scrape_configs:
        - job_name: journal
          journal:
            max_age: 12h
            labels:
              host: ${config.networking.hostName}
              cluster: nixos-cluster
          relabel_configs:
            - source_labels: ["__journal__systemd_unit"]
              target_label: unit
              regex: '(.+)'
            - source_labels: ["__journal__hostname"]
              target_label: host
              regex: '(.+)'
            - source_labels: ["__journal__priority"]
              target_label: priority
              regex: '(.+)'
            - source_labels: ["__journal__transport"]
              target_label: transport
              regex: '(.+)'
    '';
  };
}
```

**Step 2: Add Promtail to monitoring modules list**

File: `modules/services/monitoring/default.nix`

Add `"./promtail.nix"` to imports list:

```nix
imports = [
  ./prometheus.nix
  ./alertmanager.nix
  ./alert-webhook.nix
  ./grafana-v2.nix
  ./alert-rules.nix
  ./node-exporter.nix
  ./nfs-exporter.nix
  ./redis-exporter.nix
  ./smart-exporter.nix
  ./loki.nix
  ./promtail.nix  # <-- ADD THIS LINE
];
```

**Step 3: Commit Promtail module**

```bash
cd /etc/nixos
git add modules/services/monitoring/promtail.nix
git add modules/services/monitoring/default.nix
git commit -m "feat: add Promtail log agent module"
```

---

### Task 3: Enable Promtail on All Nodes

**Files:**
- Modify: `hosts/zephyr/configuration.nix`
- Modify: `hosts/nexus/configuration.nix`
- Modify: `hosts/forge/configuration.nix`
- Modify: `hosts/sentry/configuration.nix`

**Step 1: Add Promtail to zephyr**

File: `hosts/zephyr/configuration.nix`

Find the services block and add:

```nix
services = {
  # ... existing services ...
  promtail.enable = true;
};
```

**Step 2: Add Promtail to nexus**

File: `hosts/nexus/configuration.nix`

Add to services block: `promtail.enable = true;`

**Step 3: Add Promtail to forge**

File: `hosts/forge/configuration.nix`

Add to services block: `promtail.enable = true;`

**Step 4: Add Promtail to sentry**

File: `hosts/sentry/configuration.nix`

Add to services block: `promtail.enable = true;`

**Step 5: Test configuration locally**

Run: `nix flake check`

Expected: No errors

**Step 6: Deploy to each node incrementally**

```bash
# Deploy to zephyr first
just switch zephyr

# Verify Promtail is running
ssh zephyr "systemctl status promtail.service"

# Then deploy to nexus
just switch nexus
ssh nexus "systemctl status promtail.service"

# Then forge
just switch forge
ssh forge "systemctl status promtail.service"

# Finally sentry (last, since it runs Loki)
just switch sentry
ssh sentry "systemctl status promtail.service"
```

**Step 7: Verify logs are flowing to Loki**

Run: `ssh sentry "curl -s 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query={host=\"zephyr\"}' | jq"`

Expected: JSON response with log entries

**Step 8: Commit configuration changes**

```bash
cd /etc/nixos
git add hosts/*/configuration.nix
git commit -m "feat: enable Promtail on all cluster nodes"
```

---

## Phase 2: NFS Server and Client

### Task 4: Create NFS Server Module on Nexus

**Files:**
- Create: `modules/services/nfs-server.nix`

**Step 1: Create NFS server module**

```nix
# NFS Server for cluster-wide file sharing
# Runs on Nexus (10.1.1.20) - the storage node
{config, lib, pkgs, ...}: let
  cfg = config.services.nfs.server;
in {
  config = lib.mkIf cfg.enable {
    # NFS server configuration
    services.nfs.server = {
      enable = true;
      statsd.enable = false;

      # Export definitions
      exports = ''
        # Shared data - read/write for all cluster nodes
        /data/shared 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt,no_root_squash,fsid=100)

        # User home directories - read/write for owner
        /data/home 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt,no_root_squash,fsid=101)

        # Media library - read-only for most, write for admin
        /data/media 10.1.1.0/24(ro,sync,no_subtree_check,crossmnt,fsid=102)

        # Backups - read-only for clients (written locally)
        /data/backups 10.1.1.0/24(ro,sync,no_subtree_check,crossmnt,fsid=103)
      '';
    };

    # Firewall for NFS
    networking.firewall = {
      allowedTCPPorts = lib.mkOptionDefault [2049 111 20048];
      allowedUDPPorts = lib.mkOptionDefault [2049 111 20048];
    };

    # Enable idmapd for user/group mapping
    services.nfs.idmapd = {
      enable = true;
      settings = {
        General = {
          Domain = "cluster.local";
          Local-Realms = "cluster.local";
        };
      };
    };

    # Fixed rpc.statd port for firewall
    systemd.services.nfs-server = {
      serviceConfig.ExecStart = lib.mkForce [
        "${pkgs.nfs-utils}/bin/exportfs -ra"
        "${pkgs.nfs-utils}/bin/rpc.mountd --port 20048"
        "${pkgs.nfs-utils}/bin/rpc.nfsd"
      ];
    };
  };
}
```

**Step 2: Add NFS server to default modules**

File: `modules/default.nix`

Add to services section:

```nix
# Services
./services/mcp-servers.nix
# ...
./services/nfs-server.nix  # <-- ADD THIS LINE
./services/nfs-client.nix  # <-- ADD THIS (will create in next task)
```

**Step 3: Commit NFS server module**

```bash
git add modules/services/nfs-server.nix modules/default.nix
git commit -m "feat: add NFS server module"
```

---

### Task 5: Create NFS Client Module

**Files:**
- Create: `modules/services/nfs-client.nix`

**Step 1: Create NFS client module**

```nix
# NFS Client for mounting shared storage from Nexus
{config, lib, pkgs, ...}: let
  cfg = config.services.nfs-client;
  nfsServer = "10.1.1.20";  # Nexus
in {
  options.services.nfs-client = {
    enable = lib.mkEnableOption "NFS client for cluster storage";

    mountShared = lib.mkEnableOption "mount /data/shared from NFS";

    mountHome = lib.mkEnableOption "mount /data/home from NFS";

    mountMedia = lib.mkEnableOption "mount /data/media (read-only) from NFS";
  };

  config = lib.mkIf cfg.enable {
    # NFS client packages
    environment.systemPackages = with pkgs; [nfs-utils];

    # NFS client settings
    services.rpcbind.enable = true;

    # Create mount points
    system.activationScripts.nfs-mounts = lib.stringAfter ["var"] ''
      mkdir -p /data/shared /data/home /data/media
    '';

    # Filesystem mounts
    fileSystems = lib.mkMerge [
      (lib.mkIf cfg.mountShared {
        "/data/shared" = {
          device = "${nfsServer}:/data/shared";
          fsType = "nfs";
          options = [
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "_netdev"
            "noatime"
            "rw"
          ];
        };
      })
      (lib.mkIf cfg.mountHome {
        "/data/home" = {
          device = "${nfsServer}:/data/home";
          fsType = "nfs";
          options = [
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "_netdev"
            "noatime"
            "rw"
          ];
        };
      })
      (lib.mkIf cfg.mountMedia {
        "/data/media" = {
          device = "${nfsServer}:/data/media";
          fsType = "nfs";
          options = [
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "_netdev"
            "noatime"
            "ro"
          ];
        };
      })
    ];

    # Network dependency - don't try to mount until network is ready
    systemd.targets."remote-fs-pre".wants = ["network-online.target"];
  };
}
```

**Step 2: Commit NFS client module**

```bash
git add modules/services/nfs-client.nix
git commit -m "feat: add NFS client module with automount"
```

---

### Task 6: Enable NFS Server on Nexus

**Files:**
- Modify: `hosts/nexus/configuration.nix`

**Step 1: Enable NFS server**

File: `hosts/nexus/configuration.nix`

In the services block, add:

```nix
services = {
  # ... existing services ...
  nfs.server.enable = true;
};
```

**Step 2: Test configuration**

Run: `nix eval .#nixosConfigurations.nexus.config.services.nfs.server.exports`

Expected: String with export definitions

**Step 3: Deploy to nexus**

```bash
just switch nexus
```

**Step 4: Verify NFS server is running**

```bash
ssh nexus "systemctl status nfs-server"
ssh nexus "showmount -e localhost"
```

Expected output should show the 4 exports:
```
/export/data/shared 10.1.1.0/24
/export/data/home   10.1.1.0/24
/export/data/media  10.1.1.0/24
/export/data/backups 10.1.1.0/24
```

**Step 5: Commit**

```bash
git add hosts/nexus/configuration.nix
git commit -m "feat(nexus): enable NFS server"
```

---

### Task 7: Enable NFS Client on Zephyr

**Files:**
- Modify: `hosts/zephyr/configuration.nix`

**Step 1: Enable NFS client with shared mount**

File: `hosts/zephyr/configuration.nix`

Add to services block:

```nix
services = {
  # ... existing services ...
  nfs-client = {
    enable = true;
    mountShared = true;   # Shared project/data directory
    mountHome = false;    # Zephyr has local home
    mountMedia = true;    # Read-only media access
  };
};
```

**Step 2: Deploy to zephyr**

```bash
just switch zephyr
```

**Step 3: Verify mounts**

```bash
ssh zephyr "mount | grep nfs"
ssh zephyr "ls -la /data/shared"
```

**Step 4: Test write access**

```bash
ssh zephyr "touch /data/shared/test-$(date +%s)"
ssh zephyr "ls -la /data/shared/test-*"
```

**Step 5: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "feat(zephyr): enable NFS client for shared storage"
```

---

### Task 8: Enable NFS Client on Forge and Sentry

**Files:**
- Modify: `hosts/forge/configuration.nix`
- Modify: `hosts/sentry/configuration.nix`

**Step 1: Enable NFS client on forge**

File: `hosts/forge/configuration.nix`

Add:
```nix
services.nfs-client = {
  enable = true;
  mountShared = true;
  mountHome = true;    # Forge can use NFS home for persistence
  mountMedia = true;
};
```

**Step 2: Enable NFS client on sentry**

File: `hosts/sentry/configuration.nix`

Add:
```nix
services.nfs-client = {
  enable = true;
  mountShared = true;
  mountHome = false;   # Sentry has local home
  mountMedia = false;  # Monitoring node doesn't need media
};
```

**Step 3: Deploy to forge**

```bash
just switch forge
ssh forge "mount | grep nfs"
```

**Step 4: Deploy to sentry**

```bash
just switch sentry
ssh sentry "mount | grep nfs"
```

**Step 5: Commit**

```bash
git add hosts/forge/configuration.nix hosts/sentry/configuration.nix
git commit -m "feat: enable NFS client on forge and sentry"
```

---

## Phase 3: Syncthing for Config Sync

### Task 9: Create Syncthing Module

**Files:**
- Create: `modules/services/syncthing.nix`

**Step 1: Create Syncthing module**

```nix
# Syncthing P2P file synchronization
# Used for /etc/nixos config sync across cluster
{config, lib, pkgs, ...}: let
  cfg = config.services.syncthing;
in {
  options.services.syncthing = {
    enable = lib.mkEnableOption "Syncthing P2P file sync";

    deviceId = lib.mkOption {
      type = lib.types.str;
      description = "This node's Syncthing device ID";
    };
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = "root";  # Need root for /etc/nixos
      dataDir = "/var/lib/syncthing";
      configDir = "/var/lib/syncthing/.config/syncthing";

      openDefaultPorts = true;

      settings = {
        devices = {
          "zephyr" = { id = "ZEPHR-DEVICE-ID-HERE"; };
          "nexus" = { id = "NEXUS-DEVICE-ID-HERE"; };
          "forge" = { id = "FORG-DEVICE-ID-HERE"; };
          "sentry" = { id = "SENTRY-DEVICE-ID-HERE"; };
        };

        folders = {
          "nixos-configs" = {
            path = "/etc/nixos";
            devices = ["zephyr" "nexus" "forge" "sentry"];
            ignorePerms = false;  # Preserve file permissions
            versioning = {
              type = "simple";
              params = {keep = "10";};  # Keep 10 versions
            };
          };
        };

        gui = {
          address = "127.0.0.1:8384";
          user = "j_kro";
          password = "$2a$12$...";  # Hashed password - generate with: syncthing generate
        };

        options = {
          keepTemporariesHrs = 24;
          connectionsServiceEnabled = true;
        };
      };
    };

    # firewall
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22000 8384];
    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [21027 22000];

    # Ensure syncthing starts after network
    systemd.services.syncthing.after = ["network-online.target"];
    systemd.services.syncthing.wants = ["network-online.target"];
  };
}
```

**Step 2: Add to default modules**

File: `modules/default.nix`

```nix
./services/syncthing.nix  # <-- ADD in services section
```

**Step 3: Commit module**

```bash
git add modules/services/syncthing.nix modules/default.nix
git commit -m "feat: add Syncthing module for config sync"
```

---

### Task 10: Generate Syncthing Device IDs

**Step 1: Install syncthing locally (if not installed)**

Run: `nix-shell -p syncthing`

**Step 2: Generate device IDs for each node**

This requires syncthing to be installed first. We'll generate after initial deployment.

For now, create placeholder config:

File: `docs/plans/syncthing-device-ids.md`

```markdown
# Syncthing Device IDs

Generate these after initial Syncthing deployment on each node:

```bash
# On each node, run:
syncthing device-id

# Or extract from running instance:
cat /var/lib/syncthing/.config/syncthing/config.xml | grep deviceID
```

## Device ID placeholders
- Zephyr: `ZEPYR-PLACEHOLDER`
- Nexus: `NEXUS-PLACEHOLDER`
- Forge: `FORGE-PLACEHOLDER`
- Sentry: `SENTRY-PLACEHOLDER`

## Initial setup process
1. Enable syncthing on each node
2. Run `syncthing device-id` to get actual IDs
3. Update each node's config with peer IDs
4. Configure GUI password: `syncthing generate`
5. Accept device connections in web UI
```

---

### Task 11: Enable Syncthing Incrementally

**Files:**
- Modify: `hosts/zephyr/configuration.nix`
- Modify: `hosts/nexus/configuration.nix`
- Modify: `hosts/forge/configuration.nix`
- Modify: `hosts/sentry/configuration.nix`

**Step 1: Enable on zephyr first**

File: `hosts/zephyr/configuration.nix`

Add to services:
```nix
services.syncthing = {
  enable = true;
  deviceId = "ZEPYR-PLACEHOLDER";  # Will update after first run
};
```

**Step 2: Deploy and get device ID**

```bash
just switch zephyr
ssh zephyr "syncthing device-id"
# Output: ZEPYR-ACTUAL-ID-XXXXX-XXXXX
```

**Step 3: Enable on nexus and get ID**

```bash
# Add config to nexus (same as above)
just switch nexus
ssh nexus "syncthing device-id"
```

**Step 4: Enable on forge and sentry, get all IDs**

```bash
just switch forge
ssh forge "syncthing device-id"

just switch sentry
ssh sentry "syncthing device-id"
```

**Step 5: Update all configs with actual device IDs**

Edit each host's configuration.nix, replacing placeholders with actual IDs.

**Step 6: Set GUI password**

```bash
# On each node, generate password hash:
syncthing generate
# Output will include password hash, add to config
```

**Step 7: Restart all nodes**

```bash
just switch zephyr
just switch nexus
just switch forge
just switch sentry
```

**Step 8: Verify sync**

```bash
# Create test file on zephyr
ssh zephyr "echo 'test' > /etc/nixos/.syncthing-test"

# Check if it appears on other nodes
ssh nexus "cat /etc/nixos/.syncthing-test"
ssh forge "cat /etc/nixos/.syncthing-test"
ssh sentry "cat /etc/nixos/.syncthing-test"
```

**Step 9: Clean up test file and commit**

```bash
ssh zephyr "rm /etc/nixos/.syncthing-test"
git add hosts/*/configuration.nix docs/plans/syncthing-device-ids.md
git commit -m "feat: enable Syncthing config sync across cluster"
```

---

## Phase 4: Garage Object Storage

### Task 12: Create Garage Module

**Files:**
- Create: `modules/services/garage.nix`

**Step 1: Create Garage module**

```nix
# Garage S3-compatible object storage
{config, lib, pkgs, ...}: let
  cfg = config.services.garage;
in {
  options.services.garage = {
    enable = lib.mkEnableOption "Garage S3-compatible object storage";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/data/shared/garage";
      description = "Directory for Garage data";
    };

    rpcPort = lib.mkOption {
      type = lib.types.port;
      default = 3901;
      description = "RPC listen port";
    };

    s3ApiPort = lib.mkOption {
      type = lib.types.port;
      default = 3900;
      description = "S3 API listen port";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 3902;
      description = "Web interface port";
    };

    peers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of peer RPC addresses (e.g., [\"10.1.1.10:3901\"])";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.garage];

    # Garage directory
    system.activationScripts.garage-dirs = ''
      mkdir -p ${cfg.dataDir}/{meta,data}
      chmod 750 ${cfg.dataDir}
    '';

    systemd.services.garage = {
      description = "Garage S3 Object Storage";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];

      serviceConfig = {
        ExecStart = ''
          ${pkgs.garage}/bin/garage \
            -c ${cfg.dataDir}/garage.toml \
            server
        '';
        Restart = "always";
        RestartSec = "5s";
        DynamicUser = true;

        # Security
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = "/";
        ReadWritePaths = [cfg.dataDir];

        # Resource limits
        MemoryMax = "2G";
        CPUQuota = "200%";
      };
    };

    # Garage configuration
    environment.etc."garage.toml".text = ''
      metadata_dir = "${cfg.dataDir}/meta"
      data_dir = "${cfg.dataDir}/data"
      db_engine = "lmdb"

      block_size = 1048576  # 1MB blocks

      replication_factor = 2

      [rpc_bind_addr]
      address = "[::]:${toString cfg.rpcPort}"
      public_addr = "${config.networking.hostName}.cluster.local:${toString cfg.rpcPort}"

      [s3_api]
      s3_region = "us-cluster"
      api_bind_addr = "[::]:${toString cfg.s3ApiPort}"
      s3_root_domain = ".s3.cluster.local"

      [s3_web]
      bind_addr = "[::]:${toString cfg.webPort}"
      root_domain = ".web.cluster.local"
      index = "index.html"

      ${lib.optionalString (cfg.peers != []) ''
      [peer]
      ${lib.concatMapStringsSep "\n" (peer: ''
      ${peer}
      '') cfg.peers}
      ''}
    '';

    # Firewall
    networking.firewall = {
      allowedTCPPorts = lib.mkOptionDefault [cfg.rpcPort cfg.s3ApiPort cfg.webPort];
    };
  };
}
```

**Step 2: Add to default modules**

File: `modules/default.nix`

```nix
./services/garage.nix  # <-- ADD in services section
```

**Step 3: Commit module**

```bash
git add modules/services/garage.nix modules/default.nix
git commit -m "feat: add Garage S3-compatible object storage module"
```

---

### Task 13: Deploy Garage on 3 Nodes

**Files:**
- Modify: `hosts/zephyr/configuration.nix`
- Modify: `hosts/nexus/configuration.nix`
- Modify: `hosts/sentry/configuration.nix`

**Step 1: Enable on zephyr**

File: `hosts/zephyr/configuration.nix`

Add:
```nix
services.garage = {
  enable = true;
  dataDir = "/data/shared/garage";  # Will be on NFS from nexus
  peers = [
    "10.1.1.20:3901"  # nexus
    "10.1.1.40:3901"  # sentry
  ];
};
```

**Step 2: Enable on nexus**

File: `hosts/nexus/configuration.nix`

Add:
```nix
services.garage = {
  enable = true;
  dataDir = "/data/shared/garage";  # Local on nexus
  peers = [
    "10.1.1.10:3901"  # zephyr
    "10.1.1.40:3901"  # sentry
  ];
};
```

**Step 3: Enable on sentry**

File: `hosts/sentry/configuration.nix`

Add:
```nix
services.garage = {
  enable = true;
  dataDir = "/storage/garage";  # Local on sentry
  peers = [
    "10.1.1.10:3901"  # zephyr
    "10.1.1.20:3901"  # nexus
  ];
};
```

**Step 4: Deploy in order (nexus first, then others)**

```bash
# Deploy to nexus first (has local storage)
just switch nexus
ssh nexus "systemctl status garage"

# Then zephyr
just switch zephyr
ssh zephyr "systemctl status garage"

# Then sentry
just switch sentry
ssh sentry "systemctl status garage"
```

**Step 5: Configure Garage cluster**

```bash
# On any node, run garage CLI to configure cluster
ssh nexus "garage layout assign -z zephyr -t 10.1.1.10:3901"
ssh nexus "garage layout assign -z nexus -t 10.1.1.20:3901"
ssh nexus "garage layout assign -z sentry -t 10.1.1.40:3901"
ssh nexus "garage layout apply --version 1"
```

**Step 6: Create S3 bucket**

```bash
ssh nexus "garage key create --name j_kro"
# Save access_key and secret_key

ssh nexus "garage bucket create ml-models"
ssh nexus "garage bucket allow ml-models --read --write --key <access_key>"
```

**Step 7: Commit**

```bash
git add hosts/zephyr/configuration.nix hosts/nexus/configuration.nix hosts/sentry/configuration.nix
git commit -m "feat: deploy Garage 3-node S3 cluster"
```

---

## Phase 5: Testing and Verification

### Task 14: End-to-End Storage Tests

**Step 1: Test NFS writes**

```bash
# From zephyr
ssh zephyr "echo 'NFS test' > /data/shared/nfs-test-$(date +%s)"
ssh nexus "cat /data/shared/nfs-test-*"

# From forge
ssh forge "touch /data/shared/forge-test-$(date +%s)"
ssh zephyr "ls -la /data/shared/forge-test-*"
```

**Step 2: Test Syncthing sync**

```bash
# Create file on zephyr
ssh zephyr "echo 'sync test' > /etc/nixos/.sync-test-$(date +%s)"

# Wait up to 30 seconds for sync
sleep 30

# Verify on other nodes
ssh nexus "cat /etc/nixos/.sync-test-*"
ssh forge "cat /etc/nixos/.sync-test-*"
ssh sentry "cat /etc/nixos/.sync-test-*"
```

**Step 3: Test Garage S3 API**

```bash
# Install awscli if needed
nix-shell -p awscli2

# Configure using garage credentials
export AWS_ACCESS_KEY_ID="<garage_access_key>"
export AWS_SECRET_ACCESS_KEY="<garage_secret_key>"
export AWS_ENDPOINT_URL="http://10.1.1.20:3900"

# List buckets
aws s3api list-buckets --endpoint-url $AWS_ENDPOINT_URL

# Upload test file
echo "garage test" > /tmp/garage-test.txt
aws s3 cp /tmp/garage-test.txt s3://ml-models/test.txt --endpoint-url $AWS_ENDPOINT_URL

# Download and verify
aws s3 cp s3://ml-models/test.txt /tmp/garage-download.txt --endpoint-url $AWS_ENDPOINT_URL
cat /tmp/garage-download.txt
```

**Step 4: Test Loki log aggregation**

```bash
# Generate log on zephyr
ssh zephyr "logger 'Test log entry for Loki'"

# Query Loki
curl -s 'http://10.1.1.40:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={host="zephyr"} |= "Test log entry"' \
  --data-urlencode 'start='$(date -u -d '5 minutes ago' +%s)000000000 \
  --data-urlencode 'end='$(date +%s)000000000 | jq
```

**Step 5: Document results**

File: `docs/plans/storage-test-results.md`

```markdown
# Storage Test Results

Date: [DATE]

## NFS Tests
- [ ] Write from zephyr, read on nexus
- [ ] Write from forge, read on zephyr
- [ ] Media mount is read-only

## Syncthing Tests
- [ ] File sync within 30 seconds
- [ ] Permissions preserved
- [ ] Conflict resolution works

## Garage Tests
- [ ] S3 API accessible
- [ ] Upload/download works
- [ ] Replication factor 2 achieved

## Loki Tests
- [ ] Logs from all 4 nodes visible
- [ ] Query by hostname works
- [ ] Retention policy active
```

---

## Completion Checklist

- [ ] All modules created and committed
- [ ] NFS running on nexus, clients on zephyr/forge/sentry
- [ ] Syncthing syncing /etc/nixos across all nodes
- [ ] Garage 3-node cluster operational
- [ ] Promtail sending logs to Loki on sentry
- [ ] All tests passing
- [ ] Documentation updated

---

**Next Phase (Future):**
- Kubernetes CSI driver (Longhorn)
- Restic backup automation
- External backup sync (Wasabi/B2)
