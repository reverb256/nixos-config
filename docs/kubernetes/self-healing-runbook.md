# Self-Healing Runbook

**Purpose:** Recovery procedures for self-healing mechanisms in the NixOS cluster
**Last Updated:** 2026-03-14
**Cluster:** zephyr (control plane), nexus, forge, sentry (workers)

---

## Table of Contents

1. [Service Restart Recovery](#service-restart-recovery)
2. [VIP Failover Recovery](#vip-failover-recovery)
3. [Circuit Breaker Recovery](#circuit-breaker-recovery)
4. [etcd Cluster Recovery](#etcd-cluster-recovery)
5. [Storage Recovery](#storage-recovery)
6. [Network Recovery](#network-recovery)
7. [Alert Response Procedures](#alert-response-procedures)

---

## Service Restart Recovery

### Automatic Restart Policies

Most services use `Restart = "on-failure"` or `Restart = "always"`:

| Service | Restart Policy | Behavior |
|---------|---------------|----------|
| kubelet | on-failure | Restarts if crashes, 10s delay |
| kube-apiserver | on-failure | Restarts if crashes, no explicit delay |
| containerd | on-failure | Restarts if crashes |
| ai-gateway | on-failure | Restarts after 10s |
| etcd | on-failure | Restarts after 5s |
| gpu-proxy | on-failure | Restarts after 5-10s |

### Manual Recovery Steps

If a service fails to restart automatically:

```bash
# 1. Check service status
systemctl status <service-name>

# 2. View recent logs
journalctl -u <service-name> -n 50 --no-pager

# 3. Check for dependency failures
systemctl list-dependencies <service-name>

# 4. Attempt manual restart
systemctl restart <service-name>

# 5. If restart fails, check configuration
nixos-rebuild dry-build --flake .#<hostname>

# 6. Reset failure state (if stuck)
systemctl reset-failed <service-name>
systemctl start <service-name>
```

### Common Failure Patterns

**Pattern 1: Dependency Chain Failure**
```
containerd fails → kubelet fails → apiserver fails
```
**Recovery:**
```bash
# Restart in reverse dependency order
systemctl restart containerd
# Wait for containerd to be ready (up to 60s)
systemctl restart kubelet
# Wait for kubelet healthz (up to 120s)
systemctl restart kube-apiserver
```

**Pattern 2: OOM Killer**
```
Service killed due to MemoryMax limit
```
**Recovery:**
```bash
# Check memory usage
free -h
systemctl show <service-name> -p MemoryCurrent

# Temporary: Increase MemoryMax (edit service config)
# Permanent: Adjust in module config
```

---

## VIP Failover Recovery

### Keepalived VIP Architecture

```
Priority  Node     Role     VIP Behavior
──────────────────────────────────────────
110       zephyr   MASTER   Holds VIP when healthy
100       nexus    BACKUP   Takes over if zephyr fails
90        sentry   BACKUP   Last resort
──────────────────────────────────────────
VIP       10.1.1.100         Floats to highest priority
```

### Health Check Configuration

When enabled (`enableHealthCheck = true`):
- Checks `https://127.0.0.1:6443/healthz` every 2 seconds
- Requires 2 consecutive failures to reduce priority by 20
- Requires 2 consecutive successes to restore priority

### Failover Event Response

**Plasma Notification:** "Self-Healing: failover - [hostname] is now BACKUP (VIP lost)"

**Investigation Steps:**

```bash
# 1. Check which node has the VIP
ip addr show | grep "10.1.1.100"

# 2. Check keepalived status
systemctl status keepalived

# 3. Check kube-apiserver health
curl -k https://127.0.0.1:6443/healthz

# 4. Check recent keepalived logs
journalctl -u keepalived -n 50 --no-pager

# 5. Check VRRP advertisements
tcpdump -i <interface> vrrp -n -v
```

**Recovery Scenarios:**

**Scenario A: Temporary Network Glitch**
- VIP returns automatically when network recovers
- No action needed

**Scenario B: Kube-apiserver Hung**
```bash
# Restart kube-apiserver on affected node
systemctl restart kube-apiserver

# Monitor for VIP return
watch -n 2 'ip addr show | grep "10.1.1.100"'
```

**Scenario C: Node Failure**
- VIP permanently moves to next priority node
- Recover failed node hardware/network
- VIP will return when node rejoins with higher priority

### Manual VIP Recovery

```bash
# Force local node to release VIP (use carefully)
systemctl stop keepalived

# Force local node to acquire VIP (use carefully)
systemctl restart keepalived

# Change priority temporarily (emergency)
# Edit host config: services.keepalived-vip.priority = 200
# Apply: nixos-rebuild switch
```

---

## Circuit Breaker Recovery

### Circuit Breaker States

```
CLOSED (normal) → failure threshold → OPEN (blocked)
     ↑                                    ↓
     └── success threshold ← HALF_OPEN (testing)
```

### AI Gateway Circuit Breaker

**Configuration:**
- `failureThreshold`: 5 consecutive failures
- `successThreshold`: 2 consecutive successes
- `timeoutSeconds`: 60 seconds before HALF_OPEN

**Plasma Notifications:**
- "Self-Healing: circuit_breaker - Circuit breaker OPEN for [backend]" (critical)
- "Self-Healing: circuit_breaker - Circuit breaker HALF_OPEN for [backend]" (normal)
- "Self-Healing: recovery - Circuit breaker CLOSED for [backend]" (normal)

### Checking Circuit Breaker State

```bash
# 1. Via metrics endpoint
curl -s http://127.0.0.1:8080/metrics | grep circuit_breaker_state

# 2. Via health endpoint (if enabled)
curl -s http://127.0.0.1:8080/health | jq .circuit_breaker

# 3. Check backend connectivity
curl -s https://api.z.ai/v1/models -H "Authorization: Bearer <key>"

# 4. Check Redis state (if distributed)
redis-cli GET "circuit_breaker:<backend>:state"
```

### Manual Recovery

**Force Circuit Breaker Closed:**
```bash
# Option 1: Delete Redis state
redis-cli DEL "circuit_breaker:<backend>:state"
redis-cli DEL "circuit_breaker:<backend>:failures"

# Option 2: Restart AI Gateway
systemctl restart ai-gateway
```

**Investigate Backend Failure:**
```bash
# Check backend health directly
curl -v <backend-url>/health

# Check DNS resolution
nslookup <backend-hostname>

# Check network connectivity
ping -c 3 <backend-host>
traceroute <backend-host>
```

---

## etcd Cluster Recovery

### etcd Cluster Members

```
Member  Address          Peer Port  Client Port
─────────────────────────────────────────────────
zephyr  10.1.1.110:2380   2380       2379
nexus   10.1.1.120:2380   2380       2379
sentry  10.1.1.140:2380   2380       2379
```

### Quorum Requirements

- 3-node cluster: 2 nodes must be available for quorum
- If quorum is lost, etcd becomes read-only

### Checking etcd Health

```bash
# 1. Check etcd service status
systemctl status etcd

# 2. Check etcd member health
ETCDCTL_API=3 etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  endpoint health

# 3. Check cluster membership
ETCDCTL_API=3 etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  member list

# 4. Check cluster health
ETCDCTL_API=3 etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  endpoint status --write-out=table
```

### Recovery Scenarios

**Scenario A: Single Node Failure**

```bash
# On failed node, restart etcd
systemctl restart etcd

# Verify rejoin
ETCDCTL_API=3 etcdctl member list
```

**Scenario B: Quorum Loss (2 nodes down)**

```bash
# 1. Identify remaining healthy node
# 2. On healthy node, force leader election (if needed)
ETCDCTL_API=3 etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  move-leader <healthy-member-id>

# 3. Restart failed nodes one at a time
```

**Scenario C: Data Corruption**

```bash
# WARNING: Last resort - restores from snapshot
# Find latest snapshot in /var/lib/etcd/member/snapshots

ETCDCTL_API=3 etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  snapshot restore /var/lib/etcd/member/snapshots/<latest>
```

### Rebuilding a Failed Member

```bash
# 1. Stop etcd on failed node
systemctl stop etcd

# 2. Remove corrupted data
rm -rf /var/lib/etcd/member/*

# 3. Update initialClusterState to "existing" in node config
# (should already be set for non-initial nodes)

# 4. Restart etcd
systemctl start etcd

# 5. Verify rejoin
ETCDCTL_API=3 etcdctl member list
```

---

## Storage Recovery

### NFS Mount Failures

**Graceful Mount Options:**
```nix
options = [
  "soft"           # Return errors after timeout
  "timeo=50"       # 5 second timeout
  "retrans=2"      # 2 retransmission attempts
  "nofail"         # Don't fail boot if unavailable
  "bg"             # Background mounting
  "x-systemd.device-timeout=5s"   # Device timeout
  "x-systemd.mount-timeout=10s"   # Mount timeout
];
```

**Recovery Steps:**

```bash
# 1. Check mount status
findmnt | grep nfs
systemctl list-units -t mount | grep nfs

# 2. Check NFS server availability
ping -c 3 <nfs-server-host>
showmount -e <nfs-server-host>

# 3. Remount failed mount
umount <mount-point>
mount <mount-point>

# 4. Or restart mount unit
systemctl restart <mount-point>.mount

# 5. If persistent issues, check NFS server
systemctl status nfs-server
journalctl -u nfs-server -n 50
```

### Garage S3 Storage Recovery

**Checking Garage Health:**

```bash
# 1. Check Garage service
systemctl status garage

# 2. Check cluster layout
garage status

# 3. Check bucket health
garage bucket list
garage bucket info <bucket-name>

# 4. Check connectivity
curl -f http://10.1.1.110:3900/health
```

**Recovering from Node Failure:**

```bash
# 1. On remaining nodes, check cluster health
garage status

# 2. If quorum lost (RF=3, only 2 nodes available):
#    - Garage is read-only, no data loss
#    - Recover failed node to restore write capability

# 3. On recovered node, restart Garage
systemctl restart garage

# 4. Verify cluster rebalanced
garage status
```

---

## Network Recovery

### Flannel CNI Issues

**Symptoms:**
- Pods cannot communicate
- `CoreDNS` not resolving
- NodeNotReady status

**Diagnosis:**

```bash
# 1. Check Flannel daemonset
kubectl -n kube-system get pods -l app=flannel

# 2. Check Flannel logs
kubectl -n kube-system logs -l app=flannel --tail=50

# 3. Check pod network
kubectl get pods -o wide

# 4. Test pod-to-pod connectivity
kubectl exec -it <pod> -- ping <other-pod-ip>

# 5. Check node network
ip addr show flannel.1
```

**Recovery:**

```bash
# 1. Restart Flannel pods
kubectl -n kube-system delete pods -l app=flannel

# 2. If persistent issues, check CNI config
cat /etc/cni/flannel.conflist

# 3. Check firewall rules (VXLAN port 8472)
iptables -L FLANNEL-FWD -n
```

### Tailscale VPN Issues

**Diagnosis:**

```bash
# 1. Check Tailscale status
tailscale status

# 2. Check Tailscale service
systemctl status tailscaled

# 3. Check Tailscale logs
journalctl -u tailscaled -n 50

# 4. Test connectivity
ping -c 3 <tailscale-ip>
```

**Recovery:**

```bash
# 1. Restart Tailscale daemon
systemctl restart tailscaled

# 2. If stuck, force logout
# WARNING: Only if absolutely necessary
tailscale logout
tailscale up
```

---

## Alert Response Procedures

### Plasma Notification Categories

| Icon | Type | Urgency | Response Time |
|------|------|---------|---------------|
| ❌ dialog-error | failure | critical | Immediate |
| 🔄 view-refresh | restart | normal | 5 minutes |
| 🌐 network-vpn | failover | normal | 10 minutes |
| ⚠️ dialog-warning | circuit_breaker | critical | Immediate |
| 💾 drive-harddisk | resource | warning | 30 minutes |
| ✅ dialog-ok | recovery | low | Log only |

### Critical Alert Response

**1. Service Failure (critical)**
```bash
# Immediate: Check service status
systemctl status <service>

# If failed: Attempt restart
systemctl restart <service>

# If restart fails: Investigate logs
journalctl -u <service> -n 100 --no-pager

# If hardware/resource issue: Escalate
```

**2. Circuit Breaker OPEN (critical)**
```bash
# Immediate: Check backend health
curl -f <backend-url>/health

# If backend down: Fix backend or update config
# If backend up but CB wrong: Reset state
redis-cli DEL "circuit_breaker:<backend>:state"
```

**3. VIP Failover (normal)**
```bash
# Verify expected behavior (planned maintenance)
# If unexpected: Investigate losing node
```

### Resource Alerts (warning)

**High Memory Usage:**
```bash
# Check memory usage
free -h
systemd-cgtop

# Identify top consumers
ps aux --sort=-%mem | head -20

# Action: Restart memory-hungry services if safe
```

**High Disk Usage:**
```bash
# Check disk usage
df -h

# Find large files
du -sh /* 2>/dev/null | sort -hr | head -20

# Action: Clean logs, old backups, etc.
journalctl --vacuum-time=7d
```

---

## Emergency Contacts

| Role | Contact | Availability |
|------|---------|--------------|
| Cluster Admin | j_kro | On-site/Remote |
| Network Admin | j_kro | Tailscale VPN |
| Storage Admin | j_kro | Garage S3 |

---

## Runbook Maintenance

**Review Schedule:** Monthly
**Last Review:** 2026-03-14
**Next Review:** 2026-04-14

**Updates:**
- Add new self-healing mechanisms as deployed
- Document actual recovery experiences
- Update contact information

---

**Appendix A: Useful Commands**

```bash
# Quick cluster health check
kubectl get nodes
kubectl get pods --all-namespaces
systemctl status kubelet kube-apiserver etcd containerd

# Quick service status
systemctl list-units --failed

# Quick resource check
free -h
df -h
iostat -x 1 1

# Quick network check
ping -c 3 10.1.1.110  # zephyr
ping -c 3 10.1.1.120  # nexus
ping -c 3 10.1.1.130  # forge
ping -c 3 10.1.1.140  # sentry
```
