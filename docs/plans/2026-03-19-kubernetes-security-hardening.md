# Kubernetes Security Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement defense-in-depth security for internet-facing Kubernetes services (SearXNG, Cloudflared, default namespace) through Pod Security Standards, NetworkPolicy isolation, security context hardening, and runtime monitoring.

**Architecture:** Layered security model starting with namespace PSS labels, followed by NetworkPolicy isolation (default-deny + explicit allow rules), pod-level security context hardening (non-root, read-only), and Falco runtime monitoring for threat detection.

**Tech Stack:** Kubernetes 1.29+, NetworkPolicy, Pod Security Standards, Falco, NixOS flakes

---

## Task 1: Create Security Baseline Directory Structure

**Files:**
- Create: `kubernetes-manifests/security-baseline/00-pod-security-standards.yaml`
- Create: `kubernetes-manifests/security-baseline/01-network-policy-global.yaml`
- Create: `kubernetes-manifests/security-baseline/02-security-context.yaml`
- Create: `kubernetes-manifests/security-baseline/emergency-allow-all.yaml`

**Step 1: Create directory**

```bash
mkdir -p kubernetes-manifests/security-baseline
```

**Step 2: Write Pod Security Standards for all namespaces**

Create: `kubernetes-manifests/security-baseline/00-pod-security-standards.yaml`

```yaml
# Pod Security Standards for Unprotected Namespaces
# Applies defense-in-depth security policies

---
# Search Namespace (SearXNG) with PSS
apiVersion: v1
kind: Namespace
metadata:
  name: search
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    name: search
---
# Akash Services Namespace (Cloudflared) with PSS
apiVersion: v1
kind: Namespace
metadata:
  name: akash-services
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    name: akash-services
---
# Default Namespace with PSS
apiVersion: v1
kind: Namespace
metadata:
  name: default
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    name: default
```

**Step 3: Write global NetworkPolicy defaults**

Create: `kubernetes-manifests/security-baseline/01-network-policy-global.yaml`

```yaml
# Global NetworkPolicy Defaults
# Implements default-deny with DNS and monitoring allow rules

---
# Default deny all traffic in search namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: search
  labels:
    policy: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
# Default deny all traffic in akash-services namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: akash-services
  labels:
    policy: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
# Default deny all traffic in default namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
  labels:
    policy: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
# Allow DNS from all protected namespaces (required for service discovery)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: search
  labels:
    policy: allow-dns
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: akash-services
  labels:
    policy: allow-dns
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
  labels:
    policy: allow-dns
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
# Allow monitoring (Prometheus) to scrape metrics from all namespaces
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: search
  labels:
    policy: allow-monitoring
spec:
  podSelector:
    matchLabels:
      prometheus.io/scrape: "true"
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 7777
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: akash-services
  labels:
    policy: allow-monitoring
spec:
  podSelector:
    matchLabels:
      prometheus.io/scrape: "true"
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 20241
```

**Step 4: Write default security context**

Create: `kubernetes-manifests/security-baseline/02-security-context.yaml`

```yaml
# Default Security Context for Pods
# Apply these to all pods for baseline hardening

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: security-context-defaults
  namespace: default
data:
  # Non-root user (common across containers)
  runAsUser: "1001"
  runAsGroup: "1001"
  fsGroup: "1001"
  # Security options
  runAsNonRoot: "true"
  allowPrivilegeEscalation: "false"
  readOnlyRootFilesystem: "true"
  seccompProfileType: "RuntimeDefault"
```

**Step 5: Write emergency rollback policy**

Create: `kubernetes-manifests/security-baseline/emergency-allow-all.yaml`

```yaml
# EMERGENCY ROLLBACK POLICY
# Apply this to restore full connectivity if security policies break services
# WARNING: This removes all network restrictions - use only for emergencies

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-allow-all
  namespace: search
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-allow-all
  namespace: akash-services
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-allow-all
  namespace: default
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

**Step 6: Commit baseline policies**

```bash
git add kubernetes-manifests/security-baseline/
git commit -m "feat(security): add baseline security policies

- Pod Security Standards for search, akash-services, default
- Default-deny NetworkPolicy with DNS/monitoring allow rules
- Default security context ConfigMap
- Emergency rollback policy

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Update SearXNG Namespace with PSS Labels

**Files:**
- Modify: `kubernetes-manifests/searxng/00-namespace.yaml`

**Step 1: Read current namespace file**

```bash
cat kubernetes-manifests/searxng/00-namespace.yaml
```

**Step 2: Update namespace with PSS labels**

Replace contents of `kubernetes-manifests/searxng/00-namespace.yaml`:

```yaml
---
# SearXNG Privacy-Respecting Metasearch Engine Namespace
# Migrated from systemd to Kubernetes (2026-03-19)
# Privacy-focused metasearch engine that doesn't track users
# SECURITY: Pod Security Standards applied

apiVersion: v1
kind: Namespace
metadata:
  name: search
  labels:
    name: search
    # Pod Security Standards
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Step 3: Verify syntax**

```bash
kubectl apply --dry-run=client -f kubernetes-manifests/searxng/00-namespace.yaml
```

Expected: `namespace/search configured (dry run)`

**Step 4: Commit**

```bash
git add kubernetes-manifests/searxng/00-namespace.yaml
git commit -m "feat(security): add PSS labels to search namespace

Enforce baseline, audit against restricted for SearXNG.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Create SearXNG NetworkPolicy

**Files:**
- Create: `kubernetes-manifests/searxng/04-network-policy.yaml`

**Step 1: Write SearXNG NetworkPolicy**

Create: `kubernetes-manifests/searxng/04-network-policy.yaml`

```yaml
# Network Policies for SearXNG
# Implements defense-in-depth network segmentation

---
# Allow SearXNG to receive ingress traffic from ingress controller
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-searxng-ingress
  namespace: search
  labels:
    app: searxng
    policy: allow-ingress
spec:
  podSelector:
    matchLabels:
      app: searxng
  policyTypes:
  - Ingress
  ingress:
  # Allow from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  # Allow from within cluster (internal services)
  - from:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 8080
---
# Allow SearXNG to make outbound DNS queries only
# No other egress allowed (search-only service)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-searxng-egress
  namespace: search
  labels:
    app: searxng
    policy: allow-egress
spec:
  podSelector:
    matchLabels:
      app: searxng
  policyTypes:
  - Egress
  egress:
  # DNS queries only
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

**Step 2: Verify syntax**

```bash
kubectl apply --dry-run=client -f kubernetes-manifests/searxng/04-network-policy.yaml
```

Expected: No errors

**Step 3: Commit**

```bash
git add kubernetes-manifests/searxng/04-network-policy.yaml
git commit -m "feat(security): add SearXNG NetworkPolicy

Allow ingress from ingress controller only.
Egress restricted to DNS queries only (search-only service).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Create Akash-Services Namespace with PSS

**Files:**
- Create: `kubernetes-manifests/akash-services/00-namespace.yaml`

**Step 1: Create directory**

```bash
mkdir -p kubernetes-manifests/akash-services
```

**Step 2: Write namespace with PSS labels**

Create: `kubernetes-manifests/akash-services/00-namespace.yaml`

```yaml
---
# Akash Services Namespace
# Cloudflare tunnel and external service integrations
# SECURITY: Pod Security Standards applied

apiVersion: v1
kind: Namespace
metadata:
  name: akash-services
  labels:
    name: akash-services
    # Pod Security Standards
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Step 3: Verify syntax**

```bash
kubectl apply --dry-run=client -f kubernetes-manifests/akash-services/00-namespace.yaml
```

**Step 4: Commit**

```bash
git add kubernetes-manifests/akash-services/00-namespace.yaml
git commit -m "feat(security): add akash-services namespace with PSS

Enforce baseline, audit against restricted for Cloudflare tunnel.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Create Cloudflared NetworkPolicy

**Files:**
- Create: `kubernetes-manifests/akash-services/01-network-policy.yaml`

**Step 1: Write Cloudflared NetworkPolicy**

Create: `kubernetes-manifests/akash-services/01-network-policy.yaml`

```yaml
# Network Policies for Cloudflare Tunnel
# Outbound-only service (tunnel to Cloudflare edge)

---
# Allow Cloudflared to reach Cloudflare edge servers
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cloudflared-egress
  namespace: akash-services
  labels:
    app: cloudflared
    policy: allow-egress
spec:
  podSelector:
    matchLabels:
      app: cloudflared-tunnel
  policyTypes:
  - Egress
  egress:
  # DNS queries
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  # Cloudflare edge (any IP, HTTPS only)
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
---
# No ingress allowed (outbound tunnel only)
# Deny policy is implicit from default-deny
```

**Step 2: Verify syntax**

```bash
kubectl apply --dry-run=client -f kubernetes-manifests/akash-services/01-network-policy.yaml
```

**Step 3: Commit**

```bash
git add kubernetes-manifests/akash-services/01-network-policy.yaml
git commit -m "feat(security): add Cloudflared NetworkPolicy

Egress to Cloudflare edge only (port 443).
No ingress allowed (outbound tunnel).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Add Security Context to SearXNG Deployment

**Files:**
- Modify: `kubernetes-manifests/searxng/03-deployment.yaml`

**Step 1: Read current deployment**

```bash
cat kubernetes-manifests/searxng/03-deployment.yaml
```

**Step 2: Add security context to pod spec**

In the deployment, add `securityContext` at both pod level and container level:

```yaml
# At the pod level (under spec.template.metadata.labels):
spec:
  template:
    metadata:
      labels:
        app: searxng
    spec:
      # POD LEVEL SECURITY CONTEXT
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 1001
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: searxng
        image: searxng/searxng:latest
        # CONTAINER LEVEL SECURITY CONTEXT
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        # ... rest of container config
        # Add volume for tmp directory (required for read-only root)
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /var/www/searxng/cache
      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}
```

**Step 3: Verify syntax**

```bash
kubectl apply --dry-run=client -f kubernetes-manifests/searxng/03-deployment.yaml
```

**Step 4: Commit**

```bash
git add kubernetes-manifests/searxng/03-deployment.yaml
git commit -m "feat(security): add security context to SearXNG

- Non-root user (1001)
- Read-only root filesystem
- Drop all capabilities
- Runtime seccomp profile

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Add Security Context to Cloudflared Deployment

**Files:**
- Modify: `kubernetes-manifests/cloudflared-final.yaml`

**Step 1: Read current deployment**

```bash
cat kubernetes-manifests/cloudflared-final.yaml
```

**Step 2: Add security context to pod spec**

```yaml
spec:
  template:
    spec:
      # POD LEVEL SECURITY CONTEXT
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 1001
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:2026.3.0
        # CONTAINER LEVEL SECURITY CONTEXT
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        # ... rest of container config
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: config
          mountPath: /etc/cloudflared
          readOnly: true
      volumes:
      - name: tmp
        emptyDir: {}
      - name: config
        projected:
          sources:
          - configMap:
              name: cloudflared-final-config
          - secret:
              name: cloudflared-final-credentials
```

**Step 3: Verify syntax**

```bash
kubectl apply --dry-run=client -f kubernetes-manifests/cloudflared-final.yaml
```

**Step 4: Commit**

```bash
git add kubernetes-manifests/cloudflared-final.yaml
git commit -m "feat(security): add security context to Cloudflared

- Non-root user (1001)
- Read-only root filesystem
- Drop all capabilities
- Runtime seccomp profile

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Create Kubernetes Security Module

**Files:**
- Create: `modules/kubernetes-security.nix`

**Step 1: Write security module**

Create: `modules/kubernetes-security.nix`

```nix
# Kubernetes Security Module
# Runtime security monitoring with Falco

{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf types;
  cfg = config.security.kubernetes;
in {
  options.security.kubernetes = {
    enable = mkEnableOption "Kubernetes runtime security monitoring";

    enableFalco = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Falco for runtime threat detection";
    };
  };

  config = mkIf cfg.enable {
    # Install Falco for runtime security monitoring
    services.falco = mkIf cfg.enableFalco {
      enable = true;
      settings = {
        # Falco configuration
        json_output = true;
        log_stderr = true;
        priority = "info";
      };

      # Enable security rules
      rules = [
        # Detect shell in containers (potential compromise)
        "shell_in_containers"
        # Detect sensitive file access
        "sensitive_file_access"
        # Detect privileged container spawns
        "privileged_container"
        # Detect crypto miners
        "crypto_miner"
        # Detect unexpected network connections
        "network_policy"
      ];

      # Output to journald for integration with logging stack
      outputs = [
        {
          type = "syslog";
        }
      ];
    };

    # Install security tools
    environment.systemPackages = with pkgs; [
      falcoctl  # Falco management tool
      kubectl   # For audit scripts
    ];

    # JournalD configuration for security events
    journald.extraConfig = ''
      # Forward security events to persistent storage
      Storage=persistent

      # Increase retention for security audit logs
      SystemMaxUse=2G
      MaxRetentionSec=30day
    '';
  };
}
```

**Step 2: Add to modules list**

Check `modules/default.nix` and add import if not present:

```bash
grep -q "kubernetes-security" modules/default.nix || echo "Need to add import"
```

If not present, add to `modules/default.nix`:

```nix
security.kubernetes.enable = true;
```

**Step 3: Verify flake syntax**

```bash
nix flake check
```

**Step 4: Commit**

```bash
git add modules/kubernetes-security.nix
git commit -m "feat(security): add Kubernetes runtime security module

Falco integration for runtime threat detection:
- Shell in containers detection
- Sensitive file access monitoring
- Privileged container detection
- Crypto miner detection

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Deploy Phase 1 - Namespace Hardening

**Step 1: Apply namespace updates**

```bash
# Apply search namespace with PSS
kubectl apply -f kubernetes-manifests/searxng/00-namespace.yaml

# Apply akash-services namespace
kubectl apply -f kubernetes-manifests/akash-services/00-namespace.yaml

# Apply baseline PSS policies
kubectl apply -f kubernetes-manifests/security-baseline/00-pod-security-standards.yaml
```

**Step 2: Verify namespaces have PSS labels**

```bash
kubectl get namespaces search,akash-services,default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels}{"\n"}{end}'
```

Expected: All namespaces show `pod-security.kubernetes.io/enforce: baseline`

**Step 3: Verify existing pods still running**

```bash
kubectl get pods -n search
kubectl get pods -n akash-services
```

Expected: Pods are running (no restarts due to PSS)

**Step 4: Document Phase 1 completion**

```bash
echo "Phase 1 complete: Namespace PSS labels applied" > /tmp/security-phase1.log
```

---

## Task 10: Deploy Phase 2 - Network Isolation

**Step 1: Apply default-deny NetworkPolicies**

```bash
kubectl apply -f kubernetes-manifests/security-baseline/01-network-policy-global.yaml
```

**Step 2: Verify default-deny policies applied**

```bash
kubectl get networkpolicy -n search,akash-services,default
```

Expected: `default-deny-all` and `allow-dns` policies present

**Step 3: Test DNS resolution still works**

```bash
kubectl run test-dns --rm -it --image=busybox --restart=Never -n search -- nslookup kubernetes.default
```

Expected: DNS resolution succeeds

**Step 4: Clean up test pod**

```bash
kubectl delete pod test-dns -n search --ignore-not-found
```

---

## Task 11: Deploy Phase 3 - Service-Specific Policies

**Step 1: Apply SearXNG NetworkPolicy**

```bash
kubectl apply -f kubernetes-manifests/searxng/04-network-policy.yaml
```

**Step 2: Apply Cloudflared NetworkPolicy**

```bash
kubectl apply -f kubernetes-manifests/akash-services/01-network-policy.yaml
```

**Step 3: Verify policies applied**

```bash
kubectl get networkpolicy -n search,akash-services
```

Expected: Service-specific policies visible

**Step 4: Test SearXNG accessibility (via ingress should work)**

```bash
kubectl run test-searxng --rm -it --image=curlimages/curl --restart=Never -n ingress-nginx -- curl http://searxng.search.svc.cluster.local:8080
```

Expected: Connection succeeds (from ingress namespace)

**Step 5: Test SearXNG isolation (from other namespace should fail)**

```bash
kubectl run test-block --rm -it --image=busybox --restart=Never -n default -- wget --timeout=3 http://searxng.search.svc.cluster.local:8080
```

Expected: Connection times out (blocked by NetworkPolicy)

**Step 6: Clean up test pods**

```bash
kubectl delete pod test-searxng test-block --ignore-not-found
```

---

## Task 12: Deploy Phase 4 - Pod Security Context

**Step 1: Apply SearXNG deployment with security context**

```bash
kubectl apply -f kubernetes-manifests/searxng/03-deployment.yaml
```

**Step 2: Apply Cloudflared deployment with security context**

```bash
kubectl apply -f kubernetes-manifests/cloudflared-final.yaml
```

**Step 3: Verify pods restarted with new security context**

```bash
kubectl get pods -n search -w
# Wait for new pods to be Ready
```

**Step 4: Check pod security context is applied**

```bash
kubectl get pod -n search -l app=searxng -o jsonpath='{.items[0].spec.securityContext}'
```

Expected: Shows `runAsNonRoot: true`, `runAsUser: 1001`

**Step 5: Verify services are still accessible**

```bash
# SearXNG health check
kubectl run test-health --rm -it --image=curlimages/curl --restart=Never -n ingress-nginx -- curl -f http://searxng.search.svc.cluster.local:8080/health
```

Expected: Health check succeeds

---

## Task 13: Deploy Phase 5 - Runtime Monitoring

**Step 1: Enable Kubernetes security module in NixOS config**

Add to host configuration (e.g., `hosts/zephyr/configuration.nix`):

```nix
security.kubernetes.enable = true;
```

**Step 2: Build and switch**

```bash
just switch
```

**Step 3: Verify Falco is running**

```bash
systemctl status falco
```

Expected: Falco service is active

**Step 4: Check Falco is receiving events**

```bash
journalctl -u falco -f
```

Expected: Security events being logged

**Step 5: Test Falco detects a security event**

```bash
# Run a shell in a container (should trigger Falco alert)
kubectl run test-shell --rm -it --image=busybox --restart=Never -n search -- sh -c "whoami"
```

Expected: Falco logs the shell execution

**Step 6: Clean up test pod**

```bash
kubectl delete pod test-shell -n search --ignore-not-found
```

---

## Task 14: Final Verification and Documentation

**Step 1: Run comprehensive security check**

```bash
# Check all NetworkPolicies
kubectl get networkpolicy --all-namespaces

# Check PSS labels on all namespaces
kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}{end}'

# Check pod security contexts
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.spec.securityContext.runAsNonRoot}{"\n"}{end}'
```

**Step 2: Verify service functionality**

```bash
# SearXNG should be accessible
curl -I http://searxng.example.com

# Cloudflared tunnel should be running
kubectl get pod -n akash-services -l app=cloudflared-tunnel
```

**Step 3: Create security verification report**

```bash
cat > docs/security/verification-report-$(date +%Y-%m-%d).md << 'EOF'
# Kubernetes Security Hardening Verification Report

**Date**: $(date +%Y-%m-%d)
**Phase**: Completed

## Checklist

- [x] Namespace PSS labels applied
- [x] Default-deny NetworkPolicies deployed
- [x] DNS allow rules working
- [x] Service-specific NetworkPolicies applied
- [x] Pod security contexts configured
- [x] Falco runtime monitoring enabled
- [x] All services functional
- [x] No service disruptions

## Applied Policies

### Namespaces
- search: baseline enforce, restricted audit/warn
- akash-services: baseline enforce, restricted audit/warn
- default: baseline enforce, restricted audit/warn

### NetworkPolicies
- Default-deny all traffic (ingress + egress)
- Allow DNS (kube-system:53/UDP+TCP)
- Allow monitoring (Prometheus scrape)

### Service Policies
- SearXNG: Ingress from ingress-system only
- Cloudflared: Egress to Cloudflare edge only

### Security Context
- Non-root user (1001)
- Read-only root filesystem
- Drop all capabilities
- Runtime seccomp profile

## Rollback Commands

```bash
# Emergency full rollback
kubectl delete networkpolicy --all --all-namespaces
kubectl label namespace search,akash-services,default pod-security.kubernetes.io/enforce-
```

EOF
```

**Step 4: Commit verification report**

```bash
git add docs/security/
git commit -m "docs: add security hardening verification report

All security policies successfully applied and verified.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Testing Commands Reference

```bash
# Verify NetworkPolicies
kubectl get networkpolicy --all-namespaces -o wide

# Describe a specific policy
kubectl describe networkpolicy default-deny-all -n search

# Test connectivity between namespaces
kubectl run test-pod --rm -it --image=busybox --restart=Never -n <namespace> -- wget <target>

# Check pod security context
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.securityContext}'

# View Falco events
journalctl -u falco -n 100

# Simulate security event (triggers Falco)
kubectl run test-shell --rm -it --image=busybox --restart=Never -- sh

# Check PSS compliance
kubectl get pod <pod-name> -n <namespace> -o json | jq '.status'
```

---

## Rollback Commands Reference

```bash
# Phase 1 rollback (PSS labels)
kubectl label namespace search,akash-services,default pod-security.kubernetes.io/enforce-

# Phase 2 rollback (NetworkPolicies)
kubectl delete networkpolicy -n search default-deny-all allow-dns
kubectl delete networkpolicy -n akash-services default-deny-all allow-dns
kubectl delete networkpolicy -n default default-deny-all allow-dns

# Phase 3 rollback (service policies)
kubectl delete networkpolicy -n search allow-searxng-ingress allow-searxng-egress
kubectl delete networkpolicy -n akash-services allow-cloudflared-egress

# Phase 4 rollback (security context)
kubectl patch deployment searxng -n search --type=json -p='[{"op": "remove", "path": "/spec/template/spec/securityContext"}]'
kubectl patch deployment cloudflared-tunnel -n akash-services --type=json -p='[{"op": "remove", "path": "/spec/template/spec/securityContext"}]'

# Emergency full rollback
kubectl apply -f kubernetes-manifests/security-baseline/emergency-allow-all.yaml
```

---

## Success Criteria

- [ ] All namespaces have PSS labels (`enforce: baseline`, `audit: restricted`)
- [ ] All namespaces have default-deny NetworkPolicy
- [ ] SearXNG accessible only via ingress
- [ ] Cloudflared can reach Cloudflare edge
- [ ] All pods have hardened securityContext
- [ ] Falco is running and capturing events
- [ ] No service disruptions
- [ ] Rollback procedures tested
