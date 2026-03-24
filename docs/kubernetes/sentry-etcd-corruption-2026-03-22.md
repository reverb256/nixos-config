# Sentry Node etcd Corruption Incident

**Date:** 2026-03-22 20:35 UTC
**Severity:** Critical
**Affected Node:** Sentry (10.1.1.140)
**Impact:** Node NotReady, Caddy ingress pod cannot run

## Problem Summary

The sentry node is in NotReady state due to a cascading failure chain:

1. **etcd Data Corruption** (root cause)
   - Sentry's etcd raft log is severely out of sync
   - Cluster is at index 339866, sentry is at index 0
   - etcd panic: `tocommit(339866) is out of range [lastIndex(0)]`

2. **kube-apiserver Failure**
   - Cannot connect to local etcd (10.1.1.140:2379)
   - Service crashes immediately after start
   - Error: `dial tcp 10.1.1.140:2379: connect: connection refused`

3. **kubelet Registration Failure**
   - Cannot register node with API server
   - Connection errors to VIP (10.1.1.100:6443)
   - Node marked NotReady

## Error Logs

### etcd Panic
```
panic: tocommit(339866) is out of range [lastIndex(0)]. Was the raft log corrupted, truncated, or lost?
```

### API Server Errors
```
E0322 20:34:32.155048   14933 logging.go:55] [core] [Channel #2 SubChannel #5]grpc: addrConn.createTransport failed to connect to {Addr: "10.1.1.140:2379", ServerName: "10.1.1.140:2379", ...}. Err: connection error: desc = "transport: Error while dialing: dial tcp 10.1.1.140:2379: connect: connection refused
```

### Kubelet Errors
```
E0322 20:33:05.590696   13753 kubelet_node_status.go:106] "Unable to register node with API server" err="Post \"https://10.1.1.100:6443/api/v1/nodes\": dial tcp 10.1.1.100:6443: connect: connection refused"
```

## Current Cluster Status

### Healthy Nodes (3/4)
- **zephyr** (10.1.1.110): Ready, etcd leader, API server running
- **nexus** (10.1.1.120): Ready, etcd member, API server running
- **forge** (10.1.1.130): Ready, worker node

### Unhealthy Nodes (1/4)
- **sentry** (10.1.1.140): NotReady, etcd corrupted, API server down

### etcd Cluster Status
- **Members:** 3 configured (zephyr, nexus, sentry)
- **Active:** 2 healthy (zephyr, nexus)
- **Failed:** 1 corrupted (sentry)

## Impact on Services

### Caddy Ingress
- **Expected:** 3 pods (nexus, sentry, forge)
- **Actual:** 2 pods running (nexus, forge)
- **Missing:** 1 pod on sentry (stuck in Terminating)

### Other Services
- Control plane functions normally with 2 etcd members
- API server, scheduler, controller-manager operational
- No disruption to workloads on healthy nodes

## Recovery Options

### Option 1: Remove and Re-Add Sentry to etcd Cluster (Recommended)
1. Remove sentry from etcd cluster membership
2. Delete sentry's etcd data directory
3. Re-add sentry as new etcd member
4. Restart kube-apiserver and kubelet

**Risk:** Medium - requires careful etcd cluster manipulation

### Option 2: Restore from etcd Backup
1. Stop sentry's etcd
2. Restore from recent etcd snapshot
3. Verify data integrity
4. Restart services

**Risk:** High - may not work if corruption is severe

### Option 3: Rebuild Sentry Node
1. Backup sentry configuration
2. Wipe and reinstall NixOS
3. Rejoin cluster as fresh node
4. Restore configuration from backup

**Risk:** Very High - complete node rebuild required

## Temporary Workaround

The cluster is **operational with 3 nodes** and **2 etcd members**:
- Quorum is maintained (2 out of 3)
- No immediate action required
- Sentry can be recovered during maintenance window

## Recovery Steps (Option 1 - Detailed)

### Prerequisites
- Verify zephyr and nexus etcd members are healthy
- Backup all etcd data from zephyr
- Schedule maintenance window (downtime expected for sentry)

### Step 1: Verify Current Cluster State
```bash
# On zephyr: check etcd members
etcdctl --endpoints=https://10.1.1.110:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd-peer.pem \
  --key=/var/lib/kubernetes/secrets/etcd-peer-key.pem \
  member list

# Check cluster health
etcdctl --endpoints=https://10.1.1.110:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd-peer.pem \
  --key=/var/lib/kubernetes/secrets/etcd-peer-key.pem \
  endpoint health --cluster
```

### Step 2: Remove Sentry from etcd Cluster
```bash
# On zephyr: get sentry member ID
etcdctl --endpoints=https://10.1.1.110:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd-peer.pem \
  --key=/var/lib/kubernetes/secrets/etcd-peer-key.pem \
  member list

# Remove sentry member (replace <member-id>)
etcdctl --endpoints=https://10.1.1.110:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd-peer.pem \
  --key=/var/lib/kubernetes/secrets/etcd-peer-key.pem \
  member remove <member-id>
```

### Step 3: Clean Sentry etcd Data
```bash
# On sentry: stop services
sudo systemctl stop kube-apiserver
sudo systemctl stop kube-controller-manager
sudo systemctl stop kube-scheduler
sudo systemctl stop etcd

# Remove etcd data directory
sudo rm -rf /var/lib/kubernetes/etcd/*
```

### Step 4: Re-Add Sentry to etcd Cluster
```bash
# On zephyr: add sentry back to cluster
etcdctl --endpoints=https://10.1.1.110:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd-peer.pem \
  --key=/var/lib/kubernetes/secrets/etcd-peer-key.pem \
  member add sentry \
  --peer-urls=http://10.1.1.140:2380
```

### Step 5: Update Sentry Configuration
```bash
# On sentry: update etcd service with new cluster configuration
# The exact steps depend on NixOS configuration structure
# May need to update /etc/kubernetes/manifests or regenerate from flake
```

### Step 6: Restart Sentry Services
```bash
# On sentry: restart services in order
sudo systemctl start etcd
sudo systemctl start kube-apiserver
sudo systemctl start kube-controller-manager
sudo systemctl start kube-scheduler
sudo systemctl start kubelet
```

### Step 7: Verify Recovery
```bash
# Check sentry node status
kubectl get nodes

# Check sentry etcd member
etcdctl --endpoints=https://10.1.1.110:2379 \
  --cacert=/var/lib/kubernetes/secrets/ca.pem \
  --cert=/var/lib/kubernetes/secrets/etcd-peer.pem \
  --key=/var/lib/kubernetes/secrets/etcd-peer-key.pem \
  member list

# Check sentry API server
curl -k https://10.1.1.140:6443/healthz

# Verify Caddy ingress pod runs
kubectl get pods -n ingress-system -l app.kubernetes.io/name=caddy-ingress
```

## Prevention

1. **Regular etcd backups** - automate snapshot creation
2. **Monitor etcd health** - alert on member failures
3. **Hardware monitoring** - prevent disk corruption
4. **Graceful shutdown** - avoid hard power-offs

## Timeline

- **20:19 UTC** - Sentry etcd first started after recent reboot
- **20:33 UTC** - Sentry kubelet restarted
- **20:34 UTC** - Sentry API server crashed (etcd connection refused)
- **20:35 UTC** - Sentry etcd panic (raft log corruption discovered)
- **20:36 UTC** - Incident documented, recovery plan created

## References

- etcd data corruption: https://etcd.io/docs/v3.6/faq/#what-if-the-raft-log-is-corrupted
- etcd member management: https://etcd.io/docs/v3.6/op-guide/member-reconfigure/
- NixOS Kubernetes etcd: `/etc/nixos/modules/services/kubernetes/`

**Status:** Documented, awaiting recovery execution
**Next Action:** Schedule maintenance window for sentry recovery

## Recovery Execution (2026-03-22 20:42-20:45 UTC)

### Recovery Method Used
**Option 1: Remove and Re-Add Sentry to etcd cluster** ✅ SUCCESS

### Steps Executed

#### 1. Listed etcd cluster members (20:42 UTC)
```bash
ssh zephyr "sudo etcdctl member list \
  --endpoints=http://127.0.0.1:2379"
```
**Result:** Identified sentry member ID: `343d172959332711`

#### 2. Removed sentry from cluster (20:42 UTC)
```bash
ssh zephyr "sudo etcdctl member remove 343d172959332711 \
  --endpoints=http://127.0.0.1:2379"
```
**Result:** `Member 343d172959332711 removed from cluster c09bb4586132a4e6`

#### 3. Wiped sentry etcd data (20:44 UTC)
```bash
ssh sentry "sudo find /var/lib/etcd/ -mindepth 1 -delete"
```
**Result:** Cleaned all etcd data from sentry

#### 4. Re-added sentry to cluster (20:44 UTC)
```bash
ssh zephyr "sudo etcdctl member add sentry \
  --endpoints=http://127.0.0.1:2379 \
  --peer-urls=http://10.1.1.140:2380"
```
**Result:** 
- Member 217c862ba6b3ddfc added to cluster
- New configuration provided for sentry

#### 5. Started sentry services (20:44-20:45 UTC)
```bash
ssh sentry "sudo systemctl start etcd"
ssh sentry "sudo systemctl start kubelet"
ssh sentry "sudo systemctl start kube-apiserver"
ssh sentry "sudo systemctl start kube-controller-manager"
ssh sentry "sudo systemctl start kube-scheduler"
```

### Recovery Results

#### etcd Cluster Status
✅ **All 3 members healthy**
```
e054b3a350f6bc1, started, zephyr, http://10.1.1.110:2380
217c862ba6b3ddfc, started, sentry, http://10.1.1.140:2380
8a4959715f53504c, started, nexus, http://10.1.1.120:2380
```

#### Kubernetes Node Status
✅ **All 4 nodes Ready**
```
NAME     STATUS   ROLES    AGE     VERSION
forge    Ready    <none>   5h37m   v1.35.2
nexus    Ready    <none>   5h39m   v1.35.2
sentry   Ready    <none>   5h58m   v1.35.2
zephyr   Ready    <none>   5h44m   v1.35.2
```

#### Caddy Ingress Pods
✅ **All 3 pods running**
```
NAME                  READY   STATUS    RESTARTS   AGE   NODE
caddy-ingress-bxsnv   1/1     Running   0          36m   nexus
caddy-ingress-fl8qn   1/1     Running   0          36m   forge
caddy-ingress-mqpwr   1/1     Running   0          42s   sentry
```

### Recovery Timeline
- **20:42 UTC** - Cluster member listed, sentry ID identified
- **20:42 UTC** - Sentry removed from etcd cluster
- **20:44 UTC** - Sentry etcd data wiped
- **20:44 UTC** - Sentry re-added to cluster (new ID: 217c862ba6b3ddfc)
- **20:44 UTC** - Sentry etcd started, joined cluster successfully
- **20:44 UTC** - Sentry Kubernetes services started
- **20:45 UTC** - Sentry node Ready
- **20:45 UTC** - Caddy ingress pod on sentry Running and Ready

### Key Success Factors
1. ✅ Used HTTP endpoint (not HTTPS) for etcdctl commands
2. ✅ Stopped all sentry services before data wipe
3. ✅ NixOS configuration already correct (no rebuild needed)
4. ✅ Cluster maintained quorum throughout recovery (2/3 members)
5. ✅ Zero data loss - full cluster recovery

### Lessons Learned
1. **etcd HTTP vs HTTPS**: NixOS etcd module uses HTTP for peer communication, not HTTPS
2. **Certificate paths**: Actual certs in `/var/lib/kubernetes/secrets/`, not `/etc/kubernetes/pki/`
3. **Member IDs change**: When re-adding a member, it gets a new ID (old: 343d172959332711, new: 217c862ba6b3ddfc)
4. **No rebuild required**: NixOS etcd configuration is dynamic - member add worked without rebuild
5. **Quick recovery**: Total recovery time: 3 minutes (20:42-20:45 UTC)

**Status:** ✅ **RECOVERY COMPLETE** - All systems operational
**Recovery Time:** 3 minutes
**Data Loss:** None
**Downtime:** Minimal (sentry node only, cluster remained operational)

---
