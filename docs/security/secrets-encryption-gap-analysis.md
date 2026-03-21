# Kubernetes Secrets Encryption Gap Analysis

**Date**: 2026-03-21
**Status**: ⚠️ **NOT IMPLEMENTED** - Security Gap Identified
**Priority**: HIGH - Critical data protection

---

## Current Status

❌ **Secrets are NOT encrypted at rest in etcd**

**Verification**:
```bash
# Check for encryption provider config
grep -r 'encryption-provider-config' /etc/kubernetes/
# Result: No encryption config found

# Check kube-apiserver process flags
ps aux | grep kube-apiserver | grep 'encryption-provider-config'
# Result: Only returns grep command itself (not enabled)
```

---

## Security Impact

### Risk Assessment
**Severity**: HIGH

**What's at risk**:
- All Kubernetes secrets stored in plain text in etcd
- Service account tokens
- API keys (Cloudflare, Akash, Zai API keys)
- Database credentials (GlitchTip PostgreSQL, Redis)
- Application secrets (SearXNG secret key, AI gateway tokens)

**Attack scenario**:
1. Attacker gains access to etcd data directory
2. Reads `etcd/db` files directly
3. Extracts all secrets in plain text
4. Uses credentials to access services, deploy malicious containers, exfiltrate data

**Real-world impact**:
- Complete cluster compromise
- Data breach of user data
- Unauthorized resource usage (mining, GPU compute)
- Supply chain attack (deploy malicious images)

---

## Implementation Plan

### Phase 1: Generate Encryption Key (1 hour)

```bash
# Generate 32-byte AES key
head -c 32 /dev/urandom | base64

# Output example:
# YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXl6MDEyMzQ1Njc4OQ==
```

### Phase 2: Create EncryptionConfig (2 hours)

**File**: `/etc/kubernetes/encryption-config.yaml`
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
          - name: key1
            secret: <BASE64-ENCODED-KEY-HERE>
```

**Location**: Store securely on all control plane nodes (zephyr)

### Phase 3: Update Kube-Apiserver Configuration (3 hours)

**NixOS Configuration**: `modules/services/kubernetes.nix`
```nix
services.kubernetes.apiserver = {
  enable = true;
  extraArgs = [
    "--encryption-provider-config=/etc/kubernetes/encryption-config.yaml"
  ];
};
```

**Add to flake**:
```nix
# Add encryption config to system activation
environment.etc."kubernetes/encryption-config.yaml".source = ./encryption-config.yaml;
```

### Phase 4: Rollout Encryption (4 hours)

```bash
# 1. Apply encryption config to all control plane nodes
just deploy  # NixOS rebuild with encryption config

# 2. Restart kube-apiserver (one node at a time)
ssh zephyr "systemctl restart kube-apiserver"

# 3. Verify encryption is active
kubectl get secrets --all-namespaces | head -5

# 4. Re-encrypt all existing secrets
kubectl get secrets --all-namespaces -o json | \
  kubectl replace -f -

# 5. Verify all secrets are encrypted
etcdctl get /registry/secrets/default/... --keys-only
# Should show: k8s:enc:aescbc:v1:key1:...
```

---

## Testing & Verification

### Pre-Implementation Tests
```bash
# 1. Backup etcd (critical!)
etcdctl snapshot save /backup/etcd-pre-encryption-$(date +%Y%m%d)

# 2. Test cluster connectivity
kubectl get nodes
kubectl get pods --all-namespaces

# 3. List current secrets
kubectl get secrets --all-namespaces | wc -l
# Note: Count for post-encryption verification
```

### Post-Implementation Tests
```bash
# 1. Verify secrets are encrypted
ETCDCTL_API=3 etcdctl get /registry/secrets/ --prefix --keys-only
# Expected: k8s:enc:aescbc:v1:key1:...

# 2. Test secret creation
kubectl create secret generic test-secret \
  --from-literal=key=value \
  --dry-run=client

# 3. Verify secret is encrypted at rest
etcdctl get /registry/secrets/default/test-secret
# Expected: k8s:enc:aescbc:v1:key1:<encrypted-data>

# 4. Test secret decryption (runtime)
kubectl run test-pod --rm -it --restart=Never \
  --image=busybox \
  -- sh -c 'echo $TEST_SECRET'

# 5. Verify all pods still running
kubectl get pods --all-namespaces | grep -v Running
```

---

## Rollback Plan

**If encryption causes issues:**

```bash
# 1. Immediate rollback (remove encryption config)
# Edit /etc/kubernetes/manifests/kube-apiserver.yaml
# Remove: --encryption-provider-config=/etc/kubernetes/encryption-config.yaml

# 2. Restart apiserver
ssh zephyr "systemctl restart kube-apiserver"

# 3. Restore from backup
etcdctl snapshot restore /backup/etcd-pre-encryption-<date>

# 4. Verify cluster recovery
kubectl get nodes
kubectl get pods --all-namespaces
```

---

## Operational Considerations

### Key Rotation (Recommended: Quarterly)
```bash
# 1. Generate new key
head -c 32 /dev/urandom | base64 > /etc/kubernetes/encryption-key-v2.txt

# 2. Update encryption-config.yaml
# Add new key to providers list (secondary key)

# 3. Roll out new config
just deploy

# 4. Re-encrypt secrets with new key
kubectl get secrets --all-namespaces -o json | kubectl replace -f -

# 5. Remove old key after verification
```

### Performance Impact
- **Minimal**: AES-CBC encryption is fast (~1-2% overhead)
- **Memory**: Slight increase in apiserver memory usage
- **Startup**: First-time secret encryption adds ~30 seconds to cluster startup

### Backup Impact
- **Encrypted backups**: Can only be decrypted with same key
- **Key storage**: Store encryption key securely (Agenix, HSM, or offline)
- **Backup rotation**: Include encryption key in backup rotations

---

## Alternative: External Secrets Operator

**If etcd encryption is too complex**, consider:
```yaml
# External Secrets Operator (recommended)
- Syncs secrets from external KMS (AWS KMS, Vault, Cloud KMS)
- Never stores secrets in etcd (only references)
- Automatic rotation support
- Better audit trail

# Implementation
helm install external-secrets \
  --namespace external-secrets \
  --set env.AWS_REGION=us-east-1
```

---

## Compliance Mapping

### CIS Kubernetes Benchmark
- **Control 1.1.21**: Encrypt etcd data ✓ (would satisfy)
- **Control 1.2.7**: Encrypt secrets in transit ✓ (already done via TLS)

### NIST Cybersecurity Framework
- **Protect**: Data at rest protection ✓ (would satisfy)
- **Recover**: Secure backup procedures ✓ (with encryption)

### GDPR Article 32
- **Pseudonymization & encryption**: ✓ (would satisfy)
- **Confidentiality**: ✓ (secret protection)

---

## Next Steps

### Immediate (This Week)
1. ✅ **Document gap** (this file)
2. ⏳ **Get approval** for maintenance window
3. ⏳ **Schedule encryption rollout**

### Short-term (Next Sprint)
1. ⏳ **Generate encryption key**
2. ⏳ **Create encryption-config.yaml**
3. ⏳ **Update NixOS configuration**
4. ⏳ **Test on staging cluster**

### Long-term (Next Quarter)
1. ⏳ **Implement key rotation procedure**
2. ⏳ **Consider External Secrets Operator**
3. ⏳ **Audit secret usage quarterly**

---

## References

- **Kubernetes Documentation**: [Encrypting Secret Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- **CIS Benchmark**: Kubernetes Benchmark v1.6.0
- **NIST SP 800-53**: Cryptographic Key Management
- **etcd Encryption**: [Supported providers](https://etcd.io/docs/latest/op-guide/encryption/)

---

**Last Updated**: 2026-03-21
**Status**: ⚠️ **GAP IDENTIFIED - AWAITING IMPLEMENTATION**
**Estimated Implementation Time**: 8-10 hours
**Risk Level**: HIGH if not addressed

**Recommendation**: Implement during next maintenance window to reduce cluster exposure time.
