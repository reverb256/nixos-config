# Kubernetes HA Migration Plan

**Status:** 📋 Planned | **Created:** 2026-03-19 | **Target:** 3-Node HA Control Plane

---

## Executive Summary

Migrate the Kubernetes cluster from a single-node control plane (Zephyr only) to a 3-node highly available control plane spanning Zephyr, Nexus, and Sentry.

**Current State:** Single point of failure - only Zephyr has functional etcd
**Target State:** 3-node HA with etcd quorum, VIP failover, and multi-master API servers

---

## Current State Analysis

### etcd Cluster Status

```bash
$ etcdctl member list
e054b3a350f6bc1, started, zephyr, http://10.1.1.110:2380
```

**Only ONE member** - Nexus and Sentry etcd are dead/inactive.

### Control Plane Component Status

| Node | etcd | API Server | Scheduler | Controller | In Cluster |
|------|------|-----------|-----------|------------|------------|
| Zephyr | ✅ Running | ✅ Running | ✅ Running | ✅ Running | ✅ Yes |
| Nexus | ❌ Dead | ✅ Running (orphaned) | ✅ Running (orphaned) | ✅ Running (orphaned) | ❌ No |
| Sentry | ❌ Dead | ✅ Running (orphaned) | ✅ Running (orphaned) | ✅ Running (orphaned) | ❌ No |

### Root Cause

The `etcdClusterMembers` option in `modules/services/kubernetes.nix` is empty by default:

```nix
etcdClusterMembers = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = [ ];  # ← EMPTY!
};
```

---

## Migration Plan

### Phase 1: Preparation (15 min)

**Objective:** Safely prepare for HA migration

1. **Backup etcd data from Zephyr:**
```bash
ssh zephyr "ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-\$(date +%Y%m%d-%H%M).db"
```

2. **Document current cluster state:**
```bash
kubectl get nodes -o wide > /tmp/nodes-before.txt
kubectl get pods -A > /tmp/pods-before.txt
ETCDCTL_API=3 etcdctl member list > /tmp/etcd-before.txt
```

3. **Verify network connectivity:**
```bash
# Test etcd peer ports
for ip in 10.1.1.110 10.1.1.120 10.1.1.140; do
  nc -zv $ip 2380  # etcd peer port
  nc -zv $ip 2379  # etcd client port
done
```

### Phase 2: Configure etcd Cluster (30 min)

**Objective:** Add Nexus and Sentry to etcd cluster

**Update `modules/services/kubernetes.nix`:**

```nix
services.kubernetes-module = {
  enable = true;

  # etcd HA cluster configuration
  etcdClusterMembers = [
    "zephyr=http://10.1.1.110:2380"
    "nexus=http://10.1.1.120:2380"
    "sentry=http://10.1.1.140:2380"
  ];

  # Per-node settings (configured in host configs)
  # Zephyr: etcdName = "zephyr", etcdInitialState = "existing"
  # Nexus:  etcdName = "nexus", etcdInitialState = "existing"
  # Sentry: etcdName = "sentry", etcdInitialState = "existing"
};
```

**Host-specific configurations:**

**Zephyr (`hosts/zephyr/configuration.nix`):**
```nix
services.kubernetes-module = {
  enable = true;
  roles = ["master" "node"];
  etcdName = "zephyr";
  etcdInitialState = "existing";  # Already has data
  etcdListenHost = "10.1.1.110";
};
```

**Nexus (`hosts/nexus/configuration.nix`):**
```nix
services.kubernetes-module = {
  enable = true;
  roles = ["master" "node"];
  etcdName = "nexus";
  etcdInitialState = "existing";  # Joining existing cluster
  etcdListenHost = "10.1.1.120";
};
```

**Sentry (`hosts/sentry/configuration.nix`):**
```nix
services.kubernetes-module = {
  enable = true;
  roles = ["master" "node"];
  etcdName = "sentry";
  etcdInitialState = "existing";  # Joining existing cluster
  etcdListenHost = "10.1.1.140";
};
```

### Phase 3: Deployment (20 min)

**Objective:** Apply configuration to all nodes

```bash
# Validate configuration
just check

# Deploy to all nodes
just deploy
```

**Expected behavior:**
- Zephyr: Reconfigures etcd to accept Nexus/Sentry
- Nexus: Starts etcd and joins cluster
- Sentry: Starts etcd and joins cluster

### Phase 4: Verification (15 min)

**Objective:** Verify HA cluster is functional

1. **Check etcd cluster membership:**
```bash
ETCDCTL_API=3 etcdctl member list
# Expected: 3 members (zephyr, nexus, sentry)
```

2. **Check etcd health:**
```bash
ETCDCTL_API=3 etcdctl endpoint health --endpoints=http://10.1.1.110:2379,http://10.1.1.120:2379,http://10.1.1.140:2379
# Expected: All healthy
```

3. **Check Kubernetes nodes:**
```bash
kubectl get nodes
# Expected: All nodes Ready, 3 with control-plane role
```

4. **Check API server endpoints:**
```bash
kubectl get endpoints kube-apiserver -n kube-system
# Expected: 3 endpoints (one per control plane node)
```

### Phase 5: Failover Testing (20 min)

**Objective:** Verify VIP and control plane failover

1. **Test VIP failover:**
```bash
# Check current VIP owner
ip addr show | grep "10.1.1.100"

# Stop API server on Zephyr
ssh zephyr "systemctl stop kube-apiserver"

# Verify VIP moved to Nexus or Sentry
ip addr show | grep "10.1.1.100"

# Test cluster functionality
kubectl get nodes

# Restart Zephyr API server
ssh zephyr "systemctl start kube-apiserver"
```

2. **Verify quorum maintenance:**
```bash
# Cluster should remain functional with 2/3 etcd members
kubectl get pods -A
```

---

## Rollback Plan

If migration fails, rollback steps:

1. **Remove etcdClusterMembers** from kubernetes.nix (set back to `[]`)
2. **Stop etcd on Nexus/Sentry:**
```bash
ssh nexus "systemctl disable --now etcd"
ssh sentry "systemctl disable --now etcd"
```
3. **Deploy:** `just deploy`
4. **Verify:** Check cluster returns to single-node state

---

## Success Criteria

Migration is successful when:

- [ ] etcd cluster has 3 members
- [ ] All 3 nodes show as control-plane in `kubectl get nodes`
- [ ] API server endpoints show 3 addresses
- [ ] VIP failover works (stopping Zephyr API server moves VIP)
- [ ] Cluster remains functional with 2/3 nodes
- [ ] All existing pods continue running

---

## Estimated Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Preparation | 15 min | None |
| Phase 2: Configuration | 30 min | Phase 1 complete |
| Phase 3: Deployment | 20 min | Phase 2 complete |
| Phase 4: Verification | 15 min | Phase 3 complete |
| Phase 5: Testing | 20 min | Phase 4 complete |
| **Total** | **~100 min** | |

---

## References

- [Control Plane Architecture](../kubernetes/control-plane-architecture.md)
- [Kubernetes etcd HA](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
- [NixOS Kubernetes Options](https://search.nixos.org/options?query=etcd)

---

**Last Updated:** 2026-03-19
**Status:** 📋 Planned - Not yet started
