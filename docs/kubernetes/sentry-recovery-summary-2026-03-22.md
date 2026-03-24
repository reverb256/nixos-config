# Sentry Node Recovery Summary

**Date:** 2026-03-22 20:42-20:47 UTC
**Issue:** etcd raft log corruption preventing sentry node from joining cluster
**Status:** ✅ **FULLY RECOVERED**

---

## Problem

Sentry node (10.1.1.140) was in NotReady state due to etcd data corruption:
- **Root Cause:** etcd raft log index mismatch (cluster at index 339866, sentry at index 0)
- **Error:** `panic: tocommit(339866) is out of range [lastIndex(0)]`
- **Impact:** kube-apiserver couldn't start, kubelet couldn't register node, Caddy ingress pod stuck in Terminating

## Recovery Steps

### 1. Identified Corruption (20:35 UTC)
- Checked sentry node status: NotReady
- Examined kubelet logs: TLS timeout connecting to API server
- Checked API server: Failed to connect to local etcd
- Found etcd panic in logs: Raft log corruption

### 2. Stopped Sentry Services (20:40 UTC)
```bash
ssh sentry "sudo systemctl stop kube-apiserver"
ssh sentry "sudo systemctl stop kube-controller-manager"
ssh sentry "sudo systemctl stop kube-scheduler"
ssh sentry "sudo systemctl stop kubelet"
ssh sentry "sudo systemctl stop etcd"
```

### 3. Removed Sentry from etcd Cluster (20:42 UTC)
```bash
ssh zephyr "sudo etcdctl member list \
  --endpoints=http://127.0.0.1:2379"
# Found sentry member ID: 343d172959332711

ssh zephyr "sudo etcdctl member remove 343d172959332711 \
  --endpoints=http://127.0.0.1:2379"
# Result: Member removed from cluster c09bb4586132a4e6
```

### 4. Wiped Sentry etcd Data (20:44 UTC)
```bash
ssh sentry "sudo find /var/lib/etcd/ -mindepth 1 -delete"
# Result: All corrupted data removed
```

### 5. Re-added Sentry to Cluster (20:44 UTC)
```bash
ssh zephyr "sudo etcdctl member add sentry \
  --endpoints=http://127.0.0.1:2379 \
  --peer-urls=http://10.1.1.140:2380"
# Result: New member ID 217c862ba6b3ddfc added
```

### 6. Started Sentry Services (20:44-20:45 UTC)
```bash
ssh sentry "sudo systemctl start etcd"
ssh sentry "sudo systemctl start kubelet"
ssh sentry "sudo systemctl start kube-apiserver"
ssh sentry "sudo systemctl start kube-controller-manager"
ssh sentry "sudo systemctl start kube-scheduler"
```

## Recovery Results

### etcd Cluster
✅ **All 3 members healthy and synced**
```
e054b3a350f6bc1, started, zephyr, http://10.1.1.110:2380
217c862ba6b3ddfc, started, sentry, http://10.1.1.140:2380 (NEW)
8a4959715f53504c, started, nexus, http://10.1.1.120:2380
```

### Kubernetes Cluster
✅ **All 4 nodes Ready**
```
NAME     STATUS   ROLES    AGE     VERSION
forge    Ready    <none>   5h39m   v1.35.2
nexus    Ready    <none>   5h41m   v1.35.2
sentry   Ready    <none>   6h      v1.35.2
zephyr   Ready    <none>   5h46m   v1.35.2
```

### Caddy Ingress Controller
✅ **All 3 pods operational (DaemonSet)**
```
NAME                  READY   STATUS    RESTARTS   AGE     NODE
caddy-ingress-bxsnv   1/1     Running   0          38m     nexus
caddy-ingress-fl8qn   1/1     Running   0          38m     forge
caddy-ingress-mqpwr   1/1     Running   0          2m14s   sentry
```

## Timeline

| Time (UTC) | Event |
|-------------|-------|
| 20:19 | Sentry etcd first started after reboot |
| 20:33 | Sentry kubelet restarted |
| 20:34 | Sentry API server crashed (etcd connection refused) |
| 20:35 | Sentry etcd panic (raft log corruption discovered) |
| 20:36 | Incident documented, recovery plan created |
| 20:40 | All sentry Kubernetes services stopped |
| 20:42 | Sentry removed from etcd cluster (ID: 343d172959332711) |
| 20:44 | Sentry etcd data wiped |
| 20:44 | Sentry re-added to etcd cluster (new ID: 217c862ba6b3ddfc) |
| 20:44 | Sentry etcd started, joined cluster successfully |
| 20:44 | Sentry Kubernetes services started |
| 20:45 | Sentry node Ready |
| 20:45 | Caddy ingress pod on sentry Running and Ready |
| 20:46 | Zephyr API server restarted (automatic recovery) |
| 20:47 | Full cluster verification complete |

## Key Learnings

1. **HTTP vs HTTPS**: NixOS etcd module uses HTTP for peer communication, not HTTPS. Use `--endpoints=http://127.0.0.1:2379` for etcdctl.

2. **Certificate Paths**: Actual certificates are in `/var/lib/kubernetes/secrets/`, not `/etc/kubernetes/pki/`.

3. **Member IDs Change**: When re-adding a node to etcd, it gets a new member ID:
   - Old: `343d172959332711`
   - New: `217c862ba6b3ddfc`

4. **No NixOS Rebuild Needed**: The etcd cluster reconfiguration worked dynamically without requiring a NixOS rebuild.

5. **Quick Recovery**: Total recovery time was **3 minutes** (20:42-20:45 UTC) with zero data loss.

6. **Cluster Resilience**: The 3-node etcd cluster maintained quorum (2/3 members) throughout the recovery, keeping the control plane operational.

## Verification

All systems verified operational:
- ✅ etcd cluster health (3/3 members)
- ✅ Kubernetes nodes (4/4 Ready)
- ✅ Control plane components (API server, scheduler, controller-manager)
- ✅ Caddy ingress controller (3/3 pods)
- ✅ Pod scheduling and deployment
- ✅ Service discovery and DNS

## Documentation

- **Incident Report:** `/etc/nixos/docs/kubernetes/sentry-etcd-corruption-2026-03-22.md`
- **Caddy Test Report:** `/etc/nixos/kubernetes-manifests/ingress/TEST-REPORT-2026-03-22.md`
- **STATUS.md:** Updated with recovery completion

---

**Status:** ✅ **RECOVERY COMPLETE** - All systems fully operational
**Recovery Time:** 3 minutes (active work)
**Total Downtime:** ~10 minutes (sentry node only, cluster remained operational)
**Data Loss:** None
**Next Steps:** Monitor sentry node for 24 hours to ensure stability
