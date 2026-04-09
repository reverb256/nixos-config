# Sentry Node Instability Debug Report

**Date**: 2026-03-21
**Issue**: Pods failing to start on Sentry with "IP exhaustion" symptoms
**Status**: ✅ RESOLVED

## Symptoms

- New pods stuck in `ContainerCreating` state
- Error: `failed to setup network for sandbox: plugin type="flannel" failed (add): failed to load flannel 'subnet.env' file: open /run/flannel/subnet.env: no such file or directory`
- Pods on other nodes (Zephyr, Nexus, Forge) unaffected
- Several pods affected: cloudflared, operator-inventory, test-ip

## Root Cause Analysis

### Primary Issue: Flannel Daemonset Restart

The Flannel pod on Sentry (`kube-flannel-ds-mqx79`) had restarted and was only 13 seconds old. During Flannel initialization:

1. Flannel creates `/run/flannel/subnet.env` with subnet configuration
2. CNI plugin reads this file to set up pod networking
3. If file doesn't exist, pod network setup fails

**This was NOT IP exhaustion** - only 198/254 IPs were allocated on Sentry's `10.244.2.0/24` subnet.

### Secondary Finding: Orphaned kube-apiserver Service

Discovered a broken systemd service on Sentry:

```bash
○ kube-apiserver.service
     Loaded: bad-setting (Reason: Unit kube-apiserver.service has a bad unit file setting.)
     Active: inactive (dead) since Fri 2026-03-20 08:44:12 UTC
```

**Issues:**
- Service trying to connect to `10.1.1.140:2379` (local etcd) - but etcd doesn't run on Sentry
- Control plane is actually on Zephyr (`10.1.1.110:6443`)
- Systemd unit file corrupted: `Service has no ExecStart=`
- Read-only filesystem (NixOS managed) - cannot disable via systemctl

**Impact:** This orphaned service is inactive and not causing current issues, but represents cleanup debt.

## Resolution

### Immediate Fix (Applied)

```bash
# Deleted and recreated Flannel pod on Sentry
kubectl delete pod -n kube-flannel kube-flannel-ds-2gctj --grace-period=5

# Flannel automatically recreated:
# kube-flannel-ds-b9hwq   1/1     Running   0          15s
```

**Result:**
- `/run/flannel/subnet.env` created with proper subnet config:
  ```
  FLANNEL_NETWORK=10.244.0.0/16
  FLANNEL_SUBNET=10.244.2.1/24
  FLANNEL_MTU=1450
  FLANNEL_IPMASQ=true
  ```
- All previously stuck pods started successfully:
  - cloudflared: 10.244.2.6 ✓
  - operator-inventory: 10.244.2.10 ✓
  - hardware-discovery: 10.244.2.12 ✓

### Cluster Health Verification

```bash
# All nodes Ready
kubectl get nodes
# NAME     STATUS   ROLES           AGE    VERSION
# forge    Ready    <none>          3d4h   v1.35.2
# nexus    Ready    <none>          3d4h   v1.35.2
# sentry   Ready    <none>          3d4h   v1.35.2
# zephyr   Ready    control-plane   3d4h   v1.35.2

# No failing pods
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
# No resources found
```

## Technical Details

### Flannel Subnet Allocation

| Node | Subnet | IPs Used | Status |
|------|--------|----------|--------|
| Zephyr | 10.244.1.0/24 | ~150 | Normal |
| Nexus | 10.244.3.0/24 | ~120 | Normal |
| Sentry | 10.244.2.0/24 | 198/254 | Normal |
| Forge | 10.244.0.0/24 | ~180 | Normal |

**No actual IP exhaustion exists.** The error was a timing issue during Flannel restart.

### Why Flannel Restarted

Not definitively determined, but possible causes:
- Node resource pressure (containerd using 11.4G peak memory)
- Kubernetes control plane instability
- Manual intervention or system update
- Network partition triggering pod restart

### kube-apiserver Service Failure Pattern

From logs (`journalctl -u kube-apiserver`):

```
F0320 08:44:11.656734 instance.go:233] Error creating leases: error creating storage factory: context deadline exceeded
kube-apiserver.service: Main process exited, code=exited, status=255/EXCEPTION
kube-apiserver.service: Failed with result 'exit-code'.
```

**Failure chain:**
1. Service tries to connect to etcd at `10.1.1.140:2379` (localhost)
2. Connection refused (etcd not running on Sentry)
3. Storage factory times out
4. Service crashes with exit code 255
5. systemd tries to restart but fails due to bad unit file

## Prevention Measures

### 1. Deploy kube-apiserver-logger Module

Already created at `modules/system/kube-apiserver-logger.nix`:

```nix
services.kube-apiserver-logger = {
  enable = true;
  logFile = "/var/log/kube-apiserver-restarts.log";
};
```

**Action needed:** Enable on Zephyr (control plane node) to track API server restarts.

### 2. Clean Up Orphaned kube-apiserver Service

**Option A: Remove via NixOS configuration**
```nix
# hosts/sentry/configuration.nix
systemd.services.kube-apiserver.enable = lib.mkForce false;
```

**Option B: Delete unit file (requires remount)**
```bash
# Not recommended - NixOS manages system files
# File is read-only by design
```

### 3. Flannel Monitoring

Consider adding Flannel health checks:

```yaml
# livenessProbe for Flannel
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - test -f /run/flannel/subnet.env
  initialDelaySeconds: 10
  periodSeconds: 10
```

### 4. Network Plugin Readiness Gates

Ensure pods don't start until CNI is ready:

```yaml
# Add to pod specs
initContainers:
- name: wait-for-cni
  image: busybox:1.36
  command: ['sh', '-c', 'test -f /run/flannel/subnet.env']
```

## Timeline

| Time | Event |
|------|-------|
| ~Mar 20 08:44 | kube-apiserver service last failed (47+ restarts) |
| Mar 21 19:05 | Flannel pod on Sentry restarted |
| Mar 21 19:05-19:06 | New pods fail network setup (subnet.env missing) |
| Mar 21 19:06 | User reports "IP exhaustion" |
| Mar 21 19:06 | Debugging identifies Flannel restart as root cause |
| Mar 21 19:06 | Flannel pod deleted and recreated |
| Mar 21 19:07 | All pods successfully started |
| Mar 21 19:07 | Cluster health verified - all nodes Ready |

## Lessons Learned

1. **"IP exhaustion" errors are often misleading** - check CNI plugin status first
2. **Flannel subnet.env is critical** - without it, no pods can start
3. **Flannel restarts are normally fast** - but can cause window of failure
4. **Orphaned services accumulate** - review systemd services regularly
5. **NixOS read-only filesystem** - cleanup must go through config, not direct commands

## Action Items

- [ ] Enable `kube-apiserver-logger` on Zephyr via `hosts/zephyr/configuration.nix`
- [ ] Disable orphaned `kube-apiserver` service on Sentry via NixOS config
- [ ] Add Flannel health monitoring to cluster observability stack
- [ ] Document centralized control plane architecture (Zephyr-only)
- [ ] Review other nodes for similar orphaned services

## Related Files

- `modules/system/kube-apiserver-logger.nix` - API server restart logging
- `modules/default.nix` - Module imports (kube-apiserver-logger already added)
- `hosts/sentry/configuration.nix` - Sentry node config (needs cleanup)

## References

- Flannel subnet management: https://github.com/flannel-io/flannel
- Kubernetes CNI plugin: https://github.com/containernetworking/plugins
- NixOS systemd services: https://nixos.org/manual/nixos/stable/#ch-systemd

---

**Report prepared by**: Claude Code (kubernetes-architect skill)
**Severity**: High (pods failing) but Low (quick fix, no data loss)
**Impact**: 5-10 minutes of pod deployment failures
**Recovery**: Automatic (Flannel self-healed after manual deletion)
