---
name: k8s-security
description: Use when securing Kubernetes clusters, implementing network policies, configuring RBAC, pod security standards, or asking about "Kubernetes security", "NetworkPolicy", "PodSecurityPolicy", "RBAC", "pod security standards", "OPA Gatekeeper". Covers defense-in-depth security including Pod Security Standards, NetworkPolicy, RBAC, admission control, service mesh security, and compliance frameworks.
version: 2.0.0
---

# Kubernetes Security Policies

Comprehensive guide for implementing NetworkPolicy, PodSecurityPolicy, RBAC, Pod Security Standards, and admission control in Kubernetes for production-grade security.

## Purpose

Implement defense-in-depth security for Kubernetes clusters using network policies, pod security standards, RBAC, admission control, and service mesh security.

## When to Use This Skill

- Implement network segmentation and isolation
- Configure pod security standards at namespace level
- Set up RBAC for least-privilege access
- Create security policies for compliance (CIS, NIST)
- Implement admission control (OPA Gatekeeper, Kyverno)
- Secure multi-tenant clusters
- Enable service mesh security (mTLS, authorization)
- Implement pod security contexts
- Set up audit logging
- Enforce resource quotas and limit ranges

## Pod Security Standards

Kubernetes Pod Security Standards (PSS) replace deprecated PodSecurityPolicy. Apply at namespace level.

### 1. Privileged (Unrestricted)

For workloads requiring elevated privileges (use sparingly):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: privileged-ns
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

### 2. Baseline (Minimally restrictive)

For most applications:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: baseline-ns
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: baseline
```

### 3. Restricted (Most Secure)

For production workloads requiring maximum security:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: restricted-ns
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Secure Pod Configuration

Always configure security context at pod and container level:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: restricted-ns
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:1.0
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

## Network Policies

Implement network segmentation with NetworkPolicy (requires CNI that supports it).

### Default Deny All

Start with default deny for every namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Allow Frontend to Backend

Tiered communication:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### Allow DNS Egress

Required for most workloads:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: production
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

### Allow External Egress

For external API calls:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16
    ports:
    - protocol: TCP
      port: 443
```

## RBAC Configuration

Implement least-privilege access with RBAC.

### Role (Namespace-scoped)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
```

### ClusterRole (Cluster-wide)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "watch", "list"]
```

### RoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: production
subjects:
- kind: User
  name: jane
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount
  name: my-app
  namespace: production
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### ClusterRoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: secret-reader-global
subjects:
- kind: ServiceAccount
  name: my-app
  namespace: production
roleRef:
  kind: ClusterRole
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

## Admission Control

### OPA Gatekeeper Policies

#### ConstraintTemplate (Reusable policy logic)

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg, "details": {"missing_labels": missing}}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("missing required labels: %v", [missing])
        }
```

#### Constraint (Policy instance)

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-app-label
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
  parameters:
    labels: ["app", "environment"]
```

### Kyverno Policies

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  background: true
  rules:
    - name: require-app-label
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "label 'app' is required"
        pattern:
          metadata:
            labels:
              app: "?*"
```

## Service Mesh Security (Istio)

### Strict mTLS

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
```

### AuthorizationPolicy

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-frontend
  namespace: production
spec:
  selector:
    matchLabels:
      app: backend
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/production/sa/frontend"]
```

## Resource Quotas and Limit Ranges

### ResourceQuota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-resources
  namespace: production
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    persistentvolumeclaims: "4"
```

### LimitRange

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "256Mi"
    type: Container
```

## Compliance Frameworks

### CIS Kubernetes Benchmark Controls

Implement these critical controls:

1. **RBAC Authorization** - Use RBAC for all access
2. **Audit Logging** - Enable audit log backend
3. **Pod Security Standards** - Enforce at namespace level
4. **Network Policies** - Configure for all namespaces
5. **Secrets Encryption** - Enable at-rest encryption
6. **Node Authentication** - Use TLS for API server communication
7. **Image Scanning** - Scan images for vulnerabilities
8. **Runtime Security** - Use seccomp, AppArmor, SELinux

### NIST Cybersecurity Framework

- **Identify**: Asset inventory, risk assessment
- **Protect**: Network segmentation, access controls, encryption
- **Detect**: Monitoring, logging, anomaly detection
- **Respond**: Incident response procedures
- **Recover**: Backup and restoration, disaster recovery

## Best Practices

1. **Implement Pod Security Standards** at namespace level
2. **Use Network Policies** for network segmentation
3. **Apply least-privilege RBAC** for all service accounts
4. **Enable admission control** (OPA Gatekeeper/Kyverno)
5. **Run containers as non-root** with dedicated user IDs
6. **Use read-only root filesystem** with tmpfs for writable paths
7. **Drop all capabilities** unless specifically needed
8. **Implement resource quotas** and limit ranges
9. **Enable audit logging** for security events
10. **Regular security scanning** of images and clusters
11. **Encrypt secrets** at rest using KMS
12. **Rotate secrets** and certificates regularly
13. **Implement network policies** as default deny
14. **Use service mesh** for east-west traffic security
15. **Enable pod security contexts** for all workloads

## Troubleshooting

### NetworkPolicy Issues

```bash
# Check if CNI supports NetworkPolicy
kubectl get nodes -o wide

# Describe a network policy
kubectl describe networkpolicy <name>

# List all network policies
kubectl get networkpolicy -A

# Test connectivity from a pod
kubectl exec -it <pod> -- nslookup <service>
```

### RBAC Permission Issues

```bash
# Check effective permissions for a service account
kubectl auth can-i list pods --as system:serviceaccount:default:my-sa

# Check all permissions
kubectl auth can-i '*' '*' --as system:serviceaccount:default:my-sa

# List roles and rolebindings
kubectl get roles,rolebindings -n <namespace>

# Describe role/rolebinding
kubectl describe role <name> -n <namespace>
kubectl describe rolebinding <name> -n <namespace>
```

### Pod Security Admission Issues

```bash
# Check PSS labels on namespace
kubectl get namespace <name> -o yaml | grep pod-security

# Check pod audit warnings
kubectl describe pod <pod-name> | grep -A5 "Warning:"

# View audit logs
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Admission Controller Issues

```bash
# Check Gatekeeper constraints
kubectl get constraints -A

# Describe a constraint
kubectl describe constraint <name>

# Check constraint template
kubectl get constrainttemplates

# View denied admission requests
kubectl get events --field-selector reason=FailedAdmission
```

## Security Checklist

Use this checklist when deploying workloads to Kubernetes:

- [ ] Namespace has Pod Security Standards enforced
- [ ] Network policies configured (default deny)
- [ ] RBAC configured with least privilege
- [ ] Service accounts configured with minimal permissions
- [ ] Pods run as non-root
- [ ] Containers have security context configured
- [ ] Filesystem is read-only where possible
- [ ] Unnecessary capabilities dropped
- [ ] Resource limits and requests set
- [ ] Secrets encrypted at rest
- [ ] Secrets not stored in ConfigMaps or plain text
- [ ] Images scanned for vulnerabilities
- [ ] seccomp/AppArmor profiles applied
- [ ] Admission control policies in place
- [ ] Audit logging enabled
- [ ] Network segmentation implemented
- [ ] mTLS enabled (if using service mesh)
- [ ] Regular security scans scheduled

## Related Skills

- `kubernetes` - Comprehensive Kubernetes expertise
- `kubernetes-specialist` - Deploying and managing K8s workloads
- `kubernetes-architect` - Designing K8s platforms and architecture
- `gpu-kubernetes-operations` - GPU-backed Kubernetes clusters for AI
- `security-best-practices` - Web application and infrastructure security (includes OWASP audit guidelines)
