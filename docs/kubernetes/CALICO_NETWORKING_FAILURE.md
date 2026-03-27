# Calico Networking Failure - Critical Issue

**Date:** 2026-03-27
**Severity:** CRITICAL - All pod networking broken
**Status:** ROOT CAUSE IDENTIFIED

## Root Cause

**Empty `cali-to-hep-forward` iptables chain on ALL cluster nodes**

This Calico Felix dataplane programming failure is blocking ALL pod-to-host communication, preventing:
- Pod-to-service communication (gateway: 10.0.0.192:8080, DNS: 10.0.0.10:53)
- Pod-to-external connectivity (search engines, APIs)
- Pod-to-pod cross-node communication

## Technical Details

### Affected Components
- **Chain:** `cali-to-hep-forward` (should allow pod → host traffic)
- **Status:** Completely EMPTY on all 4 nodes (zephyr, nexus, forge, sentry)
- **Expected:** Should have ACCEPT rules for allowed host traffic
- **Actual:** 0 rules → all pod-to-host traffic dropped

### Additional Issues Found and Fixed
1. ✅ **Old Flannel routes** - Removed from nexus, forge, sentry (6 routes total)
2. ✅ **Dead cni0 bridge routes** - Removed from nexus
3. ✅ **Service CIDR blocking** - Added ACCEPT rule for 10.96.0.0/12 on all nodes
4. ⚠️ **NetworkPolicies** - Correct ingress/egress policies in place

### Why the Fix Didn't Work
The `cali-to-hep-forward` chain being empty is a **deeper Calico Felix issue**, not a route or policy problem. The iptables rules I added won't help because:
- Traffic never reaches the `cali-cidr-block` chain
- The `cali-to-hep-forward` chain processes packets FIRST
- Empty chain = packets are dropped before reaching other rules

## Impact Assessment

### Broken Functionality
- ❌ SearXNG cannot reach external search engines (Google, Bing, Brave, Wikipedia, GitHub)
- ❌ SearXNG cannot reach internal services (AI Inference Gateway)
- ❌ Any pod-to-service or pod-to-external communication fails
- ✅ Node-to-external connectivity works (tested from nexus node)
- ✅ Gateway service responds to requests from nodes

### Scope
- **ALL pods** on ALL nodes are affected
- This is a cluster-wide infrastructure failure
- Not specific to SearXNG or search namespace

## Resolution Path

### Immediate Workaround (NOT IMPLEMENTED)
```bash
# Manual iptables fix (temporary, won't survive Calico restart)
for node in zephyr nexus forge sentry; do
  ssh $node "sudo iptables -A cali-to-hep-forward -j ACCEPT"
done
```

### Proper Fix Required
1. **Diagnose Calico Felix** - Why is it not programming the chain?
   - Check Felix logs for errors
   - Verify Felix configuration
   - Check for resource constraints
   - Review Calico version compatibility

2. **Restart Calico components** - Force Felix to reprogram iptables
   - Delete Calico node pods on all nodes
   - Delete Calico typha pods
   - Monitor if chains populate correctly

3. **Upgrade/Reinstall Calico** - If restart doesn't fix it
   - Current version: v3.28.0
   - Check if there's a known bug with `cali-to-hep-forward`

4. **Alternative: Switch CNI** - Last resort
   - Consider returning to Flannel (was working before)
   - Or evaluate other CNIs (Cilium)

## Testing Commands

### Verify Fix
```bash
# 1. Check cali-to-hep-forward chain
for node in zephyr nexus forge sentry; do
  ssh $node "sudo iptables -L cali-to-hep-forward -n -v"
done

# 2. Test pod connectivity
kubectl exec -n search searxng-<pod> -- wget -q -O- --timeout=5 http://10.0.0.192:8080/health

# 3. Test external connectivity
kubectl exec -n search searxng-<pod> -- wget -q -O- --timeout=5 http://93.184.216.34

# 4. Test DNS
kubectl exec -n search searxng-<pod> -- nslookup www.google.com
```

## Files Modified

1. `/etc/nixos/kubernetes-manifests/search/searxng-egress-networkpolicy.yaml` - Created egress policy
2. `/etc/nixos/kubernetes-manifests/ai-inference/allow-search-ingress.yaml` - Created ingress policy
3. All nodes: Removed old Flannel routes, added service CIDR ACCEPT rules

## Related Documentation

- `/etc/nixos/docs/kubernetes/caddy-ingress.md` - Caddy Ingress configuration
- `/etc/nixos/ROADMAP.md` - Kubernetes migration plan
- `/etc/nixos/.claude/skills/knowledge-fabric/SKILL.md` - Knowledge fabric documentation

## Next Actions

1. **IMMEDIATE:** Diagnose why Calico Felix isn't programming `cali-to-hep-forward`
2. **SHORT-TERM:** Force restart all Calico node pods
3. **IF NEEDED:** Escalate to Calico support or consider CNI alternatives
4. **DOCUMENT:** Update STATUS.md with current networking state

---

**Last Updated:** 2026-03-27
**Version:** 1.0
**Status:** 🔴 CRITICAL - Root cause identified, fix in progress
