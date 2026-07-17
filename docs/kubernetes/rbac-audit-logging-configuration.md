# Kubernetes RBAC Audit Logging Configuration

**Purpose**: Track all RBAC changes for security monitoring and compliance
**Severity**: HIGH - From security audit 2026-03-21
**Created**: 2026-03-22

---

## Audit Logging Policy

### Phase 1: Basic RBAC Auditing (Implement Now)

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all RBAC API requests at RequestResponse level
  - level: RequestResponse
    verbs: ["create", "update", "delete", "patch"]
    resources:
    - group: "rbac.authorization.k8s.io"
      resources: ["clusterroles", "clusterrolebindings", "roles", "rolebindings"]
    - group: "certificates.k8s.io"
      resources: ["certificatesigningrequests"]

  # Log who is using anonymous access attempts
  - level: Request
    verbs: ["*"]
    resources: ["*"]
    userGroups: ["system:unauthenticated"]

  # Log all pod/exec and port-forward requests (security sensitive)
  - level: Request
    verbs: ["create", "exec", "portforward"]
    resources: ["pods"]

  # Log all configmap and secret changes (potential credentials)
  - level: RequestResponse
    verbs: ["create", "update", "delete", "patch"]
    resources: ["secrets", "configmaps"]

  # Don't log routine reads
  - level: None
    verbs: ["get", "list", "watch"]
    resources: ["*"]
```

---

## Deployment

### Step 1: Enable Audit Logging on API Server

Edit `/etc/kubernetes/manifests/kube-apiserver.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - name: kube-apiserver
    command:
    - kube-apiserver
    - --audit-log-path=/var/log/kubernetes/audit.log
    - --audit-log-maxage=30
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
    volumeMounts:
    - mountPath: /etc/kubernetes/audit-policy.yaml
      name: audit
      readOnly: true
    - mountPath: /var/log/kubernetes
      name: audit-log
  volumes:
  - hostPath:
      path: /etc/kubernetes/audit-policy.yaml
      type: File
    name: audit
  - hostPath:
      path: /var/log/kubernetes
      type: DirectoryOrCreate
    name: audit-log
```

### Step 2: Deploy Audit Policy

```bash
# Copy audit policy to all control plane nodes
scp audit-policy.yaml zephyr:/etc/kubernetes/audit-policy.yaml
scp audit-policy.yaml [other-nodes]:/etc/kubernetes/audit-policy.yaml

# Restart API server (will restart automatically)
```

### Step 3: Configure Log Aggregation

```yaml
# File: /var/lib/rancher/k3s/server/manifests/audit-logging.yaml (for K3s)
apiVersion: v1
kind: ConfigMap
metadata:
  name: audit-policy
  namespace: kube-system
data:
  policy.yaml: |
    apiVersion: audit.k8s.io/v1
    kind: Policy
    rules:
      - level: RequestResponse
        verbs: ["create", "update", "delete"]
        resources:
        - group: "rbac.authorization.k8s.io"
          resources: ["clusterrolebindings", "rolebindings"]
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: k3s-config
  namespace: kube-system
data:
  audit.yaml: |
    auditLogPath: "/var/log/k3s/audit.log"
    auditLogMaxAge: 30
    auditLogMaxBackups: 10
    auditLogMaxSize: 100
    auditPolicyFile: "/etc/rancher/k3s/audit-policy.yaml"
```

---

## Log Analysis

### Query RBAC Changes with kubectl

```bash
# View recent RBAC changes
kubectl get events --all-namespaces --field-selector reason=Created | grep -i "clusterrole\|rolebinding"

# Check who deleted cluster-admin binding
kubectl auth can-i list clusterrolebindings --all-namespaces
```

### Parse Audit Logs

```bash
# Find all ClusterRoleBinding changes
jq 'select(.objectRef.resource=="clusterrolebindings")' /var/log/kubernetes/audit.log

# Find anonymous access attempts
jq 'select(.user.username=="system:anonymous")' /var/log/kubernetes/audit.log

# Find secret/configmap changes
jq 'select(.objectRef.resource=="secrets" or .objectRef.resource=="configmaps")' /var/log/kubernetes/audit.log
```

---

## Alerting on RBAC Changes

### Prometheus Alert Rules

```yaml
# File: kubernetes-manifests/monitoring/rbac-security-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: rbac-security-alerts
  namespace: monitoring
spec:
  groups:
  - name: rbac-changes
    interval: 30s
    rules:

    # Alert: Dangerous ClusterRoleBinding created
    - alert: DangerousClusterRoleBindingCreated
      expr: |
        increase(kube_audit_total{verb="create",resource="clusterrolebindings"}[5m]) > 0
      labels:
        severity: critical
      annotations:
        summary: "New ClusterRoleBinding created"
        description: "ClusterRoleBinding {{ $labels.name }} was created by {{ $labels.user }}"

    # Alert: ClusterRoleBinding with cluster-admin
    - alert: ClusterAdminBindingCreated
      expr: |
        increase(kube_audit_total{verb="create",resource="clusterrolebindings",role_ref="cluster-admin"}[5m]) > 0
      labels:
        severity: critical
      annotations:
        summary: "NEW cluster-admin binding created!"
        description: "CRITICAL: User {{ $labels.user }} granted cluster-admin access"

    # Alert: Anonymous access attempt
    - alert: AnonymousAccessAttempt
      expr: |
        increase(kube_audit_total{user="system:anonymous",verb!="get",verb!="list"}[5m]) > 10
      labels:
        severity: warning
      annotations:
        summary: "Multiple anonymous access attempts"
        description: "{{ $value }} anonymous access attempts in last 5 minutes"

    # Alert: Secret deletion in kube-system
    - alert: SystemNamespaceSecretDeleted
      expr: |
        increase(kube_audit_total{verb="delete",resource="secrets",namespace=~"kube-.*"}[5m]) > 0
      labels:
        severity: critical
      annotations:
        summary: "Secret deleted in system namespace"
        description: "Secret {{ $labels.name }} deleted in {{ $labels.namespace }} by {{ $labels.user }}"
```

---

## Compliance Reporting

### Generate Weekly RBAC Change Report

```bash
#!/bin/bash
# File: scripts/generate-rbac-report.sh

echo "# RBAC Change Report - $(date)"
echo "Generated: $(date)"
echo ""

echo "## ClusterRoleBindings Changed This Week"
jq -r 'select(.objectRef.resource=="clusterrolebindings" and .stageTimestamp > "'$(date -d '7 days ago' -Iseconds)'") |
  "\(.stageTimestamp) \(.user.username) \(.verb) \(.objectRef.name)"' \
  /var/log/kubernetes/audit.log | sort -r

echo ""
echo "## New cluster-admin Grants"
jq -r 'select(.objectRef.resource=="clusterrolebindings" and .objectRef.name=="cluster-admin") |
  "\(.stageTimestamp) \(.user.username) \(.verb) \(.objectRef.name)"' \
  /var/log/kubernetes/audit.log | tail -10

echo ""
echo "## Anonymous Access Attempts (Top 10)"
jq -r 'select(.user.username=="system:anonymous") |
  "\(.stageTimestamp) \(.sourceIPs[0]) \().verb) \(.objectRef.resource)"' \
  /var/log/kubernetes/audit.log | tail -10
```

---

## Testing

### Test 1: Verify Audit Logging is Working

```bash
# Create a test RoleBinding
kubectl create rolebinding test-binding --clusterrole=view --serviceaccount=default:default -n default

# Check audit log
tail -f /var/log/kubernetes/audit.log | grep test-binding

# Clean up
kubectl delete rolebinding test-binding -n default
```

### Test 2: Verify Alerting

```bash
# Trigger alert by creating dangerous binding
kubectl create clusterrolebinding dangerous-test --clusterrole=cluster-admin --serviceaccount=default:default

# Should trigger: ClusterAdminBindingCreated alert

# Clean up
kubectl delete clusterrolebinding dangerous-test
```

---

## Storage & Rotation

**Current Configuration**:
- Max size: 100MB per file
- Max backups: 10 files
- Max age: 30 days
- Location: `/var/log/kubernetes/` on control plane nodes

**Estimated Storage**: ~1GB per month per control plane node

**Archive to S3/Long-term Storage**:
```bash
# Install kube-bench or use log shipping
kubectl create secret generic s3-credentials --from-file=aws-key=/path/to/key

# Deploy fluent-bit with S3 output
kubectl apply -f kubernetes-manifests/monitoring/fluent-bit-rbac-audit.yaml
```

---

## Incident Response

### If Malicious RBAC Change Detected

1. **Immediate Actions**:
   ```bash
   # Identify the binding
   kubectl get clusterrolebindings -o wide

   # Delete malicious binding
   kubectl delete clusterrolebinding <suspicious-binding>

   # Check user permissions
   kubectl auth can-i list clusterrolebindings --all-namespaces --as=<suspicious-user>
   ```

2. **Investigation**:
   ```bash
   # Check audit logs for context
   jq 'select(.user.username="<suspicious-user>")' /var/log/kubernetes/audit.log

   # Review all changes by that user
   jq 'select(.user.username="<suspicious-user>") |
     {timestamp: .stageTimestamp, verb: .verb, resource: .objectRef.resource, name: .objectRef.name}' \
     /var/log/kubernetes/audit.log
   ```

3. **Prevention**:
   ```yaml
   # Add OPA Gatekeeper policy
   apiVersion: templates.gatekeeper.sh/v1
   kind: ClusterRoleBindingTemplate
   metadata:
     name: no-anonymous-cluster-admin
   spec:
     rules:
     - message: "Cluster-admin access cannot be given to anonymous users"
       match:
         kind: ClusterRoleBinding
       pattern:
         roleRef:
           name: cluster-admin
         subjects:
         - name: system:anonymous
   ```

---

## Compliance Checklists

### CIS Benchmark Coverage

- ✅ **1.1.17**: Ensure that the audit log path is set
- ✅ **1.1.18**: Ensure that the audit log max age is set
- ✅ **1.1.19**: Ensure that the audit log max backup is set
- ✅ **1.1.20**: Ensure that the audit log max size is set
- ✅ **1.1.21**: Ensure that the audit policy is set

### SOC 2 Requirements

- ✅ **Monitoring**: All RBAC changes logged
- ✅ **Alerting**: Dangerous changes trigger alerts
- ✅ **Retention**: 30-day audit log retention
- ✅ **Review**: Weekly RBAC change reports

---

## Next Steps

1. ✅ Create audit policy manifest
2. ⏳ Enable audit logging on API servers (requires NixOS config change)
3. ⏳ Deploy Prometheus alert rules
4. ⏳ Configure log aggregation to central storage
5. ⏳ Set up weekly RBAC change reports
6. ⏳ Test incident response procedures

---

**Owner**: Security Team
**Review Date**: 2026-04-22
**Related**: Security Audit 2026-03-21 (Task #26)
