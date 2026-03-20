# Kubernetes Security Hardening Design

**Date**: 2026-03-19
**Status**: Approved
**Author**: Claude (security-best-practices skill)

## Overview

Implement defense-in-depth security for internet-facing Kubernetes services through layered controls: Pod Security Standards, NetworkPolicy isolation, security context hardening, and runtime monitoring.

## Problem Statement

Current Kubernetes security posture is inconsistent:
- **Protected**: mining, ai-inference, yunikorn namespaces (NetworkPolicies + PSS)
- **Unprotected**: search, akash-services, default namespaces (no policies)
- **Partial**: Some pods have securityContext, most don't

Internet-facing services without proper isolation are vulnerable to:
- Lateral movement between pods
- Privilege escalation
- Data exfiltration
- Container breakouts

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     LAYER 4: Monitoring & Auditing              │
│  - Falco (runtime security) - Security event logging             │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     LAYER 3: Network Security                    │
│  - NetworkPolicy (default-deny + allow rules)                    │
│  - Pod-to-pod traffic isolation                                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     LAYER 2: Pod Security Standards              │
│  - PSS labels on namespaces (baseline enforce, restricted audit) │
│  - Security context on all pods (non-root, read-only, no escape)  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     LAYER 1: RBAC & Secrets                      │
│  - ServiceAccount per application (least privilege)              │
└─────────────────────────────────────────────────────────────────┘
```

## Scope

**In scope (Critical internet-facing services):**
- SearXNG (search namespace) - Privacy-focused search engine
- Cloudflared (akash-services namespace) - Cloudflare tunnel
- Default namespace - General hardening

**Out of scope:**
- Glitchtip (deferred to future phase)
- Internal services (mining, ai-inference already have policies)

## Components

### File Structure

```
/etc/nixos/kubernetes-manifests/
├── security-baseline/                    # NEW: Cluster-wide security policies
│   ├── 00-pod-security-standards.yaml   # PSS for all namespaces
│   ├── 01-network-policy-global.yaml    # Cross-namespace policies
│   ├── 02-security-context.yaml         # Default security contexts
│   └── 03-rbac-restrictions.yaml        # ClusterRole restrictions
│
├── search/
│   ├── 00-namespace.yaml                # MODIFY: Add PSS labels
│   ├── 04-network-policy.yaml           # NEW: SearXNG isolation
│   └── 05-security-context.yaml         # NEW: Pod hardening
│
├── akash-services/
│   └── namespace.yaml                   # NEW: Namespace with PSS labels
│
└── modules/
    └── kubernetes-security.nix          # NEW: Falco + audit logging
```

### Security Policies

#### Pod Security Standards

| Namespace | Enforce | Audit | Warn |
|-----------|---------|-------|------|
| search | baseline | restricted | restricted |
| akash-services | baseline | restricted | restricted |
| default | baseline | restricted | restricted |

#### NetworkPolicy Rules

**SearXNG (search namespace):**
- Default-deny all traffic
- Allow DNS (kube-system:53/UDP)
- Allow ingress from ingress-system only
- Allow monitoring scrape (monitoring namespace)

**Cloudflared (akash-services namespace):**
- Default-deny all traffic
- Allow DNS (kube-system:53/UDP)
- Allow egress to Cloudflare edge (any IP:443/TCP)
- Allow monitoring scrape (monitoring namespace)

#### SecurityContext

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  runAsGroup: 1001
  fsGroup: 1001
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
    - ALL
```

### Runtime Monitoring

**Falco rules:**
- `shell_in_containers` - Detect shell in containers
- `sensitive_file_access` - Detect sensitive file access
- `privileged_container` - Detect privileged container spawns
- `crypto_miner` - Detect crypto miners

**Audit logging:**
- Log all authenticated API requests
- RequestResponse level for security-relevant operations

## Implementation Phases

### Phase 1: Namespace Hardening (5 min, Low Risk)
- Add PSS labels to search, akash-services, default namespaces
- Verify existing pods still run

### Phase 2: Network Isolation (15 min, Medium Risk)
- Apply default-deny NetworkPolicy to each namespace
- Add DNS and monitoring allow rules
- Test connectivity

### Phase 3: Service-Specific Policies (20 min, Medium Risk)
- SearXNG: Allow ingress from ingress-system only
- Cloudflared: Allow egress to Cloudflare only

### Phase 4: Pod Security Context (15 min, Medium Risk)
- Add securityContext to SearXNG and Cloudflared deployments
- Verify pods start successfully

### Phase 5: Runtime Monitoring (10 min, Low Risk)
- Deploy Falco for security event monitoring
- Configure audit logging

**Total Duration**: ~65 minutes

## Rollback Strategy

### Per-Phase Rollback

```bash
# Phase 1 rollback
kubectl label namespace search pod-security.kubernetes.io/enforce-

# Phase 2 rollback
kubectl delete networkpolicy -n search default-deny-all

# Phase 3 rollback
kubectl delete networkpolicy -n search allow-ingress

# Phase 4 rollback
kubectl patch deployment searxng -n search --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/securityContext"}]'

# Emergency full rollback
kubectl delete networkpolicy --all --all-namespaces
```

### Pre-Staged Emergency Policies

File: `kubernetes-manifests/security-baseline/emergency-allow-all.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-allow-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
```

## Testing Strategy

### Pre-Deployment Validation

```bash
# Dry-run apply policies
kubectl apply --dry-run=server -f kubernetes-manifests/security-baseline/

# Validate with kube-score
kube-score score kubernetes-manifests/**/*.yaml
```

### Post-Deployment Verification

```bash
# Verify pods are running
kubectl get pods -n search -n akash-services

# Verify SearXNG connectivity
kubectl run test-pod --rm -it --image=curlimages/curl \
  -- curl http://searxng.search.svc.cluster.local:8080

# Verify NetworkPolicy blocks unwanted traffic
kubectl run test-pod --rm -it --image=busybox \
  -- wget --timeout=2 http://unauthorized.service
```

## Success Criteria

- [ ] All namespaces have PSS labels
- [ ] All namespaces have default-deny NetworkPolicy
- [ ] SearXNG accessible only via ingress
- [ ] Cloudflared can reach Cloudflare edge
- [ ] All pods have hardened securityContext
- [ ] Falco is running and capturing events
- [ ] Audit logging is enabled
- [ ] No service disruptions

## References

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Falco](https://falco.org/docs/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-19 | Initial design |
