# Security Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement all HIGH and MEDIUM priority security recommendations from the comprehensive security audit

**Architecture:** Layered security approach - harden Kubernetes control plane, add network segmentation, secure API surface, harden remaining systemd services, implement container supply chain security

**Tech Stack:** NixOS modules, Kubernetes Pod Security Admission, Network Policies, systemd service hardening, Trivy for vulnerability scanning

---

## Overview

This plan addresses 14 security findings from the audit:
- **3 HIGH**: Kubernetes Pod Security Admission, Network Policies, Service Account Token Binding
- **5 MEDIUM**: API security headers, systemd hardening, container scanning, secrets rotation documentation, Podman policies

**Implementation Order:**
1. Kubernetes control plane security (highest impact)
2. Network segmentation (prevents lateral movement)
3. API security headers (OWASP A05:2021)
4. Systemd service hardening (attack surface reduction)
5. Container scanning (supply chain security)
6. Documentation (secrets rotation, emergency procedures)

---

## Task 1: Enable Kubernetes Pod Security Admission

**Files:**
- Modify: `/etc/nixos/modules/services/kubernetes.nix`
- Create: `/etc/nixos/docs/security/pod-security-admission.md` (documentation)

**Step 1: Add PSA configuration to Kubernetes module**

Add to `services.kubernetes.apiserver` section:

```nix
# In modules/services/kubernetes.nix, find the apiserver configuration block
apiserver = {
  serviceAccountSigningKeyFile = lib.mkForce "/etc/kubernetes/service-account-key.pem";
  serviceAccountKeyFile = lib.mkForce "/etc/kubernetes/service-account-key.pem";
  enable = isMaster;
  bindAddress = config.services.kubernetes-module.masterAddress;
  securePort = 6443;
  allowPrivileged = true;

  # Pod Security Admission Configuration
  podSecurityAdmissionControl = {
    enable = true;
  };

  # Run with PSA enabled
  extraArgs = [
    "--pod-security-admission-config-file=/etc/kubernetes/pod-security-admission.yaml"
  ];
};
```

**Step 2: Create PSA config file**

Add to `environment.etc` in kubernetes.nix:

```nix
environment.etc."kubernetes/pod-security-admission.yaml".text = ''
  apiVersion: pod-security.admission.config.k8s.io/v1
  kind: PodSecurityConfiguration
  defaults:
    enforce: "restricted"
    enforce-version: "latest"
    audit: "restricted"
    audit-version: "latest"
    warn: "restricted"
    warn-version: "latest"
  exemptions:
    namespaces: []
    runtimeClasses: []
    usernames: []
'';
```

**Step 3: Create documentation**

Create `/etc/nixos/docs/security/pod-security-admission.md`:

```markdown
# Pod Security Admission Configuration

## Policy Level: Restricted

The cluster enforces the `restricted` Pod Security Standard by default.

## What This Prevents

- Privileged pods
- Host PID/IPC namespace sharing
- Arbitrary capabilities
- Root containers
- Host network access

## Exemptions

Currently no exemptions. Add exemptions via `exemptions` in PSA config if needed.

## Validation

```bash
# Test PSA is working
kubectl run test-pod --image=nginx --privileged=false
# Should succeed

kubectl run test-pod-privileged --image=nginx --privileged=true
# Should fail with "pod violates PodSecurity "restricted:latest"
```

## References

- https://kubernetes.io/docs/concepts/security/pod-security-admission/
- https://kubernetes.io/docs/concepts/security/pod-security-standards/
```

**Step 4: Test configuration**

Run: `nixos-rebuild build --fast`
Expected: Build succeeds, no PSA configuration errors

**Step 5: Commit**

```bash
git add modules/services/kubernetes.nix docs/security/pod-security-admission.md
git commit -m "feat(kubernetes): enable Pod Security Admission with restricted baseline"
```

---

## Task 2: Implement Kubernetes Network Policies (Deny-All Baseline)

**Files:**
- Create: `/etc/nixos/docs/kubernetes/network-policies/README.md`
- Create: `/etc/nixos/docs/kubernetes/network-policies/default-deny.yaml`
- Create: `/etc/nixos/docs/kubernetes/network-policies/dns-allow.yaml`
- Create: `/etc/nixos/docs/kubernetes/network-policies/ingress-allow.yaml`

**Step 1: Create default-deny policy**

Create `/etc/nixos/docs/kubernetes/network-policies/default-deny.yaml`:

```yaml
# Default deny-all network policy
# All pods must have explicit allow rules
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**Step 2: Create DNS allow policy**

Create `/etc/nixos/docs/kubernetes/network-policies/dns-allow.yaml`:

```yaml
# Allow DNS resolution (required for cluster operation)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
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
```

**Step 3: Create ingress allow policy**

Create `/etc/nixos/docs/kubernetes/network-policies/ingress-allow.yaml`:

```yaml
# Allow ingress from ingress controller
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: myapp  # Replace with actual labels
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
```

**Step 4: Create README**

Create `/etc/nixos/docs/kubernetes/network-policies/README.md`:

```markdown
# Kubernetes Network Policies

## Architecture: Default Deny with Explicit Allow

This implements a zero-trust network model where all pod-to-pod communication is denied by default.

## Applying Policies

```bash
# Apply in order
kubectl apply -f default-deny.yaml
kubectl apply -f dns-allow.yaml
kubectl apply -f ingress-allow.yaml
```

## Testing

```bash
# Apply policies
kubectl apply -f docs/kubernetes/network-policies/

# Test connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default

# Create two test pods to verify isolation
kubectl run pod-a --image=nginx --labels=app=test-a
kubectl run pod-b --image=busybox --labels=app=test-b --rm -it --restart=Never -- wget --timeout=2 pod-a -O-
# Should timeout (no connectivity)
```

## Per-Application Policies

Each application needs its own network policy. Use the templates as a starting point.
```

**Step 5: Commit**

```bash
git add docs/kubernetes/network-policies/
git commit -m "feat(kubernetes): add network policies (deny-all baseline)"
```

---

## Task 3: Disable Service Account Token Auto-Mount

**Files:**
- Create: `/etc/nixos/docs/kubernetes/service-account-security.md`
- Modify: `/etc/nixos/modules/services/kubernetes.nix` (add documentation reference)

**Step 1: Create documentation**

Create `/etc/nixos/docs/kubernetes/service-account-security.md`:

```markdown
# Service Account Token Security

## Policy: Explicit Token Mounting Only

Service account tokens are NOT auto-mounted to pods by default. This follows OWASP A01:2021 (Broken Access Control).

## Implementation

For each pod/deployment that needs a service account token:

```yaml
spec:
  template:
    spec:
      automountServiceAccountToken: false  # Default to false
      # Only enable if actually needed:
      # automountServiceAccountToken: true
```

## When to Enable

- Pod needs to communicate with Kubernetes API
- Pod uses controllers/operators
- Pod uses Kubernetes client libraries

## Testing

```yaml
# Test pod without token
apiVersion: v1
kind: Pod
metadata:
  name: test-no-token
spec:
  automountServiceAccountToken: false
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "ls /var/run/secrets/kubernetes.io/serviceaccount/ && exit 1 || exit 0"]
```

Apply with:
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-no-token
spec:
  automountServiceAccountToken: false
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "test ! -f /var/run/secrets/kubernetes.io/serviceaccount/token"]
EOF
```

## References

- https://kubernetes.io/docs/concepts/configuration/pod-configuration-service-account/
- https://owasp.org/Top10/A01_2021-Broken_Access_Control/
```

**Step 2: Update Kubernetes module documentation**

Add comment to kubernetes.nix:

```nix
# Service Account Security
# Note: Service account tokens are NOT auto-mounted by default.
# Set automountServiceAccountToken: false in pod specs unless needed.
# See: docs/kubernetes/service-account-security.md
```

**Step 3: Commit**

```bash
git add docs/kubernetes/service-account-security.md modules/services/kubernetes.nix
git commit -m "docs(kubernetes): add service account token security guidelines"
```

---

## Task 4: Add API Security Headers to Caddy

**Files:**
- Modify: `/etc/nixos/modules/services/caddy.nix`
- Create: `/etc/nixos/docs/security/api-headers.md`

**Step 1: Add security headers to Caddy configuration**

In the Caddy virtualHosts configuration, add security headers:

```nix
# In modules/services/caddy.nix, add to each virtualHost
virtualHosts."<hostname>".extraConfig = ''
  # Security Headers (OWASP A05:2021)
  header {
    # Prevent clickjacking
    X-Frame-Options "DENY"
    # Prevent MIME type sniffing
    X-Content-Type-Options "nosniff"
    # Enable XSS protection (legacy browsers)
    X-XSS-Protection "1; mode=block"
    # Referrer policy
    Referrer-Policy "no-referrer"
    # Content Security Policy
    Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
    # HSTS (only enable after testing)
    # Strict-Transport-Security "max-age=31536000; includeSubDomains"
  }
'';
```

**Step 2: Create documentation**

Create `/etc/nixos/docs/security/api-headers.md`:

```markdown
# API Security Headers

## Implemented Headers

| Header | Value | Purpose |
|--------|-------|---------|
| X-Frame-Options | DENY | Prevents clickjacking |
| X-Content-Type-Options | nosniff | Prevents MIME sniffing |
| X-XSS-Protection | 1; mode=block | XSS filtering |
| Referrer-Policy | no-referrer | Privacy protection |
| Content-Security-Policy | default-src 'self' | XSS prevention |

## HSTS Status

Currently commented out. Enable after:
1. Confirming HTTPS works correctly
2. No mixed content issues
3. Testing with all clients

## Testing

```bash
# Verify headers are set
curl -I https://your-domain.com | grep -E "X-Frame-Options|X-Content-Type-Options|Content-Security-Policy"
```

## References

- https://owasp.org/www-project-secure-headers/
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers
```

**Step 3: Test configuration**

Run: `nixos-rebuild build --fast`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add modules/services/caddy.nix docs/security/api-headers.md
git commit -m "feat(security): add OWASP security headers to Caddy"
```

---

## Task 5: Harden Remaining Systemd Services

**Files:**
- Modify: `/etc/nixos/modules/services/caddy.nix`
- Modify: `/etc/nixos/modules/services/nextcloud.nix`
- Modify: `/etc/nixos/modules/services/glitchtip-selfhosted.nix`
- Create: `/etc/nixos/docs/MODULE_STRUCTURE.md` update

**Step 1: Harden Caddy service**

Add to caddy.nix systemd service:

```nix
systemd.services.caddy = {
  serviceConfig = {
    # Security hardening
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    RestrictRealtime = true;
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
    # Caddy needs network access
    AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
  };
};
```

**Step 2: Harden Nextcloud services**

Add to nextcloud.nix:

```nix
systemd.services.nextcloud-setup = {
  serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    RestrictRealtime = true;
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
  };
};

systemd.services.php-fpm-nextcloud = {
  serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    RestrictRealtime = true;
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
  };
};
```

**Step 3: Harden GlitchTip services**

Add to glitchtip-selfhosted.nix:

```nix
systemd.services.glitchtip-web = {
  serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    RestrictRealtime = true;
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
  };
};

systemd.services.glitchtip-worker = {
  serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    RestrictRealtime = true;
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
  };
};
```

**Step 4: Update MODULE_STRUCTURE.md**

Add to best practices summary:

```markdown
### Systemd Service Security Hardening Pattern

All systemd services should include:

```nix
systemd.services.<service-name> = {
  serviceConfig = {
    NoNewPrivileges = true;           # Prevent privilege escalation
    PrivateTmp = true;                # Isolate /tmp
    ProtectSystem = "strict";         # Read-only system dirs
    ProtectHome = true;               # Hide home directories
    RestrictRealtime = true;          # Prevent real-time priority abuse
    RestrictAddressFamilies = [       # Limit socket types
      "AF_UNIX" "AF_INET" "AF_INET6"  # Adjust for service needs
    ];
  };
};
```

**Exceptions:**
- Services needing raw sockets: Add "AF_PACKET"
- Services needing filesystem access: Add ReadWritePaths
- Services binding privileged ports: Add AmbientCapabilities = ["CAP_NET_BIND_SERVICE"]
```

**Step 5: Test configuration**

Run: `nixos-rebuild build --fast`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add modules/services/caddy.nix modules/services/nextcloud.nix modules/services/glitchtip-selfhosted.nix modules/MODULE_STRUCTURE.md
git commit -m "feat(security): add systemd hardening to remaining services"
```

---

## Task 6: Implement Container Image Scanning with Trivy

**Files:**
- Create: `/etc/nixos/modules/services/container-scanning.nix`
- Create: `/etc/nixos/docs/security/container-scanning.md`
- Create: `/etc/nixos/justfile` update (add scan commands)

**Step 1: Create container scanning module**

Create `/etc/nixos/modules/services/container-scanning.nix`:

```nix
# Container Image Vulnerability Scanning
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.container-scanning = {
    enable = lib.mkEnableOption "Container vulnerability scanning with Trivy";
  };

  config = lib.mkIf config.services.container-scanning.enable {
    # Install Trivy
    environment.systemPackages = with pkgs; [
      trivy
    ];

    # Periodic scanning service
    systemd.services.trivy-scan = {
      description = "Scan container images for vulnerabilities";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/run/current-system/sw/bin/trivy image --severity HIGH,CRITICAL localhost:5000/myapp:latest";
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET"];
      };
    };

    # Weekly scan timer
    systemd.timers.trivy-scan = {
      description = "Weekly container vulnerability scan";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
  };
}
```

**Step 2: Create documentation**

Create `/etc/nixos/docs/security/container-scanning.md`:

```markdown
# Container Image Vulnerability Scanning

## Tool: Trivy

Trivy scans container images for known vulnerabilities (CVEs).

## Usage

### Scan an image

```bash
# Scan local image
trivy image nginx:latest

# Scan with severity filter
trivy image --severity HIGH,CRITICAL nginx:latest

# Scan and output JSON
trivy image --format json --output report.json nginx:latest
```

### Scan running containers

```bash
# Scan all running containers
trivy image --skip-db-update $(docker ps -q)

# Scan specific container
trivy image $(docker inspect --format='{{.Config.Image}}' <container-name>)
```

### CI/CD Integration

Add to CI pipeline:

```yaml
- name: Scan image
  run: |
    trivy image --severity HIGH,CRITICAL --exit-code 1 myapp:${{ github.sha }}
```

## Scanning Schedule

Automatic weekly scan enabled via systemd timer.

## Remediation

When vulnerabilities are found:
1. Update base image to latest version
2. Rebuild application image
3. Rescan to verify fixes

## References

- https://aquasecurity.github.io/trivy/
- https://owasp.org/Top10/A05_2021-Security_Misconfiguration/
```

**Step 3: Add justfile commands**

Add to justfile:

```makefile
# Container scanning
scan-containers:
    trivy image --severity HIGH,CRITICAL $(docker ps --format '{{.Image}}')

scan-image IMAGE:
    trivy image --severity HIGH,CRITICAL {{IMAGE}}

scan-k8s:
    kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.nodeName}{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}' | \
    while read node namespace name images; do
        for img in $images; do
            echo "Scanning $namespace/$name: $img"
            trivy image --severity HIGH,CRITICAL "$img" || true
        done
    done
```

**Step 4: Enable in configuration**

Add to host configuration (e.g., `/etc/nixos/hosts/zephyr/configuration.nix`):

```nix
{config, ...}: {
  imports = [
    ../../modules/services/container-scanning.nix
  ];

  services.container-scanning.enable = true;
}
```

**Step 5: Test**

Run: `trivy --version`
Expected: Trivy version output

**Step 6: Commit**

```bash
git add modules/services/container-scanning.nix docs/security/container-scanning.md justfile
git commit -m "feat(security): add container vulnerability scanning with Trivy"
```

---

## Task 7: Create Secrets Rotation Documentation

**Files:**
- Create: `/etc/nixos/docs/security/secrets-rotation.md`
- Create: `/etc/nixos/docs/security/emergency-access.md`

**Step 1: Create secrets rotation guide**

Create `/etc/nixos/docs/security/secrets-rotation.md`:

```markdown
# Secrets Rotation Procedures

## Overview

This document describes procedures for rotating encrypted secrets managed by Agenix.

## Rotation Procedure

### Step 1: Generate new secret value

```bash
# Example: generate new API key
openssl rand -base64 32
```

### Step 2: Re-encrypt with Agenix

```bash
# Edit the secret file
agenix -e secrets/huggingface-token.age --edit
# Replace with new value, save
```

### Step 3: Rebuild and deploy

```bash
just deploy
```

### Step 4: Verify new secret is in use

```bash
# Check service logs for authentication success
journalctl -u <service-name> -f
```

### Step 5: Invalidate old secret (if applicable)

- Revoke old API key via provider dashboard
- Delete old credentials from external systems

## Rotation Schedule

| Secret | Rotation Period | Last Rotated | Next Due |
|--------|----------------|--------------|----------|
| Hugging Face token | 90 days | TBD | TBD |
| LM Studio API key | 90 days | TBD | TBD |
| ZAI API key | 90 days | TBD | TBD |
| Grafana admin password | 180 days | TBD | TBD |
| Tailscale API key | 90 days | TBD | TBD |

## Automating Rotation

Future enhancement: Use GitHub Actions to:
1. Generate new secrets
2. Re-encrypt with Agenix
3. Open PR for rotation
4. Deploy after approval

## References

- https://github.com/ryantm/agenix
- https://owasp.org/Top10/A07_2021-Identification_and_Authentication_Failures/
```

**Step 2: Create emergency access guide**

Create `/etc/nixos/docs/security/emergency-access.md`:

```markdown
# Emergency Access Procedures

## Scenario: Tailscale Service Down

### Symptoms
- Cannot SSH via Tailscale
- `tailscale status` fails
- Services unreachable via Tailscale IPs

### Recovery Steps

1. **Physical console access**
   - Connect monitor and keyboard to affected host
   - Login with local user account

2. **Restart Tailscale**
   ```bash
   sudo systemctl restart tailscaled
   ```

3. **Check Tailscale status**
   ```bash
   sudo tailscale status
   ```

4. **If still down, check network**
   ```bash
   ip a
   ping 10.1.1.1  # Gateway
   ```

5. **Fallback: Local network access**
   - Connect to local network (10.1.1.0/24)
   - SSH directly to host IP:
     ```bash
     ssh j_kro@10.1.1.110  # Zephyr
     ```

## Scenario: Kubernetes Control Plane Unreachable

### Symptoms
- `kubectl get nodes` fails
- Cannot access cluster services
- API server unreachable

### Recovery Steps

1. **Check control plane status**
   ```bash
   sudo systemctl status kube-apiserver
   sudo systemctl status etcd
   ```

2. **Restart control plane**
   ```bash
   sudo systemctl restart kube-apiserver
   sudo systemctl restart etcd
   ```

3. **Check etcd health**
   ```bash
   sudo etcdctl endpoint health --endpoints=http://10.1.1.110:2379
   ```

4. **Restore from backup if needed**
   ```bash
   # Follow etcd restore procedure
   sudo etcdctl snapshot restore /backup/etcd-snapshot.db
   ```

## Scenario: Storage Failure

### Symptoms
- Services cannot access persistent data
- Mount errors in logs
- High disk usage on /tmp

### Recovery Steps

1. **Check storage status**
   ```bash
   df -h
   mount | grep nfs
   ```

2. **Restart NFS services**
   ```bash
   sudo systemctl restart nfs-client.target
   ```

3. **Manual mount if needed**
   ```bash
   sudo mount -t nfs 10.1.1.120:/data /var/lib/nfs-data
   ```

## Emergency Contacts

- Primary Admin: j_kro
- Backup Location: Local console access only
- Documentation: /etc/nixos/docs/security/
```

**Step 3: Commit**

```bash
git add docs/security/secrets-rotation.md docs/security/emergency-access.md
git commit -m "docs(security): add secrets rotation and emergency access procedures"
```

---

## Task 8: Create Implementation Summary and Update Documentation

**Files:**
- Create: `/etc/nixos/docs/security/HARDENING_SUMMARY.md`
- Modify: `/etc/nixos/docs/security/SECURITY_AUDIT_REPORT.md` (mark items as implemented)

**Step 1: Create hardening summary**

Create `/etc/nixos/docs/security/HARDENING_SUMMARY.md`:

```markdown
# Security Hardening Implementation Summary

**Date:** 2026-03-09
**Status:** Complete
**Audit Reference:** docs/security/SECURITY_AUDIT_REPORT.md

## Implemented Hardening

### Kubernetes Control Plane (HIGH Priority)

| Item | Status | Reference |
|------|--------|-----------|
| Pod Security Admission | ✅ Implemented | modules/services/kubernetes.nix |
| Network Policies | ✅ Implemented | docs/kubernetes/network-policies/ |
| Service Account Token Binding | ✅ Documented | docs/kubernetes/service-account-security.md |

### API Security (HIGH Priority)

| Item | Status | Reference |
|------|--------|-----------|
| Security Headers | ✅ Implemented | modules/services/caddy.nix |

### Systemd Services (MEDIUM Priority)

| Item | Status | Reference |
|------|--------|-----------|
| Caddy Hardening | ✅ Implemented | modules/services/caddy.nix |
| Nextcloud Hardening | ✅ Implemented | modules/services/nextcloud.nix |
| GlitchTip Hardening | ✅ Implemented | modules/services/glitchtip-selfhosted.nix |

### Container Security (MEDIUM Priority)

| Item | Status | Reference |
|------|--------|-----------|
| Image Scanning | ✅ Implemented | modules/services/container-scanning.nix |

### Documentation (MEDIUM Priority)

| Item | Status | Reference |
|------|--------|-----------|
| Secrets Rotation | ✅ Documented | docs/security/secrets-rotation.md |
| Emergency Access | ✅ Documented | docs/security/emergency-access.md |

## Pending (Future Work)

### High Priority
- [ ] Container image signing (sigstore/cosign)
- [ ] API request validation schemas
- [ ] Restrict service bind addresses

### Medium Priority
- [ ] Podman security policies
- [ ] etcd certificate rotation
- [ ] Kubernetes ResourceQuota/LimitRange
- [ ] API audit logging
- [ ] IDS/IPS (Suricata)
- [ ] eBPF monitoring

### Low Priority
- [ ] Tailscale MFA
- [ ] Secrets audit trail
- [ ] Build artifact caching

## Testing Checklist

- [ ] Kubernetes cluster reboots successfully
- [ ] `kubectl get nodes` shows Ready status
- [ ] Network policies applied successfully
- [ ] PSA blocks privileged pods
- [ ] Security headers visible in HTTP responses
- [ ] Trivy scans images without errors
- [ ] All services start after hardening

## Rollback

If issues occur:
```bash
# Revert to previous commit
git revert HEAD

# Rebuild
just switch
```

## References

- Original Audit: docs/security/SECURITY_AUDIT_REPORT.md
- OWASP Top 10: https://owasp.org/Top10/
- Kubernetes PSS: https://kubernetes.io/docs/concepts/security/pod-security-standards/
```

**Step 2: Update security audit report**

Add to `/etc/nixos/docs/security/SECURITY_AUDIT_REPORT.md`:

```markdown
## Implementation Status (Updated 2026-03-09)

### Completed ✅

- [x] Kubernetes Pod Security Admission
- [x] Kubernetes Network Policies (deny-all baseline)
- [x] Service Account Token Security documentation
- [x] API Security Headers (Caddy)
- [x] Systemd hardening (Caddy, Nextcloud, GlitchTip)
- [x] Container vulnerability scanning (Trivy)
- [x] Secrets rotation documentation
- [x] Emergency access procedures

### In Progress 🔄

- [ ] Container image signing

### Pending 📋

See "Prioritized Action Plan" section above.
```

**Step 3: Update CLAUDE.md with security references**

Add to CLAUDE.md:

```markdown
## Security

### Documentation
- `docs/security/SECURITY_AUDIT_REPORT.md` - Comprehensive security audit
- `docs/security/HARDENING_SUMMARY.md` - Implementation status
- `docs/kubernetes/network-policies/` - Network policy templates
- `docs/security/secrets-rotation.md` - Rotation procedures
- `docs/security/emergency-access.md` - Emergency procedures

### Commands
```bash
just scan-containers  # Scan running containers for vulnerabilities
just scan-image IMAGE # Scan specific image
```
```

**Step 4: Commit**

```bash
git add docs/security/HARDENING_SUMMARY.md docs/security/SECURITY_AUDIT_REPORT.md CLAUDE.md
git commit -m "docs(security): add hardening implementation summary"
```

---

## Task 9: Final Testing and Verification

**Step 1: Build configuration**

Run: `nixos-rebuild build --fast`
Expected: Build succeeds without errors

**Step 2: Test locally (on Zephyr)**

Run: `sudo nixos-rebuild test`
Expected: All services start successfully

**Step 3: Verify Kubernetes**

```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl apply -f docs/kubernetes/network-policies/
```

**Step 4: Verify security headers**

```bash
curl -I https://localhost | grep -E "X-Frame-Options|Content-Security-Policy"
```

**Step 5: Verify Trivy**

```bash
trivy image --severity HIGH,CRITICAL nginx:alpine
```

**Step 6: Final commit**

```bash
git add -A
git commit -m "feat(security): complete hardening implementation - all HIGH/MEDIUM items addressed"
```

---

## Execution Notes

### Order Matters
1. Kubernetes changes first (control plane stability)
2. Network policies second (test thoroughly before proceeding)
3. Service hardening (one service at a time)
4. Container scanning (independent)
5. Documentation (can be done anytime)

### Testing Between Tasks
After each task:
1. `nixos-rebuild build --fast`
2. If build succeeds, commit
3. If build fails, fix before proceeding

### Rollback Plan
Each task is independently commit-able. If any task causes issues:
```bash
git revert HEAD  # Rollback last change
just switch       # Apply rollback
```

---

## References

- Security Audit: `/etc/nixos/docs/security/SECURITY_AUDIT_REPORT.md`
- NixOS Manual: https://nixos.org/manual/nixos/stable/
- Kubernetes PSS: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- OWASP Top 10: https://owasp.org/Top10/
