# Garage S3-Compatible Object Storage - Deployment Status

**Last Updated:** 2026-03-13
**Status:** Partial Deployment - Sentry Only

## Summary

Garage is a self-hosted S3-compatible distributed object storage system designed for multi-node deployments.

## Current Deployment Status

| Node | IP | Status | Notes |
|------|-----|--------|-------|
| **Sentry** | 10.1.1.140 | ✅ Running | Active, data in `/storage/garage` |
| **Nexus** | 10.1.1.120 | ❌ Not Deployed | Module enabled but service not created |
| **Zephyr** | 10.1.1.110 | ❌ Not Deployed | Module enabled but service not created |

## Module Configuration

### Location
- **Module:** `modules/services/garage.nix`
- **Import:** Included in `modules/default.nix`

### Options
```nix
services.garage-cluster = {
  enable = true;
  dataDir = "/var/lib/garage";  # Default, can be overridden
  replicationFactor = 3;        # 1-10, default 3
  consistencyMode = "consistent"; # "consistent" | "degraded" | "dangerous"
  rpcPort = 3901;               # RPC port for cluster communication
  s3ApiPort = 3900;             # S3 API port
  webPort = 3902;                # Web interface port
  rpcSecret = "32-hex-chars";    # Must be same on all nodes
};
```

### Per-Node Configuration
```nix
# Sentry - Local storage
services.garage-cluster = {
  enable = true;
  dataDir = "/storage/garage";
  rpcSecret = "b048d5cc40c1ccbdc9232c3830fbf0a47257c1f68b1debfadab4e6d93c38165a";
};

# Nexus - BCache storage
services.garage-cluster = {
  enable = true;
  dataDir = "/data/shared/garage";
  rpcSecret = "b048d5cc40c1ccbdc9232c3830fbf0a47257c1f68b1debfadab4e6d93c38165a";
};

# Zephyr - NFS mounted from Nexus
services.garage-cluster = {
  enable = true;
  dataDir = "/data/shared/garage";  # NFS from nexus
  rpcSecret = "b048d5cc40c1ccbdc9232c3830fbf0a47257c1f68b1debfadab4e6d93c38165a";
};
```

## Known Issues

### Issue 1: Colmena Deployment Inconsistency
**Symptom:** `nix eval` shows garage is enabled for all nodes, but colmena builds don't include the garage service for zephyr and nexus.

**Investigation:**
- `nix eval .#nixosConfigurations.zephyr.config.systemd.services.garage.enable` → `true`
- `nix eval .#nixosConfigurations.nexus.config.systemd.services.garage.enable` → `true`
- Colmena builds don't include garage.service in the system derivation

**Possible Causes:**
- Module evaluation order issue during colmena build
- Dependency on NFS mount (`/data/shared/garage` on zephyr)
- Colmena vs nixos-rebuild differences

### Issue 2: Sentry Only Running
Sentry is the only node with garage.service running. The service was deployed successfully but cluster communication is not yet configured.

## Next Steps

1. **Fix Colmena Deployment:** Investigate why colmena builds don't include garage for zephyr/nexus
2. **Cluster Layout Configuration:** Once all nodes are running, configure cluster layout:
   ```bash
   garage node id  # Get node ID for each node
   garage layout assign <node_id> -z <zone> -c <capacity>
   garage layout show
   garage layout apply --version 1
   ```
3. **Create S3 Buckets:** Set up buckets and access keys
4. **Test Replication:** Verify data is replicated across nodes

## Firewall Ports

- **3900/tcp** - S3 API
- **3901/tcp** - RPC (cluster communication)

## Data Directories

| Node | Path | Type |
|------|------|------|
| Sentry | `/storage/garage` | Local SSD |
| Nexus | `/data/shared/garage` | BCache (local) |
| Zephyr | `/data/shared/garage` | NFS from Nexus |

## References

- Garage Documentation: https://garagehq.deuxfleurs.fr/
- Configuration Reference: https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/
