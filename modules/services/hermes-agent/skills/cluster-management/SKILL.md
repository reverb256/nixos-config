---
name: cluster-management
description: Manage the 4-host NixOS cluster (zephyr, nexus, forge, sentry)
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [Cluster, NixOS, Colmena, Multi-host]
---

# NixOS Cluster Management

## Cluster Overview

| Host | IP | Role | Hardware |
|------|-------|-------------|------------------|
| Zephyr | 10.1.1.110 | Control plane, AI Gateway, Gaming | RTX 3090 |
| Nexus | 10.1.1.120 | Storage, GPU | RTX 3090, 8TB storage |
| Forge | 10.1.1.130 | GPU compute, mining | RTX 3090, RX 7900 |
| Sentry | 10.1.1.140 | Monitoring, logging | - |

## Multi-Host Commands

### Check all hosts
```bash
for host in zephyr nexus forge sentry; do
  ssh $host "hostname && uname -r"
done
```

### Run command on all hosts
```bash
for host in zephyr nexus forge sentry; do
  ssh $host "nixos-version"
done
```

### Colmena Deployment
```bash
# Build all hosts
nix run .#apps.x86_64-linux.colmena -- build

# Deploy to specific host
nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Deploy to all hosts
just deploy
```

## Service Health Checks

```bash
# AI Gateway
curl http://10.1.1.110:8080/health

# Qdrant
curl http://10.1.1.110:6333/

# Prometheus
curl http://10.1.1.140:9090/-/healthy
```

## Storage Access

```bash
# Garage S3 (Nexus)
s3cmd ls s3://hermes-storage

# NFS mounts
df -h | grep nfs
```

## Monitoring

- Grafana: http://10.1.1.140:3000
- Prometheus: http://10.1.1.140:9090
- Loki: http://10.1.1.140:3100

## Safety

Before cluster-wide changes:
1. Test on one node first
2. Have rollback plan ready
3. Monitor logs during deployment
