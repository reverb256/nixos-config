---
name: helm-chart-patterns
description: Helm chart development patterns for packaging and deploying Kubernetes applications. Use when creating reusable Helm charts, managing multi-environment deployments, or building application catalogs for Kubernetes.
---

# Helm Chart Patterns

Expert guidance for developing production-grade Helm charts covering chart structure, templating patterns, multi-environment configuration, dependency management, testing strategies, and distribution workflows for Kubernetes application packaging.

## When to Use This Skill

- Creating reusable Helm charts for applications and services
- Building application catalogs and chart repositories
- Managing multi-environment deployments (dev, staging, production)
- Implementing advanced templating with conditionals and loops
- Managing chart dependencies and subcharts
- Implementing chart hooks for lifecycle management
- Testing and validating chart templates
- Packaging and distributing charts via repositories
- Using Helmfile for multi-chart orchestration

## Core Concepts

### Chart Types
- **Application charts**: Standard deployable charts for your services
- **Library charts**: Reusable template helpers (not directly installable)

### Key Files
| File | Purpose |
|------|---------|
| `Chart.yaml` | Metadata, version, dependencies |
| `values.yaml` | Default configuration |
| `values.schema.json` | Input validation |
| `templates/_helpers.tpl` | Reusable template functions |
| `templates/*.yaml` | Kubernetes manifests |

### Template Essentials
- **Quote strings**: `{{ .Values.name | quote }}`
- **Indent properly**: `{{- toYaml . | nindent 4 }}`
- **Use helpers**: `{{ include "my-app.fullname" . }}`
- **Check nil**: `{{- if .Values.optional }}`

## Quick Reference

| Task | Load reference |
| --- | --- |
| Chart structure & Chart.yaml | `skills/helm-chart-patterns/references/chart-structure.md` |
| Values file patterns | `skills/helm-chart-patterns/references/values-patterns.md` |
| Template patterns & functions | `skills/helm-chart-patterns/references/template-patterns.md` |
| Dependencies & subcharts | `skills/helm-chart-patterns/references/dependencies.md` |
| Hooks & lifecycle | `skills/helm-chart-patterns/references/hooks.md` |
| Testing patterns | `skills/helm-chart-patterns/references/testing.md` |
| Packaging & distribution | `skills/helm-chart-patterns/references/packaging.md` |
| Helmfile multi-chart | `skills/helm-chart-patterns/references/helmfile.md` |
| Best practices checklist | `skills/helm-chart-patterns/references/best-practices.md` |

## Workflow

1. **Structure** - Set up chart directory with Chart.yaml and values.yaml
2. **Template** - Create Kubernetes manifests with Go templating
3. **Helpers** - Extract common patterns into _helpers.tpl
4. **Validate** - Use values.schema.json for input validation
5. **Test** - Lint, template, and run chart tests
6. **Package** - Create .tgz and publish to repository

## Essential Commands

```bash
# Development
helm create my-app          # Scaffold new chart
helm lint ./my-app          # Validate chart
helm template my-app ./my-app  # Render templates

# Dependencies
helm dependency update      # Download dependencies
helm dependency list        # Show dependencies

# Testing
helm install my-app ./my-app --dry-run --debug
helm test my-app

# Distribution
helm package ./my-app
helm repo index . --url https://charts.example.com
helm push my-app-1.0.0.tgz oci://registry.example.com/charts
```

## Common Mistakes

- Forgetting to quote strings in templates
- Not using `nindent` for proper YAML formatting
- Committing secrets to values files
- Missing security contexts (runAsNonRoot, drop capabilities)
- Not pinning dependency versions
- Skipping values.schema.json validation
- Not testing upgrades from previous versions

## Resources

- **Helm Documentation**: https://helm.sh/docs/
- **Chart Template Guide**: https://helm.sh/docs/chart_template_guide/
- **Best Practices**: https://helm.sh/docs/chart_best_practices/
- **Helmfile**: https://github.com/helmfile/helmfile
- **Chart Testing**: https://github.com/helm/chart-testing

---

## Helm Chart Scaffolding

Complete guide for scaffolding, organizing, and managing Helm chart structures for production deployments.

### Basic Chart Scaffold

```bash
# Create new chart from scratch
helm create my-app

# Directory structure
my-app/
├── Chart.yaml
├── values.yaml
├── values.schema.json
├── .helmignore
├── charts/
├── templates/
│   ├── NOTES.txt
│   ├── _helpers.tpl
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── serviceaccount.yaml
│   └── hpa.yaml
└── tests/
    ├── test-connection.yaml
    └── test-connection.bats
```

### Chart.yaml Structure

```yaml
apiVersion: v2
name: my-app
description: A Helm chart for deploying my-app
type: application

# Chart version (semantic versioning)
version: 1.2.3

# Application version
appVersion: "2.0.1"

# Kubernetes API version
kubeVersion: ">=1.22.0-0"

# Icon
icon: https://example.com/icon.png

# Keywords for search
keywords:
  - my-app
  - application
  - web

# Maintainers
maintainers:
  - name: John Doe
    email: john@example.com
    url: https://example.com

# Home page
home: https://example.com/my-app

# Sources
sources:
  - https://github.com/example/my-app

# Annotations
annotations:
  example.com/category: web

# Dependencies
dependencies:
  - name: postgresql
    version: 12.x.x
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled
  - name: redis
    version: 17.x.x
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
```

### Values File Scaffolding

```yaml
# values.yaml - default configuration

# Global values (shared across subcharts)
global:
  # Image registry
  imageRegistry: docker.io
  imagePullSecrets: []
  
  # Common labels
  commonLabels: {}
  commonAnnotations: {}

# Image configuration
image:
  repository: myregistry/my-app
  tag: 1.2.3
  pullPolicy: IfNotPresent
  pullSecrets: []
  
# Application configuration
replicaCount: 3

# Application settings
app:
  name: my-app
  environment: production
  logLevel: info
  debug: false
  
  # Configuration
  config:
    database:
      host: ""
      port: 5432
      name: myapp
      user: myapp
      sslMode: require
    cache:
      host: ""
      port: 6379
      db: 0
    api:
      timeout: 30
      maxConcurrent: 100

# Service configuration
service:
  type: ClusterIP
  port: 8080
  targetPort: http
  annotations: {}
  
  # Additional ports
  additionalPorts: []
  
  # Session affinity
  sessionAffinity: None
  sessionAffinityConfig: {}

# Ingress configuration
ingress:
  enabled: false
  className: nginx
  annotations: {}
  
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
          service: my-app
  
  tls: []
  
  # Default ingress for TLS
  defaultTls: []

# Resource limits
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

# Autoscaling
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
  customMetrics: []

# Node selector
nodeSelector: {}

# Tolerations
tolerations: []

# Affinity
affinity: {}

# Pod security context
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

# Container security context
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
      - ALL

# Liveness probe
livenessProbe:
  enabled: true
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 3

# Readiness probe
readinessProbe:
  enabled: true
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 3

# Startup probe
startupProbe:
  enabled: false
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 0
  periodSeconds: 10
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 30

# Lifecycle hooks
lifecycle: {}

# Service account
serviceAccount:
  create: true
  annotations: {}
  name: ""
  automountServiceAccountToken: false

# Pod annotations
podAnnotations: {}

# Pod labels
podLabels: {}

# Init containers
initContainers: []

# Sidecars
sidecars: []

# ConfigMaps
configMaps: []

# Secrets
secrets:
  create: true
  existingSecret: ""
  nameOverride: ""

# Persistent volumes
persistence:
  enabled: false
  storageClass: ""
  accessMode: ReadWriteOnce
  size: 10Gi
  annotations: {}

# Service monitor (for Prometheus)
serviceMonitor:
  enabled: false
  namespace: monitoring
  interval: 30s
  scrapeTimeout: 10s
  labels: {}
  annotations: {}
  relabelings: []

# Pod disruption budget
podDisruptionBudget:
  enabled: false
  minAvailable: 1
  maxUnavailable: ""

# Tolerations
tolerations: []

# Node affinity
nodeAffinity: {}

# Pod affinity
podAffinity: {}

# Pod anti-affinity
podAntiAffinity: {}
```

### Template Helpers Scaffolding

```yaml
# templates/_helpers.tpl

{{/*
Expand the name of the chart.
*/}}
{{- define "my-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "my-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "my-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create default labels.
*/}}
{{- define "my-app.labels" -}}
helm.sh/chart: {{ include "my-app.chart" . }}
{{ include "my-app.selectorLabels" . }}
{{- if .Chart.AppVersion -}}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "my-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account
*/}}
{{- define "my-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "my-app.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Image pull secrets
*/}}
{{- define "my-app.imagePullSecrets" -}}
{{- range .Values.global.imagePullSecrets -}}
- name: {{ . }}
{{- end -}}
{{- range .Values.image.pullSecrets -}}
- name: {{ . }}
{{- end -}}
{{- end -}}
```

### Deployment Template Scaffolding

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
  {{- with .Values.deploymentAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
      {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
        {{- with .Values.podAnnotations }}
          {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "my-app.serviceAccountName" . }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .Values.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
          {{- if .Values.livenessProbe.enabled }}
          livenessProbe:
            {{- toYaml .Values.livenessProbe | nindent 12 }}
          {{- end }}
          {{- if .Values.readinessProbe.enabled }}
          readinessProbe:
            {{- toYaml .Values.readinessProbe | nindent 12 }}
          {{- end }}
          {{- if .Values.startupProbe.enabled }}
          startupProbe:
            {{- toYaml .Values.startupProbe | nindent 12 }}
          {{- end }}
          env:
            - name: APP_ENV
              value: {{ .Values.app.environment | quote }}
            - name: APP_LOG_LEVEL
              value: {{ .Values.app.logLevel | quote }}
            {{- if .Values.app.debug }}
            - name: DEBUG
              value: "true"
            {{- end }}
            {{- range .Values.app.config }}
            - name: {{ upper .key | replace "." "_" | quote }}
              valueFrom:
                configMapKeyRef:
                  name: {{ include "my-app.fullname" . }}-config
                  key: {{ .key }}
            {{- end }}
          {{- with .Values.env }}
            {{- toYaml . | nindent 12 }}
          {{- end }}
          envFrom:
            - configMapRef:
                name: {{ include "my-app.fullname" . }}-config
          {{- if .Values.secrets.create }}
            - secretRef:
                name: {{ include "my-app.fullname" . }}-secrets
          {{- end }}
          volumeMounts:
            - name: config-volume
              mountPath: /etc/app/config
              readOnly: true
            {{- if .Values.persistence.enabled }}
            - name: data
              mountPath: /data
            {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      volumes:
        - name: config-volume
          configMap:
            name: {{ include "my-app.fullname" . }}-config
        {{- if .Values.persistence.enabled }}
        - name: data
          persistentVolumeClaim:
            claimName: {{ include "my-app.fullname" . }}-data
        {{- end }}
      {{- with .Values.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
```

### Multi-Environment Values

```bash
# Directory structure
my-app/
├── Chart.yaml
├── values.yaml              # Default values
├── values-dev.yaml          # Development overrides
├── values-staging.yaml      # Staging overrides
└── values-prod.yaml       # Production overrides

# Install for different environments
helm install my-app ./my-app -f values-dev.yaml
helm install my-app ./my-app -f values-staging.yaml
helm install my-app ./my-app -f values-prod.yaml

# Or use --set for overrides
helm install my-app ./my-app --set image.tag=dev --set replicaCount=1
```

### Values Schema Validation

```json
// values.schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "my-app Helm Chart",
  "type": "object",
  "required": [],
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1,
      "default": 3
    },
    "image": {
      "type": "object",
      "required": ["repository"],
      "properties": {
        "repository": {
          "type": "string"
        },
        "tag": {
          "type": "string",
          "pattern": "^[a-zA-Z0-9.\\-_]+$"
        },
        "pullPolicy": {
          "type": "string",
          "enum": ["Always", "IfNotPresent", "Never"]
        }
      }
    },
    "resources": {
      "type": "object",
      "properties": {
        "limits": {
          "type": "object",
          "properties": {
            "cpu": {
              "type": "string",
              "pattern": "^[0-9.]+m?$"
            },
            "memory": {
              "type": "string",
              "pattern": "^[0-9.]+(Ki|Mi|Gi|Ti|Pi|Ei)?$"
            }
          }
        }
      }
    }
  }
}
```

### .helmignore

```
# Patterns to ignore when packaging
.git
.gitignore
.github
*.md
LICENSE
README.md
charts/  # Don't include dependency charts
# CI/CD
.gitlab-ci.yml
.github/
# Documentation
docs/
# Test files
tests/
*.tgz
# IDE
.vscode/
.idea/
*.iml
# OS
.DS_Store
Thumbs.db
```

---

## Related Skills

- `helm-chart-scaffolding` - (DEPRECATED - merged into this skill)
- `helm-debugging` - Troubleshooting Helm chart issues
- `helm-values-management` - Managing values across environments
- `kubernetes` - Comprehensive Kubernetes expertise
- `k8s-security` - Kubernetes security policies
