# Kubernetes Networking Diagnosis - 2026-03-22

**Date**: 2026-03-22 03:28 UTC
**Severity**: 🔴 **CRITICAL** - Multiple layers of networking failures
**Status**: 📋 **DIAGNOSIS COMPLETE** - Awaiting remediation

---

## Executive Summary

The Akash provider and cluster services have **four critical networking issues** preventing external access:

1. **Cloudflare Tunnel Not Running** - No cloudflared pods in cluster
2. **Provider Service ClusterIP Only** - Not exposed externally
3. **LoadBalancer Pending** - No MetalLB configured
4. **NodePort Firewall Blocked** - Ports not accessible from outside

**Impact**: Provider is inaccessible from `https://provider.reverb256.ca` despite tunnel being "healthy" in Cloudflare dashboard.

---

## Issue #1: Cloudflare Tunnel Not Established 🔴 CRITICAL

### Current State

**Cloudflare Tunnel Status**: `healthy` (in Cloudflare dashboard)
**Tunnel ID**: `8dbfc488-5b3a-4ac5-9624-1d31e3682e4e`
**Tunnel Name**: `akash-provider-tunnel`

**Pod Status**:
```bash
kubectl get pod -n akash-services -l app.kubernetes.io/name=cloudflared
# No pods found!
```

### Root Cause

The Cloudflare tunnel is configured but **no cloudflared pods are running** in the cluster to establish the tunnel connection.

### Current Configuration

```json
{
  "service": "https://akash-provider-akash-provider-fixed.akash-services.svc.cluster.local:8443",
  "hostname": "provider.reverb256.ca",
  "originRequest": {
    "noTLSVerify": true
  }
}
```

### Why It Doesn't Work

1. **DNS Resolution**: `.svc.cluster.local` hostnames only resolve **inside** the cluster
2. **No Tunnel Connector**: Cloudflare edge has no connection path to the cluster
3. **Service Type**: Provider is ClusterIP (not accessible outside cluster anyway)

---

## Issue #2: Provider Service Not Exposed 🔴 CRITICAL

### Current Configuration

```yaml
apiVersion: v1
kind: Service
metadata:
  name: akash-provider-akash-provider-fixed
  namespace: akash-services
spec:
  type: ClusterIP  # ← PROBLEM: Not exposed externally
  ports:
    - port: 8443
      targetPort: 8443
    - port: 8444
      targetPort: 8444
  selector:
    app.kubernetes.io/name: akash-provider
```

### Problem

Service is only accessible **inside** the cluster:
- ✅ Works: `curl https://10.0.0.63:8443/status` (cluster internal)
- ❌ Fails: `curl https://provider.reverb256.ca/status` (external)

### Provider Endpoint Status

| Endpoint | Status | Notes |
|----------|--------|-------|
| `https://10.0.0.63:8443/status` | ✅ Working | Cluster-internal service IP |
| `https://provider.reverb256.ca/status` | ❌ Failing | No tunnel connection |
| `https://10.1.1.110:30843/status` | ❌ Blocked | Not exposed as NodePort |

---

## Issue #3: LoadBalancer Services Pending ⚠️ WARNING

### Affected Services

```bash
kubectl get svc -A | grep LoadBalancer
ingress-nginx    ingress-nginx-controller    LoadBalancer    <pending>
monitoring       grafana                     LoadBalancer    <pending>
```

### Root Cause

**MetalLB is not installed or configured** in the cluster.

### Impact

- Ingress controller cannot receive external traffic via LoadBalancer
- Grafana dashboard not accessible externally
- Services relying on LoadBalancer type won't work

---

## Issue #4: NodePort Firewall Blocked ⚠️ WARNING

### Exposed NodePorts

| Service | NodePort | Protocol | Status |
|---------|----------|----------|--------|
| ingress-nginx (HTTP) | 31743 | TCP | ❌ Blocked |
| ingress-nginx (HTTPS) | 30729 | TCP | ❌ Blocked |
| searxng | 30080 | TCP | ❌ Blocked |
| akash-provider | 30843 | TCP | ❌ Blocked |

### Verification

```bash
ss -tlnp | grep -E "30843|30729|31743"
# No output - ports not listening on host
```

### Root Cause

NodePorts are not exposed through host firewall or not properly configured.

---

## Certificate Status ✅ VALID

### Provider Certificate

```
Subject: CN=akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
Valid From: Mar 19 15:56:18 2026 GMT
Valid To: Mar 19 15:56:18 2027 GMT
Status: ✅ VALID (expires in 363 days)
Type: Self-signed
```

**Status**: Certificate is valid and not expiring soon.

---

## DNS Configuration

### External DNS

```
provider.reverb256.ca
  Type: CNAME
  Target: 8dbfc488-5b3a-4ac5-9624-1d31e3682e4e.cfargotunnel.com
  Proxied: false
```

**Status**: DNS correctly points to Cloudflare tunnel.

### Internal DNS

✅ CoreDNS running and resolving cluster services:
```bash
kubectl get svc -n kube-system coredns
# NAME      TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)
# coredns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP
```

---

## Network Policies

### Status

✅ Extensive network policies configured across namespaces:
- `default-deny-all` policies in place
- Specific allow policies for DNS, monitoring, egress
- Akash-services has proper allow policies

### Verification

```bash
kubectl get networkpolicy -n akash-services
# 8 policies found including allow-dns, allow-monitoring, allow-provider-egress
```

**Status**: Network policies are correctly configured and not blocking traffic.

---

## Cluster Health

### Nodes

```
NAME     STATUS   ROLES           AGE
forge    Ready    <none>          3d17h
nexus    Ready    <none>          3d17h
sentry   Ready    <none>          3d17h
zephyr   Ready    control-plane   3d18h
```

**Status**: All nodes healthy and Ready.

### Pods

```
NAMESPACE        STATUS    COUNT
akash-services   Running   8/8
ingress-nginx    Running   1/1
monitoring       Running   5/5
search           Running   3/3
```

**Status**: All pods running successfully.

---

## Root Cause Summary

### Primary Issue: Cloudflare Tunnel Architecture

The Cloudflare tunnel is configured to route traffic to a Kubernetes service hostname, but:

1. **No cloudflared pod running** - Tunnel connector not deployed
2. **Wrong service hostname** - `.svc.cluster.local` doesn't resolve outside cluster
3. **Service not exposed** - ClusterIP type prevents external access

### Secondary Issues

1. **Missing MetalLB** - LoadBalancer services don't work
2. **Firewall rules** - NodePorts not accessible from outside

---

## Remediation Plan

### Priority 1: Fix Cloudflare Tunnel (CRITICAL)

**Option A: Deploy cloudflared in cluster**
```yaml
# Deploy cloudflared as DaemonSet or Deployment
# Configure to connect to Cloudflare tunnel
# Point tunnel to cluster IP (10.0.0.63:8443)
```

**Option B: Change provider service to NodePort**
```yaml
spec:
  type: NodePort
  ports:
    - port: 8443
      nodePort: 30843  # Expose on all nodes
```

**Option C: Use hostNetwork: true**
```yaml
spec:
  hostNetwork: true  # Pod uses host network namespace
```

### Priority 2: Configure MetalLB (HIGH)

1. Install MetalLB in cluster
2. Configure IP pool for LoadBalancer services
3. Update ingress controller to use MetalLB IPs

### Priority 3: Expose NodePorts (MEDIUM)

1. Configure firewall to allow NodePorts
2. Or add NodePort to allowedTCPPorts in NixOS config

### Priority 4: Update Cloudflare Configuration (LOW)

1. Change tunnel service from hostname to IP: `https://10.1.1.120:8443`
2. Or use NodePort: `https://10.1.1.120:30843`

---

## Verification Steps

After remediation:

1. Test internal provider endpoint:
   ```bash
   curl -sk https://10.0.0.63:8443/status | jq .
   ```

2. Test external provider endpoint:
   ```bash
   curl -sk https://provider.reverb256.ca/status | jq .
   ```

3. Test NodePort access:
   ```bash
   curl -sk https://10.1.1.110:30843/status | jq .
   ```

4. Verify tunnel logs:
   ```bash
   kubectl logs -n akash-services -l app.kubernetes.io/name=cloudflared
   ```

---

## References

- **Cloudflare Tunnel Docs**: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/
- **MetalLB Documentation**: https://metallb.universe.tf/
- **Akash Provider Setup**: /etc/nixos/docs/akash-provider-configuration-complete.md
- **Cloudflare Integration**: /etc/nixos/modules/services/akash-cloudflare-integration.nix

---

**Report Generated**: 2026-03-22 03:28 UTC
**Diagnosed By**: Claude Code (Automated Network Diagnostics)
**Next Review**: After remediation implementation
