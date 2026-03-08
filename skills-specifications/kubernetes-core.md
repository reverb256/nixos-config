# Kubernetes Skill Consolidation Specification

**Target Name**: `kubernetes:core`
**Sources to Merge**:
- `kubernetes-architect`
- `k8s-manifest-generator`
- `k8s-security-policies`
- `k8s-helm`

**Created**: 2026-03-07
**Status**: Specification ready for implementation

---

## Skill Manifest

```yaml
name: kubernetes:core
description: Complete Kubernetes expertise including architecture, manifest generation, security policies, and Helm chart development.

triggers:
  - User asks about Kubernetes
  - User needs K8s manifests
  - User wants Helm charts
  - "Deploy to Kubernetes..."
  - "K8s security..."
  - "Helm chart for..."
```

---

## Consolidated Content Structure

### 1. Kubernetes Architecture

#### 1.1 Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                        Control Plane                         │
├─────────────────────────────────────────────────────────────┤
│  API Server  │  Scheduler  │  Controller Manager  │  etcd   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Worker Nodes                         │
├─────────────────────────────────────────────────────────────┤
│  Node 1              Node 2              Node 3             │
│  ┌─────────┐        ┌─────────┐         ┌─────────┐        │
│  │ Kubelet │        │ Kubelet │         │ Kubelet │        │
│  │Proxy    │        │Proxy    │         │Proxy    │        │
│  │Pod      │        │Pod      │         │Pod      │        │
│  │Container│        │Container│         │Container│        │
│  └─────────┘        └─────────┘         └─────────┘        │
└─────────────────────────────────────────────────────────────┘
```

#### 1.2 Architecture Patterns

**Microservices Pattern**:
```yaml
# Each microservice = Deployment + Service + ConfigMap + Secret
apiVersion: v1
kind: Namespace
metadata:
  name: microservices-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: microservices-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: myapp/api:1.0
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: microservices-app
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 8080
```

**Sidecar Pattern**:
```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
  - name: log-collector
    image: fluentd:1.0
    volumeMounts:
    - name: varlog
      mountPath: /var/log
  volumes:
  - name: varlog
    hostPath:
      path: /var/log
```

**Ambassador Pattern**:
```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
  - name: ambassador
    image: envoy:1.0
    ports:
    - containerPort: 9901
```

### 2. Manifest Generation

#### 2.1 Complete Deployment Manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: production
  labels:
    app: webapp
    version: v1
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
        version: v1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      serviceAccountName: webapp
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: webapp
        image: registry.example.com/webapp:1.0.0
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        - name: metrics
          containerPort: 9090
          protocol: TCP
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: webapp-secrets
              key: database-url
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: webapp-config
              key: log-level
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
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
        volumeMounts:
        - name: config
          mountPath: /etc/webapp
          readOnly: true
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: config
        configMap:
          name: webapp-config
      - name: tmp
        emptyDir: {}
      nodeSelector:
        disktype: ssd
      tolerations:
      - key: "workload"
        operator: "Equal"
        value: "web"
        effect: "NoSchedule"
---
apiVersion: v1
kind: Service
metadata:
  name: webapp
  namespace: production
  labels:
    app: webapp
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  type: LoadBalancer
  selector:
    app: webapp
  ports:
  - name: http
    port: 80
    targetPort: http
    protocol: TCP
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-config
  namespace: production
data:
  log-level: "info"
  config.yaml: |
    server:
      port: 8080
      timeout: 30s
    features:
      cache: true
      compression: true
---
apiVersion: v1
kind: Secret
metadata:
  name: webapp-secrets
  namespace: production
type: Opaque
stringData:
  database-url: "postgresql://user:pass@db:5432/mydb"
  api-key: "secret-key-here"
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: webapp
  namespace: production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: webapp
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: webapp
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  minReplicas: 3
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
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp
  namespace: production
automountServiceAccountToken: false
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp
  namespace: production
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rate-limit: "100"
spec:
  tls:
  - hosts:
    - webapp.example.com
    secretName: webapp-tls
  rules:
  - host: webapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: webapp
            port:
              number: 80
```

#### 2.2 Namespace & Resource Quota

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-a
  labels:
    name: tenant-a
    env: production
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: tenant-a
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    persistentvolumeclaims: "5"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: tenant-a
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
```

### 3. Security Policies

#### 3.1 Pod Security Standards (Pod Security Admission)

```yaml
# Namespace with restricted policy
apiVersion: v1
kind: Namespace
metadata:
  name: secure-app
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Policy Levels**:
- **privileged**: Unrestricted, widest allowable range
- **baseline**: Minimally restrictive, prevents known privilege escalations
- **restricted**: Heavily restricted, follows current security best practices

#### 3.2 Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: webapp-network-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: webapp
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: database
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

#### 3.3 Security Context

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
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
    image: secure-app:1.0
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      readOnlyRootFilesystem: true
```

#### 3.4 RBAC

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp-sa
  namespace: production
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: webapp-role
  namespace: production
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: webapp-rolebinding
  namespace: production
subjects:
- kind: ServiceAccount
  name: webapp-sa
  namespace: production
roleRef:
  kind: Role
  name: webapp-role
  apiGroup: rbac.authorization.k8s.io
```

#### 3.5 Secrets Management

```yaml
# Opaque secret (base64 encoded)
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
stringData:
  password: "supersecret"

# TLS secret
apiVersion: v1
kind: Secret
metadata:
  name: tls-cert
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi...
  tls.key: LS0tLS1CRUdJTi...

# Docker registry secret
apiVersion: v1
kind: Secret
metadata:
  name: registry-secret
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: eyJhdXRocyI6eyJyZWdpc3RyeS5leGFtcGxlLmNvbSI6eyJ1c2VybmFtZSI6InVzZXIiLCJwYXNzd29yZCI6InBhc3MifX19

# External Secrets Operator (recommended)
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: prod/db/password
```

### 4. Helm Charts

#### 4.1 Chart Structure

```
mychart/
├── Chart.yaml
├── values.yaml
├── values-dev.yaml
├── values-prod.yaml
├── charts/                    # Dependencies
├── templates/
│   ├── NOTES.txt             # Usage hints
│   ├── _helpers.tpl          # Template helpers
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── hpa.yaml
│   ├── serviceaccount.yaml
│   └── tests/
│       └── test-connection.yaml
└── .helmignore               # Like .dockerignore
```

#### 4.2 Chart.yaml

```yaml
apiVersion: v2
name: mychart
description: A Helm chart for my application
type: application
version: 1.0.0
appVersion: "1.0.0"
keywords:
  - webapp
  - api
maintainers:
  - name: My Team
    email: team@example.com
dependencies:
  - name: postgresql
    version: 12.x.x
    repository: https://charts.bitnami.com/bitnami
    alias: db
    condition: db.enabled
```

#### 4.3 Values.yaml

```yaml
# Default values for mychart
replicaCount: 3

image:
  repository: registry.example.com/myapp
  pullPolicy: IfNotPresent
  tag: ""

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true

service:
  type: ClusterIP
  port: 80
  annotations: {}

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
  - host: chart-example.local
    paths:
    - path: /
      pathType: Prefix
  tls:
  - secretName: chart-example-tls
    hosts:
    - chart-example.local

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

nodeSelector: {}

tolerations: []

affinity: {}

# Feature flags
features:
  cache:
    enabled: true
    ttl: 3600
  compression:
    enabled: true

# Dependencies
db:
  enabled: true
  postgresql:
    auth:
      postgresPassword: changeme
      database: mydb
    primary:
      persistence:
        enabled: true
```

#### 4.4 Template Helpers

```yaml
# templates/_helpers.tpl
{{/*
Expand the name of the chart.
*/}}
{{- define "mychart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "mychart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mychart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mychart.labels" -}}
helm.sh/chart: {{ include "mychart.chart" . }}
{{ include "mychart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

#### 4.5 Using Templates

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "mychart.fullname" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
      - name: {{ .Chart.Name }}
        securityContext:
          {{- toYaml .Values.securityContext | nindent 10 }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
```

#### 4.6 Helm Commands

```bash
# Create new chart
helm create mychart

# Lint chart
helm lint mychart

# Template rendering (dry-run)
helm template myapp mychart

# Install/upgrade
helm install myapp mychart
helm install myapp mychart -f values-prod.yaml
helm upgrade myapp mychart

# Install from directory
helm install myapp ./mychart

# Install from repository
helm repo add myrepo https://charts.example.com
helm install myapp myrepo/mychart

# Uninstall
helm uninstall myapp

# List releases
helm list
helm list --all-namespaces

# Get values
helm get values myapp

# Get manifest
helm get manifest myapp

# Rollback
helm rollback myapp
helm rollback myapp 2  # Rollback to revision 2

# History
helm history myapp
```

---

## When to Use This Skill

Trigger this skill when:

1. **Architecture Decisions**
   - "How should I structure my K8s app?"
   - "Multi-cluster or single cluster?"
   - "Namespace strategy?"

2. **Manifest Generation**
   - "Create K8s manifests for..."
   - "Deployment with HPA..."
   - "Ingress with TLS..."

3. **Security Setup**
   - "Secure my K8s deployment"
   - "Network policies for..."
   - "RBAC for my app..."

4. **Helm Chart Development**
   - "Create Helm chart for..."
   - "Add dependency to chart..."
   - "Template complex values..."

---

## Quality Checklist

Before applying K8s manifests:

- [ ] All resources have labels (app, version)
- [ ] Resource limits/requests defined
- [ ] Health checks configured (liveness, readiness)
- [ ] Security context set (runAsNonRoot)
- [ ] RBAC least-privilege applied
- [ ] Network policies defined
- [ ] Ingress TLS configured
- [ ] HPA for critical services
- [ ] PDB for high-availability
- [ ] Probes have appropriate thresholds

---

## Integration Notes

When implementing this consolidated skill:

1. **Merge architecture insights** from kubernetes-architect
2. **Include all manifest examples** from k8s-manifest-generator
3. **Preserve all security patterns** from k8s-security-policies
4. **Keep complete Helm guide** from k8s-helm
5. **Cross-reference**: security applies to all manifest types

---

## References

- K8s Documentation: https://kubernetes.io/docs/
- Helm Docs: https://helm.sh/docs/
- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Network Policies: https://kubernetes.io/docs/concepts/services-networking/network-policies/
