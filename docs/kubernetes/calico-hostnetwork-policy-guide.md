# Calico Network Policies and hostNetwork Pods - Complete Guide

**Date:** 2026-04-23
**Status:** Critical Issue Identified - Calico NOT Running
**Environment:** K3s v1.34.5 + NixOS

---

## Executive Summary

**CRITICAL FINDING:** Calico CNI is **NOT currently running** in this cluster. The cluster is using K3s's default CNI (likely a simple bridge/overlay), NOT Calico despite Calico manifests existing in `kubernetes-manifests/calico/`.

**Evidence:**
- No Calico pods running (`kubectl get pods -n kube-system` shows only coredns, local-path-provisioner, metrics-server, nvidia-device-plugin)
- No Calico CRDs installed (`kubectl get crd | grep calico` returns empty)
- No Tigera operator pods
- Nodes show "Unknown" status (except forge) - indicates CNI issues

---

## Why Calico Policies Don't Work with hostNetwork

### 1. **Fundamental Architecture Issue**

**hostNetwork=true means the pod uses the node's network namespace directly, bypassing the pod network overlay.**

```
Normal Pod (hostNetwork=false):
Node eth0 (10.1.1.x) → veth → pod eth0 (10.244.x.x)
                   ↑
                Calico policies apply HERE
                   (at veth interface)

hostNetwork Pod (hostNetwork=true):
Node eth0 (10.1.1.x) → pod uses this directly
                   ↑
    Calico policies DON'T apply HERE
    (policies only apply to pod network interfaces)
```

### 2. **Calico Policy Enforcement Point**

Calico enforces network policies at the **veth interface** between the node and pod network:

- **Normal pods:** Traffic flows through Calico's veth interface → policies apply
- **hostNetwork pods:** Traffic bypasses veth entirely → policies don't apply

**Key Technical Details:**

```yaml
# Calico Felix (per-node agent) enforces policies via:
- iptables rules on veth interfaces
- NOT on the host's primary network interface
- hostNetwork pods use host interface directly
```

### 3. **Why This Breaks Network Policies**

When you apply a Kubernetes NetworkPolicy or Calico GlobalNetworkPolicy:

1. **Calico Felix** translates policies into iptables rules
2. **Rules are attached to veth interfaces** (e.g., vethcalixxxx)
3. **hostNetwork pods have NO veth interface** - they use the host's eth0 directly
4. **Result:** Policies are never evaluated for hostNetwork pods

---

## How to Properly Allow Traffic to hostNetwork Pods

### Option 1: Use Node IP in ipBlock Rules (RECOMMENDED)

**Problem:** You can't use `podSelector` for hostNetwork pods because Calico doesn't see them.

**Solution:** Use the node's IP address in `ipBlock` rules:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-hostnetwork-access
  namespace: ai-inference
spec:
  podSelector:
    matchLabels:
      app: your-app
  policyTypes:
  - Ingress
  ingress:
  # Allow traffic from hostNetwork pod (running on specific node)
  - from:
    - ipBlock:
        cidr: 10.1.1.120/32  # Nexus node IP where hostNetwork pod runs
    ports:
    - protocol: TCP
      port: 8080
```

**For multiple nodes:**
```yaml
  - from:
    - ipBlock:
        cidr: 10.1.1.0/24  # Entire cluster network
    ports:
    - protocol: TCP
      port: 8080
```

### Option 2: Add hostNetwork Pod to GlobalNetworkPolicy

```yaml
apiVersion: crd.projectcalico.org/v1
kind: GlobalNetworkPolicy
metadata:
  name: allow-hostnetwork-llama-server
spec:
  selector: "app == llama-cpp"  # Won't work for hostNetwork!
  # Instead, use node selector:
  selector: "has(node-name) && node-name == 'nexus'"
  
  ingress:
  - action: Allow
    protocol: TCP
    destination:
      ports:
      - 8080
    source:
      nets:
      - 10.1.1.0/24  # Cluster network
```

**⚠️ WARNING:** This won't work because Calico can't see hostNetwork pods!

### Option 3: Use hostPort Instead of hostNetwork (BEST PRACTICE)

**Instead of:**
```yaml
spec:
  hostNetwork: true
  containers:
  - ports:
    - containerPort: 8080
      hostPort: 8080
```

**Use:**
```yaml
spec:
  hostNetwork: false  # Remove this line
  containers:
  - ports:
    - containerPort: 8080
    # Use NodePort or Service instead
```

**Then expose via Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: llama-server
  namespace: ai-inference
spec:
  type: NodePort  # Or LoadBalancer
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30880  # Optional: specify node port
  selector:
    app: llama-cpp
```

**Benefits:**
- Pod stays in pod network (10.244.x.x)
- Calico policies apply normally
- Service abstraction for load balancing
- No special IP rules needed

### Option 4: Use Calico HostEndpoint (ADVANCED)

For cases where hostNetwork is mandatory (e.g., system daemons), use Calico's HostEndpoint resource:

```yaml
apiVersion: crd.projectcalico.org/v1
kind: HostEndpoint
metadata:
  name: nexus-hostnetwork-endpoint
  namespace: ai-inference
spec:
  node: nexus  # Node name
  interface: eth0  # Host network interface
  expectedIPs:
  - 10.1.1.120  # Node IP
  profiles:
  - cali-hostnetwork-profile
```

**Then create a profile:**
```yaml
apiVersion: crd.projectcalico.org/v1
kind: Profile
metadata:
  name: cali-hostnetwork-profile
spec:
  ingress:
  - action: Allow
    protocol: TCP
    destination:
      ports:
      - 8080
    source:
      nets:
      - 10.1.1.0/24
  egress:
  - action: Allow
```

---

## Configuration Examples

### Example 1: Allow Access to hostNetwork Llama Server

**Current setup (broken):**
```yaml
# llama-server-deployment.yaml
spec:
  hostNetwork: true  # Problem: Can't use podSelector in policies
```

**Network policy (won't work):**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-llama-server
  namespace: ai-inference
spec:
  podSelector:
    matchLabels:
      app: llama-cpp  # Ignored for hostNetwork pods!
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: ai-inference-gateway
    ports:
    - port: 8080
```

**Fixed policy (using ipBlock):**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-llama-server-from-gateway
  namespace: ai-inference
spec:
  podSelector:
    matchLabels:
      app: ai-inference-gateway  # Select the SOURCE pod
  policyTypes:
  - Egress
  egress:
  # Allow traffic to hostNetwork pod on nexus
  - to:
    - ipBlock:
        cidr: 10.1.1.120/32  # Nexus IP
    ports:
    - protocol: TCP
      port: 8080
```

### Example 2: GlobalNetworkPolicy for hostNetwork

```yaml
apiVersion: crd.projectcalico.org/v1
kind: GlobalNetworkPolicy
metadata:
  name: allow-hostnetwork-ingress
spec:
  order: 100  # Apply before default-deny (1000)
  
  ingress:
  # Allow traffic to hostNetwork pods
  - action: Allow
    protocol: TCP
    destination:
      ports:
      - 8080      # llama-server
      - 9090      # custom exporter
      - 9100      # node_exporter
    source:
      nets:
      - 10.1.1.0/24    # Cluster network
      - 10.244.0.0/16  # Pod network
      - 10.0.0.0/12    # Service network
  
  # Don't apply to normal pods (they have their own policies)
  selector: "!all()"  # Empty selector = apply to all traffic
```

---

## Security Implications

### ⚠️ Critical Security Risks

**1. hostNetwork Pods Bypass All Network Policies**

```
Normal pod:
  → Pod network (10.244.x.x)
  → Calico veth interface
  → iptables rules apply
  → Policies enforced ✓

hostNetwork pod:
  → Host network (10.1.1.x)
  → Direct host interface
  → NO iptables rules on host interface
  → Policies bypassed ✗
```

**2. Access to Host Services**

hostNetwork pods can access:
- All host services (localhost, 127.0.0.1)
- Host's network stack directly
- Other processes on the host
- Host's iptables/routing tables

**3. Port Conflicts**

```yaml
spec:
  hostNetwork: true
  containers:
  - ports:
    - containerPort: 8080
      hostPort: 8080  # Occupies host port!
```

If the host already uses port 8080, the pod fails to start.

**4. Network Namespace Escape**

Pods with hostNetwork share the host's network namespace:
- Can sniff all host traffic
- Can bind to any host port
- Escapes pod network isolation

### Mitigation Strategies

**1. Minimize hostNetwork Usage**

```yaml
# ❌ AVOID: hostNetwork for convenience
spec:
  hostNetwork: true  # Don't do this!

# ✅ BETTER: Use hostPort or NodePort
spec:
  containers:
  - ports:
    - containerPort: 8080
      hostPort: 8080  # Or use NodePort service
```

**2. Use HostEndpoint Resources**

```yaml
apiVersion: crd.projectcalico.org/v1
kind: HostEndpoint
metadata:
  name: secure-hostnetwork-endpoint
spec:
  node: nexus
  interface: eth0
  expectedIPs:
  - 10.1.1.120
  profiles:
  - secure-hostnetwork-profile
```

**3. Apply Host Firewall Rules**

Use NixOS firewall for hostNetwork pods:

```nix
# modules/system/cluster-firewall.nix
networking.firewall = {
  allowedTCPPorts = lib.mkOptionDefault [
    8080  # llama-server (hostNetwork)
    9100  # node_exporter (hostNetwork)
  ];
  
  # Extra: Restrict to specific sources
  extraCommands = ''
    iptables -A INPUT -p tcp --dport 8080 -s 10.1.1.0/24 -j ACCEPT
    iptables -A INPUT -p tcp --dport 8080 -j DROP
  '';
};
```

**4. Use PSP/PSS to Restrict hostNetwork**

```yaml
apiVersion: v1
kind: PodSecurityPolicy
metadata:
  name: restrict-hostnetwork
spec:
  hostNetwork: false
  hostPorts: []
  runAsUser:
    rule: MustRunAsNonRoot
```

Or Pod Security Standards (K8s 1.25+):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secure-namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    # restricted profile forbids hostNetwork
```

---

## Current Cluster Status

### ❌ Calico is NOT Running

**Evidence:**
```bash
# No Calico pods
$ kubectl get pods -n kube-system | grep calico
# (empty)

# No Calico CRDs
$ kubectl get crd | grep calico
# (empty)

# No Tigera operator
$ kubectl get pods -n tigera-operator
# Error from server (NotFound): namespaces "tigera-operator" not found
```

### What CNI IS Running?

**Likely K3s default CNI (simple bridge):**

- Pod CIDR: 10.244.0.0/16
- Pods get 10.244.x.x IPs
- Simple overlay network (no BGP, no WireGuard)
- **Network policies likely NOT enforced** (K3s default doesn't support policies)

### Recommendation: Fix Calico OR Remove Calico Manifests

**Option A: Deploy Calico Properly**

```bash
# Deploy Tigera operator
kubectl apply -f /etc/nixos/kubernetes-manifests/calico/tigera-operator.yaml

# Deploy Calico installation
kubectl apply -f /etc/nixos/kubernetes-manifests/calico/tigera-installation.yaml

# Wait for Calico pods
kubectl get pods -n calico-system
```

**Option B: Remove Calico Manifests (Use K3s Default)**

```bash
# Remove Calico manifests
rm -rf /etc/nixos/kubernetes-manifests/calico/

# Update network policies to use K3s's policy support (if available)
# Or disable network policies entirely
```

---

## Best Practices Summary

### ✅ DO:

1. **Use hostPort or NodePort instead of hostNetwork**
   ```yaml
   spec:
     containers:
     - ports:
       - containerPort: 8080
         hostPort: 8080
   ```

2. **Expose via Services**
   ```yaml
   apiVersion: v1
   kind: Service
   spec:
     type: NodePort
     ports:
     - port: 8080
       nodePort: 30880
   ```

3. **Use ipBlock for hostNetwork pod access**
   ```yaml
   ingress:
   - from:
     - ipBlock:
         cidr: 10.1.1.120/32  # Node IP
   ```

4. **Apply host firewall rules for hostNetwork ports**
   ```nix
   networking.firewall.allowedTCPPorts = [8080];
   ```

### ❌ DON'T:

1. **Use hostNetwork unless absolutely necessary**
   - Breaks network policies
   - Security risk
   - Port conflicts

2. **Use podSelector for hostNetwork pods**
   - Calico can't see hostNetwork pods
   - Rules will be ignored

3. **Assume Calico is running**
   - Verify with `kubectl get pods -n calico-system`
   - Check CRDs with `kubectl get crd | grep calico`

4. **Mix hostNetwork and normal pods in same policy**
   - Use separate policies
   - Use ipBlock for hostNetwork
   - Use podSelector for normal pods

---

## Troubleshooting Commands

```bash
# Check if Calico is running
kubectl get pods -n calico-system
kubectl get pods -n tigera-operator
kubectl get crd | grep calico

# Check CNI configuration
kubectl get nodes -o wide
ip route show | grep 10.244
iptables-save | grep -i cali

# Check network policies
kubectl get networkpolicies -A
kubectl get globalnetworkpolicies.crd.projectcalico.org -A

# Test connectivity to hostNetwork pod
# From another pod:
kubectl run test-pod --image=nicolaka/netshoot -it --restart=Never
curl http://10.1.1.120:8080/health  # Use node IP, not pod IP

# Check hostNetwork pod
kubectl get pods -n ai-inference -o wide
kubectl describe pod llama-server-xxx -n ai-inference
```

---

## References

- **Calico Documentation:** https://docs.projectcalico.org/
- **Kubernetes Network Policies:** https://kubernetes.io/docs/concepts/services-networking/network-policies/
- **hostNetwork Security:** https://kubernetes.io/docs/concepts/security/pod-security-standards/
- **Calico HostEndpoints:** https://docs.projectcalico.org/security/host-endpoints

---

## Appendix: Current Cluster Inventory

### hostNetwork Pods (Problematic):

```bash
$ kubectl get pods -A -o json | jq -r '.items[] | select(.spec.hostNetwork==true) | "\(.metadata.namespace)/\(.metadata.name)"'
ai-inference/llama-server-7dd75b954b-2268c
ai-inference/llama-server-7dd75b954b-24gbc
ai-inference/llama-server-7dd75b954b-24hq7
... (22 llama-server replicas)
```

**Note:** 22 replicas of llama-server with hostNetwork=true on nexus (10.1.1.120).

### Network Policies:

```bash
$ kubectl get networkpolicies -A | wc -l
26  # 26 policies deployed (but Calico not running!)
```

**Conclusion:** Network policies are defined but NOT enforced because Calico is not running.

---

**Author:** Claude (Research Agent)
**Last Updated:** 2026-04-23
**Version:** 1.0
