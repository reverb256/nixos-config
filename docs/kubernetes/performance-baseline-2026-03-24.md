# Kubernetes Cluster Performance Baseline

**Date:** 2026-03-24
**Cluster Version:** v1.35.0
**Nodes:** 4 (Zephyr, Nexus, Forge, Sentry)
**CNI:** Calico v3.28.0 (IPIP, BGP, IPVS, WireGuard)

---

## Cluster Configuration

### Network Features
- **Encapsulation:** IPIP (IP-in-IP) with MTU 1480
- **BGP:** Full mesh enabled (AS 64512)
- **IPVS:** Load balancing with O(1) lookup
- **WireGuard:** Pod-to-pod encryption enabled
- **Pod CIDR:** 10.244.0.0/16

### Node Resources
| Node | CPU | RAM | GPUs | Role | Calico Status |
|------|-----|-----|------|------|---------------|
| Zephyr | 32 cores | 31GB | 2× NVIDIA | Control plane | READY (1/1) |
| Nexus | 24 cores | 46GB | 1× NVIDIA | Control plane | READY (1/1) |
| Forge | 6 cores | 15GB | 2× NVIDIA + 2× AMD | GPU compute | Running (0/1) |
| Sentry | 16 cores | 31GB | 1× AMD | Monitoring | Running (0/1) |

**Note:** Forge and Sentry have degraded BGP peering due to link-local IPv6 addresses. Cluster is functional (pods scheduling), but not optimal.

---

## Performance Testing Guide

### Tools Available
- **iperf3:** Installed on all hosts (`/nix/var/nix/profiles/default/bin/iperf3`)
- **kubectl:** Standard Kubernetes CLI
- **ping:** ICMP latency testing
- **curl:** HTTP latency testing

### Test Scenarios

#### 1. Pod-to-Pod Latency (Same Node)
```bash
# Create test pods
kubectl run test-pod-1 --image=nicolaka/netshoot --restart=Never -n default
kubectl run test-pod-2 --image=nicolaka/netshoot --restart=Never -n default

# Get pod IPs
POD1_IP=$(kubectl get pod test-pod-1 -o jsonpath='{.status.podIP}')
POD2_IP=$(kubectl get pod test-pod-2 -o jsonpath='{.status.podIP}')

# Test latency from pod1 to pod2
kubectl exec test-pod-1 -- ping -c 10 $POD2_IP

# Cleanup
kubectl delete pod test-pod-1 test-pod-2
```

#### 2. Pod-to-Pod Latency (Cross-Node)
```bash
# Create pods on specific nodes
kubectl run test-zephyr --image=nicolaka/netshoot --restart=Never -n default --overrides='{"spec":{"nodeName":"zephyr"}}'
kubectl run test-nexus --image=nicolaka/netshoot --restart=Never -n default --overrides='{"spec":{"nodeName":"nexus"}}'

# Test latency
kubectl exec test-zephyr -- ping -c 10 $(kubectl get pod test-nexus -o jsonpath='{.status.podIP}')

# Cleanup
kubectl delete pod test-zephyr test-nexus
```

#### 3. Service Lookup Latency
```bash
# Time DNS queries for services
time kubectl run test-dns --image=nicolaka/netshoot --restart=Never --command -- sh -c 'for i in {1..100}; do nslookup kubernetes.default.svc.cluster.local; done'

# Cleanup
kubectl delete pod test-dns
```

#### 4. Cross-Node Throughput (iperf3)
```bash
# Start iperf3 server on zephyr
kubectl run iperf3-server --image=nicolaka/netshoot --restart=Never --overrides='{"spec":{"nodeName":"zephyr"}}' --command -- iperf3 -s

# Start iperf3 client on nexus
kubectl run iperf3-client --image=nicolaka/netshoot --restart=Never --overrides='{"spec":{"nodeName":"nexus"}}' --command -- sh -c 'iperf3 -c $(kubectl get pod iperf3-server -o jsonpath='{.status.podIP}') -t 30'

# Cleanup
kubectl delete pod iperf3-server iperf3-client
```

---

## Expected Performance

### Latency Targets
- **Same-node pod-to-pod:** <1ms
- **Cross-node pod-to-pod:** <5ms (same LAN)
- **Service DNS lookup:** <10ms (cached), <50ms (uncached)

### Throughput Targets
- **Cross-node throughput:** >1 Gbps (1 Gbps LAN)
- **Pod-to-pod bandwidth:** Limited by node NIC speed

### IPVS Benefits
- **O(1) service lookup** vs O(n) iptables
- **Better performance** for high service count clusters
- **Automatic load distribution** across backend pods

---

## Performance Optimization Features

### Calico Features Enabled
1. **IPIP Encapsulation**
   - Type: IP-in-IP (protocol 4)
   - MTU: 1480 (1500 - 20 byte IPIP header)
   - Benefit: Simple overlay network

2. **BGP Routing**
   - Type: Full mesh (node-to-node)
   - AS Number: 64512 (private use)
   - Benefit: Dynamic pod route advertisement

3. **IPVS Load Balancing**
   - Type: NAT mode
   - Benefit: O(1) kube-proxy service lookup

4. **WireGuard Encryption**
   - Type: WireGuard (kernel module)
   - Benefit: Secure pod-to-pod traffic

---

## Current Known Issues

### BGP Peering Degradation
- **Affected Nodes:** Forge, Sentry
- **Issue:** Link-local IPv6 addresses don't work with BGP multihop
- **Impact:** 2/4 nodes not READY (but Running)
- **Workaround:** Cluster functional, pods scheduling normally
- **Resolution:** Documented in `docs/kubernetes/calico-bgp-fix-2026-03-23.md`

### MTU Considerations
- **IPIP overhead:** 20 bytes per packet
- **Effective MTU:** 1480 (vs 1500 for Ethernet)
- **Impact:** Slightly lower throughput for large payloads
- **Benefit:** Simple, reliable overlay network

---

## Next Steps

### Immediate (Optional)
1. Run iperf3 tests to establish actual throughput numbers
2. Measure actual pod-to-pod latency
3. Document service DNS lookup performance

### Future Improvements
1. **Consider VXLAN** for better performance (if needed)
2. **BGP route reflector** for larger clusters (not needed for 4 nodes)
3. **Network policies** for security (already deployed in audit mode)

---

## References

- **Calico Documentation:** https://docs.projectcalico.org/
- **IPVS Documentation:** https://kernel.org/doc/Documentation/networking/ipvs-sysctl.txt
- **WireGuard Documentation:** https://www.wireguard.com/

**Baseline Version:** 1.0 | **Created:** 2026-03-24
