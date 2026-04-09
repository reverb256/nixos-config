---
name: kubernetes
description: >
  Comprehensive Kubernetes expertise covering cluster architecture, GitOps workflows, manifest generation,
  Helm charts, security policies, and production deployment. Use for designing K8s platforms, creating
  manifests, configuring Helm charts, implementing security, or managing multi-cluster deployments.
risk: low
version: 1.0.0
---

# Kubernetes

Expert guidance for Kubernetes cluster architecture, GitOps workflows, manifest generation, Helm charts, and security policies.

## When to Use

- **Cluster Architecture**: Design multi-cluster platforms, service mesh, networking
- **Manifest Generation**: Create Deployments, Services, ConfigMaps, Secrets, PVCs
- **Helm Charts**: Package applications, manage releases, create templates
- **GitOps**: ArgoCD/Flux workflows, progressive delivery, IaC
- **Security**: Pod Security Standards, NetworkPolicy, RBAC, policies
- **Operations**: Autoscaling, monitoring, troubleshooting, cost optimization

## Cluster Architecture

### Managed Kubernetes Options

| Provider | Service | Features |
|----------|---------|----------|
| AWS | EKS | Fargate, EKS Anywhere, IRSA |
| Azure | AKS | AAD integration, AKS Edge |
| Google | GKE | Autopilot, Anthos, GKE On-Prem |
| Red Hat | OpenShift | OpenShift Operators, OpenShift GitOps |
| Rancher | RKE | Multi-cluster management, Rancher GitOps |

### Multi-Cluster Patterns

**Hub-Spoke Model**:
```
                Hub Cluster
                     |
        +------------+------------+
        |            |            |
    Cluster A    Cluster B    Cluster C
    (Production) (Staging)   (Dev)
```

**Multi-Region Active-Active**:
```
Region A          Region B
---------         ---------
Cluster A1 ←→ Cluster B1
(Primary)     (Secondary)
     |             |
  Global Load Balancer
```

### GitOps Principles (OpenGitOps)

1. **Declarative** - Entire system described declaratively
2. **Versioned** - Desired state stored in Git
3. **Pulled Automatically** - Agents pull from Git
4. **Continuously Reconciled** - Agents observe and reconcile

## Manifest Generation

### Deployment Template

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app-name>
  namespace: <namespace>
  labels:
    app.kubernetes.io/name: <app-name>
    app.kubernetes.io/component: backend
    app.kubernetes.io/version: "1.0.0"
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: <app-name>
  template:
    metadata:
      labels:
        app.kubernetes.io/name: <app-name>
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: <image>:<tag>
          ports:
            - containerPort: 8080
              name: http
          resources:
            requests:
              memory: "256Mi"
              cpu: "250m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
          env:
            - name: ENV_VAR
              value: "value"
          envFrom:
            - configMapRef:
                name: <app-name>-config
            - secretRef:
                name: <app-name>-secret
```

### Service Types

**ClusterIP (internal)**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: <app-name>
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: <app-name>
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

**LoadBalancer (external)**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: <app-name>
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: <app-name>
  ports:
    - port: 80
      targetPort: 8080
```

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: <app-name>-config
data:
  APP_MODE: production
  LOG_LEVEL: info
  DATABASE_HOST: db.example.com
  # Config file
  app.properties: |
    server.port=8080
    logging.level=INFO
```

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <app-name>-secret
type: Opaque
stringData:
  DATABASE_PASSWORD: # inject via agenix
  API_KEY: # inject via agenix
```

**Never commit secrets to Git.** Use:
- Sealed Secrets
- External Secrets Operator
- HashiCorp Vault

### PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <app-name>-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi
```

## Helm Charts

### Chart Structure

```
helm/<chart-name>/
├── Chart.yaml
├── values.yaml
├── values-dev.yaml
├── values-prod.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── hpa.yaml
│   └── serviceaccount.yaml
└── charts/           # Dependencies
```

### Chart.yaml

```yaml
apiVersion: v2
name: my-app
description: My application
type: application
version: 1.0.0
appVersion: "1.0.0"

dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: postgresql.enabled
```

### values.yaml

```yaml
# Image
image:
  repository: registry.example.com/my-app
  tag: latest
  pullPolicy: IfNotPresent

# Replicas
replicaCount: 2

# Resources
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Service
service:
  type: ClusterIP
  port: 80
  targetPort: 8080

# Ingress
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: app.example.com
      paths:
        - path: /
          pathType: Prefix

# Autoscaling
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### Helper Templates

```yaml
# templates/_helpers.tpl
{{- define "my-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "my-app.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

### Helm Commands

```bash
# Install/Upgrade
helm upgrade --install my-app ./helm/my-app \
  -f ./helm/my-app/values-prod.yaml \
  --namespace my-app --create-namespace

# Dry run
helm upgrade --install my-app ./helm/my-app --dry-run --debug

# Template only
helm template my-app ./helm/my-app -f values-prod.yaml

# Lint
helm lint ./helm/my-app

# Rollback
helm rollback my-app 1 --namespace my-app

# History
helm history my-app --namespace my-app

# Uninstall
helm uninstall my-app --namespace my-app
```

## Security Policies

### Pod Security Standards

**Privileged (Unrestricted)**:
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

**Baseline (Minimally restrictive)**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: baseline-ns
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: baseline
```

**Restricted (Most restrictive)**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: restricted-ns
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
```

### Network Policies

**Default Deny All**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

**Allow Frontend to Backend**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
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

**Allow DNS**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
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

### RBAC

**Role (namespace-scoped)**:
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

**ClusterRole (cluster-wide)**:
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

**RoleBinding**:
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
    name: default
    namespace: production
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Security Context

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
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

## Service Mesh

### Istio

**PeerAuthentication (mTLS)**:
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

**AuthorizationPolicy**:
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

## Autoscaling

### HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

### VerticalPodAutoscaler

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: Auto
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      minAllowed:
        cpu: 100m
        memory: 256Mi
      maxAllowed:
        cpu: 1
        memory: 1Gi
```

## Progressive Delivery

### Argo Rollouts

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  replicas: 5
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 10m}
      - setWeight: 40
      - pause: {duration: 10m}
      - setWeight: 60
      - pause: {duration: 10m}
      - setWeight: 80
      - pause: {duration: 10m}
      canaryService: my-app-canary
      stableService: my-app-stable
  selector:
    matchLabels:
      app: my-app
  template:
    # ... pod template
```

## Observability

### Prometheus ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

### Pod Disruption Budget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-app
```

## kubectl Commands

```bash
# Get resources
kubectl get pods -n <namespace>
kubectl get deployments -n <namespace>
kubectl get services -n <namespace>
kubectl get all -n <namespace>

# Describe resources
kubectl describe pod <pod-name> -n <namespace>
kubectl describe deployment <deployment-name> -n <namespace>

# Logs
kubectl logs <pod-name> -n <namespace> --tail=100 -f
kubectl logs deployment/<deployment-name> -n <namespace> -f

# Exec
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Port forward
kubectl port-forward -n <namespace> svc/<service-name> 8080:80

# Apply
kubectl apply -f manifest.yaml -n <namespace>
kubectl apply -k overlays/prod

# Delete
kubectl delete -f manifest.yaml -n <namespace>

# Validate
kubectl apply -f manifest.yaml --dry-run=client
kubectl apply -f manifest.yaml --dry-run=server
```

## Best Practices

### Security
1. Run containers as non-root
2. Use read-only root filesystem
3. Drop all capabilities
4. Implement Pod Security Standards
5. Use Network Policies for segmentation
6. Apply least-privilege RBAC
7. Scan images for vulnerabilities
8. Never commit secrets to Git

### Reliability
1. Set resource requests and limits
2. Implement health checks (liveness/readiness)
3. Use multiple replicas
4. Configure Pod Disruption Budgets
5. Enable autoscaling
6. Use anti-affinity rules
7. Implement backup strategies

### Performance
1. Right-size resources
2. Use HPA/VPA for autoscaling
3. Configure appropriate storage classes
4. Use node selectors/affinity
5. Enable metrics collection
6. Monitor resource usage

## Common Patterns

### Pattern 1: Stateless Web Application
- Deployment (3 replicas)
- ClusterIP Service
- ConfigMap for config
- Secret for credentials
- HPA for autoscaling

### Pattern 2: Stateful Database
- StatefulSet (not Deployment)
- Headless Service
- PersistentVolumeClaim template
- ConfigMap for DB config

### Pattern 3: Background Job
- CronJob or Job
- ConfigMap for parameters
- Secret for credentials
- ServiceAccount with RBAC

### Pattern 4: Multi-Container Pod
- Deployment with multiple containers
- Shared volumes
- Init containers
- Service (if needed)

## Quick Reference

### Label Standards

```yaml
app.kubernetes.io/name: <app-name>
app.kubernetes.io/instance: <instance-name>
app.kubernetes.io/version: "1.0.0"
app.kubernetes.io/component: backend
app.kubernetes.io/part-of: <system-name>
app.kubernetes.io/managed-by: helm
```

### Resource Units

| Resource | Unit | Example |
|----------|------|---------|
| CPU | millicores | 100m, 500m, 1000m (1 CPU) |
| Memory | bytes | 256Mi, 1Gi, 512Mi |

### Storage Access Modes

| Mode | Description |
|------|-------------|
| ReadWriteOnce | Single pod read/write |
| ReadOnlyMany | Multiple pods read-only |
| ReadWriteMany | Multiple pods read/write |

## Related Skills

- `docker-best-practices` - Container best practices
- `gitops-workflow` - GitOps patterns
- `prometheus-configuration` - Metrics setup
