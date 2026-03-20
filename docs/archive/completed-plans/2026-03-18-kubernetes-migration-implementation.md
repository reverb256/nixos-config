# Kubernetes Migration Implementation Plan
**Status:** Ready for Phase 1 | **Created:** 2026-03-18 | **Owner:** j_kro | **Last Updated:** 2026-03-18

## Overview

This implementation plan provides detailed, step-by-step instructions for migrating all containerizable services from NixOS systemd to Kubernetes.

**Timeline:** 8 weeks total (7 weeks migration + 1 week automation)

**Approach:** Service-by-service migration with Velero protection, Helm chart packaging, and automated Caddy integration.

---

## Phase 1: Foundation (Week 1)

### Objectives

- Deploy Velero for backup/DR
- Create standard Helm chart template
- Deploy Grafana dashboards
- Configure Prometheus targets
- Test backup/restore procedures

### Day 1-2: Velero Installation

**Step 1: Create Velero namespace**
```bash
kubectl create namespace velero
kubectl create namespace velero-s3
```

**Step 2: Create Garage S3 credentials**
```bash
# Create S3 credentials for Velero
cat > /tmp/velero-credentials.txt <<EOF
[default]
aws_access_key_id = garagedge
aws_secret_access_key = $(cat /run/agenix/garage-s3-credentials)
EOF

# Create Kubernetes secret
kubectl create secret generic velero-s3-credentials \
  --namespace velero \
  --from-file=/tmp/velero-credentials.txt

# Cleanup
rm /tmp/velero-credentials.txt
```

**Step 3: Install Velero via Helm**
```bash
# Add Velero Helm repo
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts

# Create values file
cat > /tmp/velero-values.yaml <<EOF
configuration:
  provider: aws
  backupStorageLocation:
    name: garage-s3
    bucket: velero-backups
    url: http://10.1.1.120:3900
    insecure: true
  volumeSnapshotLocation:
    provider: generic
  defaultBackupTTL: 720h

initContainers:
  - name: velero-aws-plugin
    image: velero/velero-plugin-for-aws:v1.7.0
    volumeMounts:
    - mountPath: /credentials
      name: cloud-credentials
    env:
      AWS_SHARED_CREDENTIALS_FILE: /credentials/credentials
  volumes:
  - name: cloud-credentials
    emptyDir: {}

service:
  server:
    timeout: 300s

credentials:
  useSecret: true
  name: velero-s3-credentials
  extraSecretRef:
    namespace: velero
EOF

# Install Velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --values /tmp/velero-values.yaml \
  --version v1.14.0

# Cleanup
rm /tmp/velero-values.yaml
```

**Step 4: Verify Velero installation**
```bash
# Check Velero pod
kubectl get pods -n velero

# Check Velero backup location
velero backup-location get

# Test backup/restore
velero backup create test-backup --wait
velero backup get test-backup --details
velero delete backup test-backup
```

### Day 3-4: Standard Helm Chart Template

**Step 1: Create standard chart structure**
```bash
mkdir -p helm-charts/common/templates
mkdir -p helm-charts/common/charts
```

**Step 2: Create helper templates**
```bash
cat > helm-charts/common/templates/_helpers.tpl <<'EOF'
{{- define "service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "service.fullname" -}}
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

{{- end }}

{{- define "service.labels" -}}
helm.sh/chart: {{ include "service.chart" . }}
{{ include "service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}
EOF
```

**Step 3: Create Caddy ingress template**
```bash
cat > helm-charts/common/templates/caddy-ingress.yaml <<'EOF'
{{- if .Values.ingress.enabled -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "service.fullname" . }}
  namespace: {{ .Release.Namespace }}
  annotations:
    # Automatic Caddy integration
    caddy.frontend.k8s.io/enable: "true"
    caddy.frontend.k8s.io/scheme: "https"
    caddy.frontend.k8s.io/host: {{ .Values.ingress.host | quote }}
    caddy.frontend.k8s.io/tls: "internal"
    caddy.frontend.k8s.io/port: {{ .Values.service.port | quote }}

    # Security headers (automatic)
    caddy.frontend.k8s.io/security-headers: "true"
    caddy.frontend.k8s.io/hsts: "max-age=31536000"

    # Metrics (automatic)
    caddy.frontend.k8s.io/metrics: "/metrics"

    # Rate limiting (automatic)
    caddy.frontend.k8s.io/rate-limit: "100r/10s"
spec:
  type: ClusterIP
  ports:
  - port: {{ .Values.service.port }}
    targetPort: {{ .Values.service.targetPort }}
  selector:
    app: {{ include "service.name" . }}
{{- end }}
EOF
```

### Day 5-7: Monitoring Setup

**Step 1: Deploy Grafana**
```bash
# Add Grafana repo
helm repo add grafana https://grafana.github.io/helm-charts

# Create namespace
kubectl create namespace monitoring

# Install Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set persistence.enabled=true \
  --set persistence.storageClassName=fast-local-ssd \
  --set persistence.size=10Gi \
  --set adminPassword=admin
```

**Step 2: Configure Prometheus targets**
```bash
# Create ConfigMap for Prometheus scrape configs
cat > /tmp/prometheus-targets.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-targets
  namespace: monitoring
data:
  custom-rules.yaml: |
    - pattern: '[a-z]+-([a-z]+)\\.cluster\\.local:\\d+'
      name: cluster_service
      value: "$1"
EOF

kubectl apply -f /tmp/prometheus-targets.yaml
rm /tmp/prometheus-targets.yaml
```

**Step 3: Create standard dashboards**
```bash
# Create dashboard directory
mkdir -p monitoring/grafana-dashboards

# Create cluster overview dashboard
cat > monitoring/grafana-dashboards/cluster-overview.json <<'EOF'
{
  "dashboard": {
    "title": "Cluster Overview",
    "panels": [
      {
        "title": "Cluster Health",
        "targets": [
          {
            "expr": "up{job='kube-node'}"
          }
        ]
      }
    ]
  }
}
EOF
```

### Week 1 Validation

```bash
# Test Velero backup/restore
velero backup create week-1-test --wait
velero restore create --from-backup week-1-test \
  --namespace-mappings default:test-backup
kubectl get ns test-backup

# Verify Helm chart template works
helm create test-chart --namespace default
helm template test-chart ./helm-charts/common

# Verify monitoring
kubectl port-forward -n monitoring svc/grafana 3000 &
# Open http://localhost:3000 (admin/admin)

# Cleanup
kubectl delete ns test-backup
helm delete test-chart
```

---

## Phase 2: Quick Wins (Week 2)

### Service 1: Vaultwarden (Day 8-9)

**Pre-Migration:**
```bash
# Backup current installation
velero backup create pre-vaultwarden \
  --selector app=vaultwarden \
  --wait
```

**Migration Steps:**

**Step 1: Create Vaultwarden Helm chart**
```bash
# Create chart structure
mkdir -p helm-charts/vaultwarden/templates

# Create Chart.yaml
cat > helm-charts/vaultwarden/Chart.yaml <<'EOF'
apiVersion: v2
name: vaultwarden
description: Vaultwarden password manager
version: 1.0.0
appVersion: "latest"
EOF

# Create values.yaml
cat > helm-charts/vaultwarden/values.yaml <<'EOF'
replicaCount: 1

image:
  repository: vaultwarden/server
  tag: latest
  pullPolicy: Always

service:
  port: 80
  targetPort: 80
  type: ClusterIP

ingress:
  enabled: true
  host: vaultwarden.ts.net

persistence:
  enabled: true
  existingClaim: null
  storageClass: fast-local-ssd
  size: 10Gi
  accessMode: ReadWriteOnce

resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m

backup:
  enabled: true
  schedule: "0 3 * * *"
  retention: 720h
EOF

# Create deployment template
cat > helm-charts/vaultwarden/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "service.fullname" . }}
  labels:
    {{- include "service.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "service.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "service.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - name: http
          containerPort: 80
        env:
        - name: WEBSOCKET_ENABLED
          value: "true"
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: {{ include "service.fullname" . }}-data
EOF

# Add other templates (service, PVC, etc.) from common template
```

**Step 2: Create namespace and PVC**
```bash
kubectl create namespace vaultwarden

# Create PVC first (no pod started yet)
helm install vaultwarden-storage ./helm-charts/vaultwarden \
  --namespace vaultwarden \
  --set replicaCount=0
```

**Step 3: Copy data from NixOS**
```bash
# Get old pod info
OLD_POD=$(podman ps --format "{{.Names}}" | grep vaultwarden)

# Copy data
podman cp $OLD_POD:/data /tmp/vaultwarden-backup
kubectl cp /tmp/vaultwarden-backup vaultwarden/vaultwarden-0:/data/
```

**Step 4: Deploy application**
```bash
helm upgrade vaultwarden ./helm-charts/vaultwarden \
  --namespace vaultwarden \
  --set replicaCount=1
```

**Step 5: Validate migration**
```bash
# Check pod status
kubectl get pods -n vaultwardwarden

# Test connectivity
kubectl exec -n vaultwarden deployment/vaultwarden -- curl localhost:80/alive

# Test external access
curl https://vaultwarden.ts.net/alive

# Verify data integrity
kubectl exec -n vaultwarden deployment/vaultardner -- ls -la /data
```

**Step 6: Post-migration backup**
```bash
velero backup create post-vaultwarden \
  --include-namespaces vaultwarden \
  --wait
```

**Step 7: Cleanup NixOS installation**
```bash
# Stop and disable Podman service on Zephyr
# TODO: Add to NixOS configuration
```

### Service 2: n8n (Day 10-11)

Similar process to Vaultwarden with n8n-specific configuration.

### Service 3: SearXNG (Day 12-14)

Since SearXNG is stateless, this is the simplest migration.

---

## Phase 3: Containerized Services (Week 3)

### Service 4: GlitchTip (Day 15-18)

**Pre-Migration:**
```bash
# Backup current GlitchTip setup
velero backup create pre-glitchtip \
  --selector app=glitchtip \
  --wait
```

**Migration Strategy:**
```bash
# Since GlitchTip already uses Podman, we:
# 1. Export PostgreSQL database
# 2. Export Redis data
# 3. Deploy Kubernetes version
# 4. Import data
# 5. Switch traffic
```

---

## Phase 4: Complex Services (Week 4-5)

### Service 5: Nextcloud (Day 22-25)

**Data Migration Planning:**
```bash
# Nextcloud has two components:
# 1. PostgreSQL database (fast-local-ssd)
# 2. Data directory (large-nfs-storage)

# Migration approach:
# 1. Stop Nextcloud on NixOS
# 2. Export PostgreSQL database
# 3. rsync data directory
# 4. Deploy Kubernetes version
# 5. Import database
# 6. Copy data to new location
# 7. Update config.php with new paths
# 8. Start Nextcloud
# 9. Run occ upgrade
# 10. Validate
```

### Service 6: AI Inference Gateway (Day 26-30)

**GPU Scheduling Configuration:**
```yaml
# Add GPU node selector
spec:
  template:
    spec:
      nodeSelector:
        gpu: "nvidia"  # Only schedule on NVIDIA GPUs
      containers:
      - name: ai-gateway
        resources:
          limits:
            nvidia.com/gpu: "1"
```

---

## Phase 5: Automation (Week 6-7)

### Flux GitOps Setup (Day 36-38)

**Step 1: Install Flux**
```bash
# Add Flux repo
helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts

# Install Flux
kubectl create namespace flux-system
helm install flux flux-community/flux2 \
  --namespace flux-system \
  --set git.repository=git@github.com:j_kro/nixos-cluster \
  --set git.path=./gitops-system
```

**Step 2: Configure GitOps**
```bash
# Create gitops directory structure
mkdir -p gitops-system/{apps,infrastructure}

# Move Helm charts to gitops
mv helm-charts gitops-system/apps/

# Create Flux Kustomization
cat > gitops-system/apps/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - vaultwarden
  - n8n
  - searxng
EOF
```

### Auto-Scaling Setup (Day 39-40)

**Install Horizontal Pod Autoscaler:**
```bash
kubectl apply -f https://github.com/kubernetes-s autoscaler/raw/master/cluster-proportional-autoscaler.yaml
```

### Self-Healing Configuration (Day 41-42)

**Configure readiness/liveness probes:**
```yaml
# Add to all deployments
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

---

## Phase 6: Testing & Documentation (Week 8)

### End-to-End Testing (Day 43-45)

**Test Plan:**
1. Service health checks
2. Data integrity verification
3. Disaster recovery testing
4. Performance testing
5. Security validation

### Documentation (Day 46-49)

**Create:**
1. Service-specific runbooks
2. Troubleshooting guides
3. User documentation
4. Architecture diagrams

---

## Rollback Procedures

### Immediate Rollback

```bash
# Option 1: Helm rollback
helm rollback <service> <previous-revision>

# Option 2: Velero restore
velero restore create --from-backup pre-migration-<service> \
  --namespace-mappings production:<service>-recovery

# Option 3: Complete NixOS restore
nixos-rebuild switch --rollback
```

---

## Success Metrics

### Quantitative

| Metric | Target | Measurement |
|--------|--------|------------|
| Services migrated | 7/7 (100%) | kubectl get services |
| Backup success rate | >95% | velero backup get |
| Service availability | >99% | uptime monitoring |
| Rollback time | <5 min | time measurement |
| Resource utilization | Optimized | kubectl top |

### Qualitative

- ✅ All services accessible via friendly DNS names
- ✅ Automated backups running reliably
- ✅ Monitoring dashboards operational
- ✅ Self-healing working (failed pods auto-restarted)
- ✅ Zero manual intervention needed
- ✅ Documentation complete and tested

---

## Troubleshooting

### Common Issues

**Issue: Pod in CrashLoopBackOff**
```bash
# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Common fixes:
# - Image pull errors → Check image name, registry access
# - Resource limits → Increase requests/limits
# - Config errors → Validate ConfigMaps/Secrets
```

**Issue: PVC pending**
```bash
# Check PVC events
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl get storageclass

# Common fixes:
# - Wrong storage class → Update storageClass in values.yaml
# - Node selector → Ensure correct nodes available
# - Storage full → Check disk space on nodes
```

**Issue: Service not accessible**
```bash
# Check service
kubectl get svc <service-name> -n <namespace>

# Check Caddy ingress
kubectl get caddyingress -n <namespace>

# Check DNS
kubectl exec -n <namespace> curl -s http://<service>.cluster.local

# Common fixes:
# - Wrong ingress host → Update annotations
# - Service port mismatch → Check targetPort
# - DNS not resolving → Check CoreDNS
```

---

## Appendix

### Useful Commands

```bash
# Backup operations
velero backup create <name> --include-namespaces <ns>
velero backup get <name>
velero backup describe <name> --details

# Restore operations
velero restore create --from-backup <name>
velero restore get <name>
velero restore describe <name> --details

# Helm operations
helm list
helm status <release>
helm history <release>
helm rollback <release> <revision>

# Pod operations
kubectl get pods -A
kubectl describe pod <pod>
kubectl logs <pod> [-n <namespace>]
kubectl exec -it <pod> -- <command>

# Service operations
kubectl get svc -A
kubectl describe svc <service> [-n <namespace>]
kubectl port-forward svc/<service> <local-port>:<remote-port>

# Storage operations
kubectl get pvc -A
kubectl describe pvc <pvc> [-n <namespace>]
kubectl get pv
kubectl get storageclass
```

---

**Version:** 1.0 | **Last Updated:** 2026-03-18
**Next:** Start Phase 1 - Velero installation
