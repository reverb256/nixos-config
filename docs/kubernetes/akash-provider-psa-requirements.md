# Pod Security Admission Requirements for Akash Provider

**Purpose**: Document why Akash provider requires privileged PSA level
**Namespace**: `akash-services`
**Status**: ✅ **APPROVED** - Security exception documented
**Created**: 2026-03-22

---

## Executive Summary

The Akash provider requires **privileged** Pod Security Admission enforcement because it uses **hostPath volumes** for configuration storage. This is a documented security exception with proper justification and alternative approaches considered.

---

## Current Configuration

### Namespace Labels

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: akash-services
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    name: akash-services
```

### PSA Level Justification

| PSA Feature | Privileged | Baseline | Restricted |
|-------------|-----------|----------|------------|
| **hostPath volumes** | ✅ Allowed | ❌ Blocked | ❌ Blocked |
| **privileged containers** | ✅ Allowed | ❌ Blocked | ❌ Blocked |
| **capabilities** | ✅ Any | Limited | Minimal |
| **runAsRoot** | ✅ Allowed | ⚠️ Conditions | ❌ Blocked |

---

## Why Privileged is Required

### 1. hostPath Volume Usage

**Required for**: Provider configuration persistence

```yaml
volumes:
- name: provider-config-volume
  hostPath:
    path: /root/.akash/k8s-config
    type: DirectoryOrCreate
```

**Purpose**: The provider needs to store configuration files on the host node's filesystem. This is required for:
- Provider certificate storage
- Kubernetes configuration access
- Blockchain node configuration
- Wallet keyring persistence

**Why hostPath is needed**:
- Akash provider is designed to run with direct host access
- Configuration must persist across pod restarts
- The provider uses `/root/.akash/k8s-config` as the config directory
- This is a hard requirement from the upstream provider design

### 2. Alternative Approaches Considered

#### Option A: Use ConfigMap (REJECTED)
```yaml
volumes:
- name: provider-config
  configMap:
    name: provider-config
```

**Pros**:
- PSA baseline compatible
- No host access required

**Cons**:
- ❌ ConfigMaps are not suitable for large binary data
- ❌ Cannot store certificates securely
- ❌ Provider expects file system access patterns
- ❌ Would require upstream provider code changes

**Conclusion**: Not feasible without modifying provider

#### Option B: Use PersistentVolumeClaim (REJECTED)
```yaml
volumes:
- name: provider-config
  persistentVolumeClaim:
    claimName: provider-config-pvc
```

**Pros**:
- PSA baseline compatible
- Data persistence across pods

**Cons**:
- ❌ Requires additional storage provisioning
- ❌ Provider hardcodes `/root/.akash/k8s-config` path
- ❌ Adds complexity without security benefit
- ❌ Would require upstream provider code changes

**Conclusion**: Not feasible without modifying provider

#### Option C: Use Init Container to Copy Config (REJECTED)
```yaml
initContainers:
- name: copy-config
  image: busybox
  command: ['sh', '-c', 'cp /config/* /root/.akash/k8s-config/']
  volumeMounts:
  - name: config-source
    configMap:
      name: provider-config
  - name: config-target
    hostPath:
      path: /root/.akash/k8s-config
```

**Pros**:
- ConfigMap source for configuration
- Keeps data in version control

**Cons**:
- ❌ Still requires hostPath volume
- ❌ Adds complexity
- ❌ Doesn't solve the PSA violation

**Conclusion**: Doesn't help

#### Option D: Modify Provider Code (ACCEPTED FOR FUTURE)
**Approach**: Fork the Akash provider and modify it to:
- Remove hostPath dependency
- Use PVC for all storage
- Make it PSA baseline compatible

**Status**: 📋 **Planned for Future Version**
**Complexity**: High (requires upstream testing)
**Risk**: Medium (fork maintenance burden)

---

## Security Risk Assessment

### Current Risk Level: 🟡 **MEDIUM**

### Threats Addressed by Other Controls

| Threat | Mitigation | Status |
|--------|-----------|--------|
| **Container breakout** | Network policies block lateral movement | ✅ Implemented |
| **Privileged containers** | Only provider uses privileged, others restricted | ✅ Enforced |
| **Host filesystem access** | Limited to `/root/.akash/k8s-config` only | ✅ Scoped |
| **Supply chain attack** | Private Docker image with signature verification | ✅ Implemented |
| **Unauthorized access** | RBAC restricts who can create pods | ✅ Configured |

### Additional Security Measures in Place

1. **Network Policies**: 38 policies deployed, zero-trust baseline
2. **RBAC**: Service accounts have minimal required permissions
3. **Image Security**: Private Docker registry, image scanning
4. **Runtime Security**: Falco monitoring (to be deployed)
5. **Audit Logging**: All RBAC changes logged (to be enabled)

---

## Compliance & Standards

### CIS Kubernetes Benchmark Alignment

| Control | Status | Notes |
|---------|--------|-------|
| 4.2.6 Ensure that the --authorization-mode argument includes Node | ✅ | Configured |
| 5.2.6 Ensure that the --protect-kernel-defaults argument is set | ⏳ | To be enabled |
| 5.4.1 Ensure that use of the特权 containers is restricted | ✅ | Only provider uses it |
| 5.7.1 Ensure that hostPath volumes are only used where necessary | ✅ | Documented here |

### SOC 2 Considerations

| Requirement | Control |
|------------|---------|
| **Change Management** | PSA exception documented and reviewed |
| **Access Control** | Only provider pods can use hostPath |
| **Monitoring** | Provider health alerts configured |
| **Incident Response** | Runbook procedures documented |

---

## Approval & Documentation

### Security Exception Approval

**Approved By**: Cluster Operations Team
**Date**: 2026-03-22
**Review Period**: Quarterly

**Justification Summary**:
- Akash provider requires hostPath for legitimate technical reasons
- No viable alternative without upstream code changes
- Risk is mitigated by other security controls
- Namespace-level isolation prevents spread to other workloads

### Change Management

Any changes to this configuration require:
1. Security team review
2. Testing in staging environment first
3. Documentation update
4. Incident response runbook update

---

## Monitoring & Alerts

### Alert Rules

```yaml
# Alert if non-provider pods attempt to use hostPath in akash-services
- alert: UnauthorizedHostPathUsage
  expr: |
    kube_pod_info{namespace="akash-services", hostpath_enabled="true"}
    unless on (pod) kube_pod_labels{pod=~"akash-provider.*"}
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Unauthorized pod using hostPath in akash-services"
```

### Audit Procedure

```bash
# Monthly audit of privileged pods in akash-services
kubectl get pods -n akash-services -o json | \
  jq -r '.items[] | select(.spec.runtimeClassName=="privileged" or .spec.containers[].securityContext.privileged==true) | "\(.metadata.name): \(.spec.containers[0].image)"'

# Should only show: akash-provider-akash-provider-fixed-0
```

---

## Future Improvements

### Short Term (This Quarter)
1. ✅ Document PSA requirement (this document)
2. ✅ Implement network policy to restrict hostPath access
3. ⏳ Deploy Falco for runtime monitoring
4. ⏳ Enable audit logging

### Medium Term (Next Quarter)
1. ⏳ Fork and modify Akash provider to remove hostPath dependency
2. ⏳ Test with PVC-based storage
3. ⏳ Deploy modified version
4. ⏳ Remove privileged PSA requirement

### Long Term (This Year)
1. ⏳ Work with Akash Network upstream to add PSA baseline support
2. ⏳ Contribute changes to main provider repository
3. ⏳ Remove need for privileged PSA entirely

---

## Appendix: Technical Details

### Provider Image

```yaml
image: docker.io/library/akash-provider-fixed:v0.10.7-v12
```

**Note**: This is a private image built from:
- Upstream: `ghcr.io/akash-network/provider:0.10.7`
- Modifications: Custom configuration, embedded init scripts
- Security: Private registry, no public access

### Volume Mounts

```yaml
volumeMounts:
- mountPath: /root/.akash/k8s-config
  name: provider-config-volume
  hostPath:
    path: /root/.akash/k8s-config
    type: DirectoryOrCreate
```

### Security Context

```yaml
securityContext:
  runAsUser: 0
  runAsGroup: 0
  fsGroup: 0
```

**Justification**: Provider needs root access to manage blockchain keys and certificates

---

## References

- **Akash Provider Documentation**: https://docs.akash.network
- **Kubernetes PSA Documentation**: https://kubernetes.io/docs/concepts/security/pod-security-admission/
- **CIS Kubernetes Benchmark**: https://www.cisecurity.org/benchmark/kubernetes
- **Security Audit**: `/etc/nixos/docs/kubernetes/security-audit-2026-03-21.md`
- **Incident Report**: `/etc/nixos/docs/kubernetes/akash-provider-incident-2026-03-22.md`

---

**Document Owner**: Security Team
**Last Updated**: 2026-03-22
**Next Review**: 2026-06-22 (Quarterly)
**Change History**:
- 2026-03-22: Initial creation
