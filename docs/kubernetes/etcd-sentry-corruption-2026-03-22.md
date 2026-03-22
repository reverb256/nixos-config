# etcd Corruption Incident - Sentry Node

**Date:** 2026-03-22 20:35:40 UTC
**Affected Node:** Sentry (10.1.1.140)
**Severity:** HIGH (etcd cluster degraded from 3 to 2 nodes)
**Impact:** Sentry node NotReady in Kubernetes cluster

## Incident Summary

During IOMMU kernel parameter deployment to Sentry, the etcd service failed to start due to RAFT log corruption. The etcd data directory on Sentry was either empty or corrupted during reboot, causing a panic when trying to rejoin the cluster.

## Root Cause

**Error Message:**
```
panic: tocommit(339866) is out of range [lastIndex(0)].
Was the raft log corrupted, truncated, or lost?
```

**Analysis:**
- Sentry's etcd data directory (`/var/lib/etcd/member/`) was empty after reboot
- Cluster (Zephyr, Term 7, Index 342342) expected Sentry to have data
- RAFT protocol mismatch caused panic when Sentry tried to rejoin as follower
- Trigger: System reboot during IOMMU parameter deployment

## Current State

**etcd Cluster (3-node HA):**
- ✅ Zephyr (e054b3a350f6bc1): Healthy, Leader, Term 7, Index 342342
- ✅ Nexus (8a4959715f53504c): Healthy, Follower
- ❌ Sentry (343d172959332711): **FAILED** - Cannot start, data lost

**Kubernetes Cluster:**
- ✅ Zephyr: Ready (control-plane)
- ✅ Nexus: Ready (control-plane + storage)
- ✅ Forge: Ready (gpu-compute)
- ❌ Sentry: **NotReady** (monitoring node)

**Quorum Status:** ✅ Maintained (2/3 nodes = quorum)

## Recovery Options

### Option 1: Remove and Re-add Sentry (Recommended)

1. Remove Sentry from etcd cluster:
   ```bash
   ssh zephyr "ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2379 \
     member remove 343d172959332711"
   ```

2. Remove Sentry's corrupted data:
   ```bash
   ssh sentry "sudo systemctl stop etcd"
   ssh sentry "sudo rm -rf /var/lib/etcd/member/*"
   ```

3. Re-add Sentry as new member:
   ```bash
   ssh zephyr "ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2379 \
     member add sentry --peer-urls=http://10.1.1.140:2380"
   ```

4. Restart Sentry's etcd:
   ```bash
   ssh sentry "sudo systemctl start etcd"
   ```

**Pros:** Clean slate, no data corruption risk
**Cons:** Loses Sentry's etcd data (acceptable - will resync from leader)

### Option 2: Restore from Backup (If Available)

Check for etcd snapshots on Zephyr/Nexus:
```bash
ssh zephyr "ls -lah /var/lib/etcd/member/snap/"
```

Restore snapshot to Sentry:
```bash
# Stop etcd on all nodes
# Copy snapshot to Sentry
# Restart cluster
```

**Pros:** Preserves all data
**Cons:** Requires valid backup, complex recovery

### Option 3: Leave Degraded (Temporary)

Run with 2/3 etcd nodes until maintenance window.

**Pros:** No risk during recovery
**Cons:** Reduced HA (single point of failure)

## Prevention

**DO NOT:**
- Reboot control plane nodes without stopping etcd first
- Delete etcd data directories
- Skip etcd backups

**DO:**
- Create etcd snapshots before maintenance:
  ```bash
  ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2379 snapshot save /backup/etcd-$(date +%Y%m%d).db
  ```
- Use `systemctl stop etcd` before system reboot
- Verify etcd health after maintenance:
  ```bash
  ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2379 endpoint health
  ```

## Related Documentation

- **Kubernetes Control Plane:** `docs/kubernetes/control-plane-architecture.md`
- **Cluster Status:** `STATUS.md` (Real-time cluster health)
- **Deployment Safety:** `CLAUDE.md` (Critical safety rules)

## Timeline

- **20:35:40 UTC:** Sentry reboots for IOMMU deployment
- **20:35:40 UTC:** etcd service fails to start (RAFT panic)
- **20:35:40 UTC:** Sentry node shows NotReady in Kubernetes
- **20:36:00 UTC:** Cluster stabilizes with 2/3 etcd nodes
- **Post-incident:** Documentation created, recovery planned

## Next Steps

1. ✅ Document incident (this file)
2. ⏳ Schedule maintenance window for etcd recovery
3. ⏳ Implement Option 1 (Remove and Re-add Sentry)
4. ⏳ Verify cluster health after recovery
5. ⏳ Update runbooks with etcd safety procedures

---

**Created:** 2026-03-22 20:45:00 UTC
**Status:** OPEN (Awaiting recovery)
**Owner:** j_kro
