# Calico CNI Migration Status & Issues

**Date:** 2026-03-23
**Status:** ⚠️ INCOMPLETE - Network Connectivity Issues
**Branch:** feature/x86-64-v3-migration

---

## Executive Summary

The NixOS Kubernetes module has been successfully updated for Calico CNI support, and Calico pods are running on all 4 nodes. However, **DNS and pod-to-pod connectivity are broken** due to Calico VXLAN using the Tailscale interface instead of the physical network interface.

---

## Completed Work

### ✅ NixOS Module Updates

**File:** `modules/services/kubernetes.nix`

1. **Updated cluster CIDR** from Flannel (10.244.0.0/16) to Calico (172.16.0.0/16)
   ```nix
   controllerManager = {
     clusterCidr = lib.mkForce "172.16.0.0/16";
   };
   ```

2. **Removed Flannel CNI configuration**
   - Deleted Flannel-specific settings
   - Removed Flannel network configuration

3. **Added Calico firewall ports**
   ```nix
   networking.firewall = lib.mkMerge [
     (lib.mkIf isMaster {
       allowedUDPPorts = [8472 4789]; # Calico VXLAN and BGP
     })
     {
       allowedUDPPorts = [8472 4789];
     }
   ];
   ```

### ✅ Deployment Success

- **All 4 nodes Ready:** zephyr, nexus, forge, sentry
- **Calico pods running:** 4/4 calico-node pods Running
- **CoreDNS running:** 2/2 CoreDNS pods Running
- **Flannel annotations cleaned:** Old podCIDR annotations removed

### ✅ Bug Fixes

**File:** `modules/services/monitoring/grafana.nix`
- Fixed systemd-helpers import error
- Inlined service definition to prevent module build failures

**File:** `hosts/zephyr/configuration.nix`
- Added 8GB swap file to prevent OOM kills during builds

**File:** `modules/system/distributed-builds.nix`
- Reduced zephyr max-jobs from 4 to 2 to prevent OOM

---

## Current Issues

### ❌ Critical: Network Connectivity Failure

**Symptom:** DNS resolution and pod-to-pod communication failing
```
;; connection timed out; no servers could be reached
PING 10.0.0.10 (10.0.0.10): 56 data bytes
--- 10.0.0.10 ping statistics ---
2 packets transmitted, 0 packets received, 100% packet loss
```

**Root Cause:** Calico VXLAN is using Tailscale interface (`tailscale0`, MTU 1280) instead of physical interface (`enp38s0`, MTU 1500)

```
933: vxlan.calico: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1230 qdisc noqueue
    vxlan id 4096 local 100.76.234.6 dev tailscale0 srcport 0 0 dstport 4789
```

**Impact:**
- No DNS resolution in pods
- No pod-to-pod communication
- Cluster is non-functional for workloads

---

## Root Cause Analysis

### Why Calico Uses Tailscale

Calico's IP autodetection (`IP: autodetect`) is selecting the Tailscale interface because:
1. Tailscale interface is UP and has a valid IP (100.76.234.6)
2. Calico doesn't know that Tailscale is a VPN, not the physical network
3. The VXLAN MTU (1230) is derived from Tailscale's MTU (1280) minus overhead

### Why This Breaks Networking

1. **MTU Mismatch:** VXLAN MTU 1230 is too small for proper packet fragmentation
2. **Wrong Network Path:** Traffic routed through Tailscale VPN instead of local LAN
3. **IP Range Conflict:** Tailscale IPs (100.x.x.x) conflict with Kubernetes service IPs (10.0.0.0/24)

---

## Solutions Attempted

### ❌ Attempt 1: Update IPPool CIDR
- Changed IPPool from 10.244.0.0/16 to 172.16.0.0/16
- **Result:** No improvement - issue is interface selection, not IP range

### ❌ Attempt 2: Update veth MTU
- Set `veth_mtu: "1450"` in calico-config ConfigMap
- **Result:** No improvement - VXLAN MTU still 1230

### ❌ Attempt 3: Delete and recreate VXLAN interface
- Deleted vxlan.calico interface
- **Result:** Calico recreated it with same wrong configuration

### ❌ Attempt 4: Remove old Flannel bridge
- Deleted cni0 bridge
- **Result:** No improvement - independent issue

### ❌ Attempt 5: Hard-code IP address
- Set `IP: 10.1.1.110` (zephyr's physical IP)
- **Result:** Failed - breaks other nodes with different IPs

---

## Required Solutions

### Solution 1: Configure Calico Interface Selection (RECOMMENDED)

Add to `modules/services/kubernetes.nix`:

```nix
# Add environment variable to Calico DaemonSet
environment = {
  # Specify physical interface for Calico
  IP_AUTODETECTION_METHOD = "interface=enp38s0.*";  # Zephyr
  # For multi-node clusters, use nodename-based detection:
  # IP_AUTODETECTION_METHOD = "skip-interface=^(tailscale0|docker0|podman0|cni0)";
};
```

**Implementation:**
1. Modify Calico DaemonSet manifest to include `IP_AUTODETECTION_METHOD`
2. Delete all calico-node pods to force recreation
3. Verify VXLAN uses physical interface
4. Test DNS and pod connectivity

### Solution 2: Disable Tailscale on Control Plane (WORKAROUND)

Stop Tailscale temporarily on control plane nodes:
```bash
sudo systemctl stop tailscaled
kubectl delete pod -n kube-system -l k8s-app=calico-node
```

**Drawback:** Loses Tailscale VPN access during migration

### Solution 3: Use BGP Mode Instead of VXLAN (ALTERNATIVE)

Configure Calico to use BGP peering instead of VXLAN:
```yaml
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  cidr: 10.244.0.0/16
  ipipMode: Never
  vxlanMode: Never
  natOutgoing: true
```

**Drawback:** Requires BGP peering configuration on all nodes

---

## Next Steps

### Immediate (Critical Priority)

1. **Implement Solution 1** - Configure Calico interface selection
   - Modify `modules/services/kubernetes.nix`
   - Update Calico DaemonSet with IP_AUTODETECTION_METHOD
   - Test DNS and connectivity

2. **Deploy to other nodes** - Apply Calico config to nexus, forge, sentry
   - Fix build failures (logprof.conf, pipewire-extra-config)
   - Use `--builders ''` to avoid distributed build issues

3. **Verify cluster health** - End-to-end testing
   - DNS resolution
   - Pod-to-pod communication
   - Service discovery
   - Network policies

### Short-term (This Week)

4. **Complete podCIDR migration** - Migrate from 10.244.x.x to 172.16.x.x
   - Update node podCIDRs to match Calico IPPool
   - Restart all pods to get new IPs
   - Verify no IP conflicts

5. **Update documentation** - Reflect Calico configuration
   - Update CLAUDE.md with Calico workflows
   - Update STATUS.md with new networking setup
   - Document Tailscale + Calico coexistence

### Long-term (Next Month)

6. **Consider BGP mode** - Evaluate BGP vs VXLAN for production
   - BGP: Better performance, more complex setup
   - VXLAN: Simpler, works with existing infrastructure

7. **Network policies** - Implement Calico network policies
   - Zero-trust security model
   - Namespace isolation
   - Pod-to-pod traffic controls

---

## Build Failures (Unrelated to Calico)

### Forge Node Issues

**Error:** `logprof.conf.drv` and `pipewire-extra-config.drv` failing

**Cause:** Unrelated to Calico migration - AppArmor and PipeWire configuration issues

**Impact:** Blocking deployment to forge node

**Solution:** Investigate separately - not a Calico issue

---

## Lessons Learned

1. **Interface selection matters:** Calico's IP autodetection can choose wrong interfaces
2. **MTU is critical:** VXLAN MTU must match underlying network or packets drop
3. **VPNs complicate CNI:** Tailscale/VPN interfaces confuse network plugins
4. **Test incrementally:** Should have tested single-node deployment before cluster-wide

---

## References

- **Calico Documentation:** https://docs.projectcalico.org/networking/ip-autodetection
- **VXLAN MTU Calculation:** https://docs.projectcalico.org/networking/vxlan-ip-in-udp
- **NixOS Kubernetes Module:** https://search.nixos.org/options?query=kubernetes

---

**Status:** ⚠️ BLOCKED on network connectivity fix
**Priority:** P0 - Critical cluster functionality
**ETA:** 2-4 hours to implement Solution 1 and verify
