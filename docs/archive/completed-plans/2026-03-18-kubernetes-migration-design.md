# Kubernetes Migration Design Document
**Status:** Design Complete | **Created:** 2026-03-18 | **Owner:** j_kro | **Last Updated:** 2026-03-18

## Executive Summary

**Objective:** Migrate all containerizable services from NixOS systemd to Kubernetes while maintaining "Apple-easy" simplicity and "Bitcoin-like" reliability.

**Vision:** Separate infrastructure management (NixOS) from application deployment (Kubernetes/Helm), achieving autonomous cluster operation that requires minimal manual intervention.

**Timeline:** 7 weeks for complete migration + 2 weeks for automation

**Success Criteria:**
- ✅ All stateless services running in Kubernetes with auto-discovery
- ✅ Stateful services using PVCs with automated backups
- ✅ GPU workloads scheduled on appropriate nodes
- ✅ Service discovery working (cluster DNS + Caddy Ingress)
- ✅ Monitoring and observability functional
- ✅ Rollback procedures tested and automated
- ✅ Zero-downtime during migration (service-by-service approach)
- ✅ Autonomous operation (auto-backups, auto-healing, auto-updates)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Velero Setup & Integration](#velero-setup--integration)
3. [Helm Chart Design Patterns](#helm-chart-design-patterns)
4. [Storage Architecture](#storage-architecture)
5. [Port Management & Service Discovery](#port-management--service-discovery)
6. [Service-Specific Migration Strategies](#service-specific-migration-strategies)
7. [Caddy Integration & Plugins](#caddy-integration--plugins)
8. [Apple-Easy + Bitcoin-Like Automation](#apple-easy--bitcoin-like-automation)
9. [Implementation Timeline](#implementation-timeline)
10. [Testing & Validation](#testing--validation)
11. [Rollback Procedures](#rollback-procedures)
12. [Documentation & Runbooks](#documentation--runbooks)

---

## Architecture Overview

### Design Philosophy

```
Apple-Easy: "It just works" ✨
├─ Zero configuration required
├─ Automatic discovery & setup
├─ Beautiful defaults (no decisions needed)
├─ Elegant user experience
└─ Thoughtful operation (no manual intervention)

Bitcoin-Like: Trustless & Reliable ⚡
├─ Self-validating systems
├─ Decentralized (no single point of failure)
├─ Automated consensus (K8s reconciler loop)
├─ Immutable infrastructure (GitOps)
└─ Runs itself (no babysitting)
```

### Complete Separation of Concerns

```
┌─────────────────────────────────────────────────────────────┐
│ NixOS (Infrastructure Layer)                                │
│ ├─ Kubernetes cluster (services.kubernetes)                 │
│ ├─ GPU drivers, container runtime                          │
│ ├─ Networking, firewall, storage                           │
│ └─ System packages                                          │
│                                                             │
│ Responsibility: Infrastructure lifecycle                      │
│ Management: nixos-rebuild switch                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes (Application Layer)                              │
│ ├─ Helm Charts (all services)                               │
│ ├─ Velero (backup & disaster recovery)                      │
│ ├─ Caddy Ingress (automatic routing)                         │
│ └─ Monitoring (Prometheus + Grafana)                         │
│                                                             │
│ Responsibility: Application lifecycle                         │
│ Management: helm install/upgrade                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ GitOps Automation Layer                                     │
│ ├─ Flux/ArgoCD (auto-deploy from git)                         │
│ ├─ Velero schedules (automated backups)                     │
│ └─ Auto-scaling & self-healing                              │
│                                                             │
│ Responsibility: Autonomous operation                          │
│ Management: git push (declarative)                            │
└─────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
nixos-cluster/
├── flake.nix                          # NixOS infrastructure ONLY
│
├── kubernetes-manifests/              # Infrastructure manifests (existing)
│   ├── nvidia-device-plugin-daemonset.yaml
│   ├── amd-device-plugin-daemonset.yaml
│   ├── caddy-ingress/                 # ✅ Already deployed
│   └── node-dashboards.yaml           # ✅ Already deployed
│
├── helm-charts/                       # Application layer (NEW)
│   ├── velero/                        # ⭐ Install FIRST
│   ├── vaultwarden/                   # Quick win #1
│   ├── n8n/                           # Quick win #2
│   ├── searxng/                       # Quick win #3
│   ├── glitchtip/                     # Already containerized
│   ├── nextcloud/                     # Complex migration
│   └── ai-inference-gateway/          # GPU workloads
│
├── gitops-system/                     # Automation layer (NEW)
│   ├── flux/                          # Auto-deploys from git
│   └── argocd/                        # Alternative GitOps
│
├── monitoring/                         # Observability (NEW)
│   ├── grafana-dashboards/             # Auto-generated dashboards
│   ├── prometheus-rules/              # Auto-alerting
│   └── loki-logs/                      # Centralized logging
│
└── scripts/                            # Automation scripts (NEW)
    ├── auto-migrate.sh                 # One-command migration
    ├── auto-backup.sh                  # Scheduled backups
    ├── auto-update.sh                  # Auto-updates
    └── health-check.sh                 # Self-healing
```

---

## Velero Setup & Integration

### Architecture

```
Velero Server (Deployment)
├── Pod running in velero namespace
├── CLI tool for backups/restores
└── REST API for scheduling

Storage Backend
├── Garage S3 (already running on Nexus)
├── Bucket: velero-backups
└── Retention: 30 days (configurable)

Backup Targets
├── Kubernetes objects (Deployments, Services, ConfigMaps, Secrets)
├── Persistent Volumes (PVCs with snapshots)
└─ Cluster resources (Namespaces, RBAC)
```

### Helm Chart Configuration

```yaml
# helm-charts/velero/values.yaml
configuration:
  provider: "aws"           # S3-compatible
  backupStorageLocation:
    name: "garage-s3"
    bucket: "velero-backups"
    url: "http://10.1.1.120:3900"  # Garage on Nexus
    insecure: true         # Local S3
  volumeSnapshotLocation:
    provider: "generic"     # Local path provisioner
  defaultBackupTTL: "720h"  # 30 days

initContainers:
  - AWS credentials for Garage
```

### Backup Strategy

**Automatic Daily Backups:**
```yaml
schedule: "0 2 * * *"  # 2 AM daily
retention: 720h        # 30 days
include:
  - "*"
exclude:
  - kube-system
  - local-path-storage
```

**Pre-Migration Backups:**
```bash
velero backup create pre-migration-<service> \
  --include-namespaces <service-namespace> \
  --wait
```

**Post-Migration Verification:**
```bash
velero restore create --from-backup pre-migration-<service> \
  --namespace-mappings <service>:<service>-test
```

---

## Helm Chart Design Patterns

### Standard Chart Structure

Every service follows this consistent pattern:

```
helm-charts/<service-name>/
├── Chart.yaml                    # Chart metadata
├── values.yaml                   # Default configuration
├── values-production.yaml        # Production overrides (optional)
└── templates/
    ├── deployment.yaml           # Main application deployment
    ├── service.yaml              # ClusterIP service
    ├── ingress.yaml              # Caddy ingress route
    ├── pvc.yaml                  # Persistent storage
    ├── configmap.yaml            # Application config
    ├── secret.yaml               # Sensitive data
    ├── backup-cronjob.yaml       # Velero backup integration
    ├── _helpers.tpl               # Template helpers
    └── NOTES.txt                 # Post-install instructions
```

### Template Patterns

**Standard Helper Templates:**
```yaml
# templates/_helpers.tpl
{{- define "service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "service.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "service.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "service.labels" -}}
helm.sh/chart: {{ include "service.chart" . }}
{{ include "service.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

**Automated Caddy Integration:**
```yaml
# templates/caddy-ingress.yaml
{{- if .Values.ingress.enabled -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "service.fullname" . }}
  namespace: {{ .Release.Namespace }}
  annotations:
    # Automatic Caddy integration!
    caddy.frontend.k8s.io/enable: "true"
    caddy.frontend.k8s.io/scheme: "https"
    caddy.frontend.k8s.io/host: {{ .Values.ingress.host }}
    caddy.frontend.k8s.io/tls: "internal"

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
```

**Standard Values Pattern:**
```yaml
# values.yaml
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
  className: caddy

persistence:
  enabled: true
  size: 10Gi
  storageClass: local-path
  accessMode: ReadWriteOnce

resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m

# Apple-Easy: Auto-calculated resources
autoResources:
  enabled: false  # Set to true for AI optimization

backup:
  enabled: true
  schedule: "0 3 * * *"
  retention: 720h
```

---

## Storage Architecture

### Storage Classes

```yaml
# fast-local-ssd (Zephyr 922GB NVMe)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local-ssd
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
parameters:
  node.kubernetes.io/instance-type: "zephyr"
  path: "/mnt/fast-storage"
allowVolumeExpansion: true

---
# large-nfs-storage (Nexus 3.6TB via NFS)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: large-nfs-storage
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
parameters:
  node.kubernetes.io/instance-type: "nexus"
  path: "/mnt/nfs-storage"
allowVolumeExpansion: true

---
# slow-hdd (Sentry 1TB HDD)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: slow-hdd
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
parameters:
  node.kubernetes.io/instance-type: "sentry"
  path: "/mnt/slow-storage"
allowVolumeExpansion: true
```

### Service-to-Storage Mapping

| Service | Storage Class | Size | Node | Rationale |
|---------|--------------|------|------|-----------|
| **Vaultwarden** | fast-local-ssd | 10Gi | Zephyr | SQLite database |
| **n8n** | fast-local-ssd | 5Gi | Zephyr | Workflow data |
| **SearXNG** | N/A | N/A | - | Stateless (cached) |
| **GlitchTip PostgreSQL** | fast-local-ssd | 20Gi | Zephyr | High IOPS database |
| **GlitchTip Redis** | fast-local-ssd | 5Gi | Zephyr | Cache |
| **Nextcloud PostgreSQL** | fast-local-ssd | 20Gi | Zephyr | High IOPS database |
| **Nextcloud Data** | large-nfs-storage | 100Gi | Nexus | Large file storage |
| **AI Models** | fast-local-ssd | 50Gi | Zephyr | Fast loading |
| **Qdrant Vector DB** | fast-local-ssd | 20Gi | Zephyr | Vector embeddings |
| **Monitoring Logs** | slow-hdd | 50Gi | Sentry | Archival storage |

---

## Port Management & Service Discovery

### Kubernetes Service Discovery Pattern

**❌ OLD: Direct port access (NixOS style)**
```bash
curl http://10.1.1.110:8080/health
curl http://10.1.1.110:7777/search
```

**✅ NEW: Service discovery (Kubernetes style)**
```bash
curl http://ai-inference-gateway.default.svc.cluster.local/health
curl http://searxng.default.svc.cluster.local/search
curl http://vaultwarden.vaultwarden.svc.cluster.local
```

### Complete Port Mapping

| Service | Internal Port | External URL | Notes |
|---------|---------------|-------------|-------|
| **Vaultwarden** | 80 | vaultwarden.ts.net | HTTPS only |
| **n8n** | 80 | n8n.cluster.local | HTTPS only |
| **SearXNG** | 80 | search.cluster.local | HTTPS only |
| **GlitchTip** | 8000 | glitchtip.cluster.local | HTTPS only |
| **Nextcloud** | 80 | cloud.cluster.local | HTTPS only |
| **AI Inference Gateway** | 8080 | ai.cluster.local | HTTPS only |
| **Qdrant** | 6333 | (internal only) | Vector DB |
| **Caddy Ingress** | 443 | *.cluster.local | HTTPS only |

### Automated Service Discovery

**Zero-Config Discovery via Annotations:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: vaultwarden
  annotations:
    # ONE annotation → Everything else automatic
    auto-discovery: "enabled"

    # Caddy automatically:
    caddy.frontend.k8s.io/enable: "true"
    caddy.frontend.k8s.io/host: "vaultwarden.ts.net"
    caddy.frontend.k8s.io/tls: "internal"

    # Prometheus automatically:
    prometheus.io/scrape: "true"
    prometheus.io/port: "80"

    # Service discovery automatically:
    discovery.enabled: "true"
spec:
  type: ClusterIP
  ports:
  - port: 80
    selector:
      app: vaultwarden
```

**What Happens Automatically:**
```bash
✅ DNS: vaultwarden.vaultwarden.svc.cluster.local
✅ Route: https://vaultwarden.ts.net (Caddy)
✅ Metrics: http://vaultwarden:80/metrics (Prometheus)
✅ Discovery: All other services can find it via DNS
✅ Monitoring: Auto-scraped, auto-alerted
```

---

## Service-Specific Migration Strategies

### Phase 1: Quick Wins (Week 1)

#### 1. Vaultwarden (1-2 hours)
**Current:** Podman container (systemd → podman)
**Migration:**
```bash
# Pre-migration backup
velero backup create pre-vaultwarden

# Deploy with Helm
helm install vaultwarden ./helm-charts/vaultwarden \
  --set persistence.storageClass=fast-local-ssd

# Copy SQLite database
kubectl cp /var/lib/vaultwarden vaultwarden-0:/data/

# Post-migration backup
velero backup create post-vaultwarden
```

#### 2. n8n (2-3 hours)
**Current:** Simple systemd service
**Migration:**
- Small database migration
- Minimal dependencies
- Fast rollback if needed

#### 3. SearXNG (2-3 hours)
**Current:** systemd service (stateless)
**Migration:**
- Purely stateless = Fastest migration
- No database
- Instant rollback

### Phase 2: Already Containerized (Week 2)

#### 4. GlitchTip (3-4 hours)
**Current:** Podman (4 containers: web + worker + postgres + redis)
**Migration:**
- Proven Podman patterns → Kubernetes
- Database migration (PVC + data copy)
- Redis cache migration

### Phase 3: Complex Services (Week 3-4)

#### 5. Nextcloud (4-6 hours)
**Current:** systemd + PostgreSQL + Redis + nginx
**Migration:**
- Large data migration (files)
- Database export/import
- User session handling

#### 6. AI Inference Gateway (8-12 hours)
**Current:** Complex FastAPI service with multiple backends
**Migration:**
- GPU scheduling
- Qdrant vector database migration
- Redis middleware
- MCP server integrations

---

## Caddy Integration & Plugins

### Current Unbound Configuration

You already have **excellent DNS setup:**
- ✅ Wildcard DNS: `*.cluster.local → Caddy Ingress`
- ✅ Security-focused upstreams (Quad9, Cloudflare, Google DoT)
- ✅ Privacy blocking (VRChat/Unity analytics)
- ✅ Tailscale MagicDNS integration
- ✅ Local zones for cluster.local, lan domains

### Caddy Plugins for Your Cluster

#### DNS & TLS Plugins
```yaml
annotations:
  # Internal certificate authority
  caddy.frontend.k8s.io/tls: "internal"

  # Or Let's Encrypt for public domains
  caddy.frontend.k8s.io/tls: "letsencrypt"
  caddy.frontend.k8s.io/email: "admin@tigris-ule.ts.net"
```

#### Security Plugins
```yaml
annotations:
  # Automatic security headers
  caddy.frontend.k8s.io/security-headers: "true"
  caddy.frontend.k8s.io/hsts: "max-age=31536000"

  # Rate limiting
  caddy.frontend.k8s.io/rate-limit: "100r/10s"

  # Compression
  caddy.frontend.k8s.io/compress: "true"
```

#### Monitoring Plugins
```yaml
annotations:
  # Automatic metrics
  caddy.frontend.k8s.io/metrics: "/metrics"
  caddy.frontend.k8s.io/metrics-prometheus: "true"

  # JSON logging
  caddy.frontend.k8s.io/log-format: "json"
```

---

## Apple-Easy + Bitcoin-Like Automation

### Zero-Config Service Discovery

**Apple-Easy: No manual DNS configuration**

```yaml
# ONE annotation → Everything else automatic
metadata:
  annotations:
    auto-discovery: "enabled"
```

**Automatically happens:**
```bash
✅ DNS: my-app.cluster.local
✅ HTTPS: Valid cert auto-generated
✅ Routing: Caddy automatically proxies
✅ Metrics: Prometheus auto-scrapes
✅ Logging: Loki auto-collects
✅ Backup: Velero auto-snapshots
```

### One-Command Deployments

**Bitcoin-Like: Trustless deployment**

```bash
# Single command → Complete service deployment
helm install my-app ./helm-charts/my-app

# Automatic behind the scenes:
✅ PVC created (right size, right node)
✅ Database deployed (if needed)
✅ ConfigMaps generated (smart defaults)
✅ Secrets created (auto-generated passwords)
✅ Ingress route created (HTTPS enabled)
✅ Health checks configured (smart defaults)
✅ Monitoring enabled (auto-scrape targets)
✅ Backup scheduled (automated)
✅ Rollback ready (previous versions kept)
```

### Self-Healing GitOps

**Bitcoin-Like: Immutable state, automated reconciliation**

```yaml
gitops-cluster/
├── infrastructure/
│   └── nixos/  # NixOS manages K8s infrastructure
├── apps/
│   ├── helm-charts/     # All service charts
│   └── values/          # Environment configs
└── flux-system/         # Auto-deploys from git

# Automatic reconciliation loop:
Git push → Flux detects change → Auto-applies to K8s → Auto-validates
   ↑                                                            │
   └────────────────────────── Self-healing loop ──────────────┘
```

### Autonomous Operation

**Zero-Thought Operations:**

```bash
# Deploy once, runs forever
helm install vaultwarden ./helm-charts/vaultwarden

# That's it. No maintenance needed:
✅ Auto-updates (smart version detection)
✅ Auto-backups (every 3AM)
✅ Auto-scaling (based on load)
✅ Auto-healing (failed pods restarted)
✅ Auto-monitoring (alerts if something breaks)
✅ Auto-cleanup (old backups removed)
```

### Complete Automation Stack

```yaml
automation:
  # Auto-updates (smart, no breakage)
  auto-updates:
    enabled: true
    test-first: true        # Test in staging first
    rollback-on-fail: true

  # Auto-backups (never forget)
  auto-backups:
    enabled: true
    schedule: "0 3 * * *"  # 3AM daily

  # Auto-cleanup (prevent storage bloat)
  auto-cleanup:
    enabled: true
    old-backups: "keep-last-30"
    old-logs: "keep-last-7d"

  # auto-scaling (handle load spikes)
  auto-scaling:
    enabled: true
    scale-up-threshold: "80% CPU"
    scale-down-threshold: "20% CPU"
```

---

## Implementation Timeline

### Week 1-2: Foundation

**Objectives:**
- Deploy Velero (backup foundation)
- Set up Helm chart structure
- Deploy Grafana dashboards
- Configure Prometheus targets
- Test backup/restore procedures

**Tasks:**
1. Install Velero Helm chart
2. Configure Garage S3 backend
3. Create Velero backup schedules
4. Test backup and restore
5. Create standard Helm chart template
6. Deploy Grafana dashboards
7. Configure Prometheus targets
8. Validate monitoring stack

### Week 3: Quick Wins

**Objectives:**
- Migrate Vaultwarden (simple Podman → K8s)
- Migrate n8n (systemd → K8s)
- Migrate SearXNG (stateless → K8s)
- Validate automation patterns

**Tasks:**
1. Migrate Vaultwarden
2. Migrate n8n
3. Migrate SearXNG
4. Test rollback procedures
5. Document lessons learned

### Week 4: Containerized Services

**Objectives:**
- Migrate GlitchTip (Podman → K8s)
- Test database migrations
- Validate PVC patterns

**Tasks:**
1. Migrate GlitchTip PostgreSQL
2. Migrate GlitchTip Redis
3. Migrate GlitchTip web/worker
4. Test multi-service communication

### Week 5-6: Complex Services

**Objectives:**
- Migrate Nextcloud (data planning)
- Migrate AI Inference Gateway
- GPU scheduling validation

**Tasks:**
1. Plan Nextcloud data migration
2. Migrate Nextcloud database
3. Migrate Nextcloud data
4. Configure GPU node selectors
5. Deploy AI Inference Gateway
6. Test GPU workloads

### Week 7: Automation

**Objectives:**
- Install Flux/ArgoCD (GitOps)
- Configure auto-updates
- Setup auto-cleanup
- Deploy beautiful dashboards

**Tasks:**
1. Install Flux/ArgoCD
2. Configure GitOps workflow
3. Setup auto-scaling
4. Configure self-healing
5. Deploy beautiful dashboards
6. Final testing

### Week 8: Testing & Documentation

**Objectives:**
- Final testing
- Documentation
- Celebration! 🎉

**Tasks:**
1. End-to-end testing
2. Performance testing
3. Disaster recovery testing
4. Write runbooks
5. Create user guides
6. Celebrate success!

---

## Testing & Validation

### Pre-Migration Checklist

For each service migration:
- [ ] Velero backup created
- [ ] PVC created and accessible
- [ ] Data migration plan documented
- [ ] Rollback plan tested
- [ ] Monitoring configured
- [ ] Logging configured
- [ ] Health checks configured

### Post-Migration Validation

```bash
# 1. Health check
kubectl get pods -l app=<service>
kubectl describe pod <service-pod>

# 2. Service connectivity
kubectl exec -it <service-pod> -- curl localhost:<port>/health

# 3. External access
curl https://<service-hostname>/health

# 4. Data integrity
kubectl exec -it <service-pod> -- ls -la /data

# 5. Resource usage
kubectl top pods -n <service-namespace>

# 6. Monitoring
kubectl logs -n <service-namespace> deployment/<service>
```

### Automated Testing Script

```bash
#!/bin/bash
# scripts/validate-migration.sh

SERVICE=$1
NAMESPACE=${2:-production}

echo "🔍 Validating $SERVICE migration..."

# Health check
kubectl rollout status deployment/$SERVICE -n $NAMESPACE

# Pod health
kubectl get pods -n $NAMESPACE -l app=$SERVICE

# Service connectivity
kubectl exec -it $SERVICE-0 -n $NAMESPACE -- curl localhost:8080/health

# External access
curl -f https://$SERVICE.cluster.local/health || exit 1

echo "✅ $SERVICE migration validated!"
```

---

## Rollback Procedures

### Immediate Rollback (Helm)

```bash
# 1. Immediate Helm rollback
helm rollback <service> <previous-revision>

# 2. Verify rollback
kubectl get pods -l app=<service>

# 3. Test connectivity
curl https://<service>.cluster.local/health
```

### Velero Restore Rollback

```bash
# If Helm rollback fails, Velero restore
velero restore create --from-backup pre-migration-<service> \
  --namespace-mappings production:<service>-recovery

# Verify restored data
kubectl get pods -n <service>-recovery
kubectl logs -n <service>-recovery deployment/<service>
```

### Complete Disaster Recovery

```bash
# Worst case: Complete cluster restore
velero restore create --from-backup <cluster-backup> \
  --include-namespaces --all

# Verify all services
kubectl get pods --all-namespaces
```

---

## Documentation & Runbooks

### Required Documentation

1. **Design Document** (this file)
2. **Implementation Plan** (detailed step-by-step)
3. **Service Migration Guides** (per-service instructions)
4. **Runbooks** (operational procedures)
5. **Troubleshooting Guides** (common issues and fixes)

### Runbook Templates

**Service Deployment Runbook:**
```markdown
# Deploying <Service>

## Prerequisites
- [ ] Velero installed and configured
- [ ] Storage class available
- [ ] Backup completed

## Deployment Steps
1. Create pre-migration backup
2. Deploy Helm chart
3. Migrate data (if applicable)
4. Validate deployment
5. Create post-migration backup

## Validation
- [ ] Health check passes
- [ ] External access works
- [ ] Data integrity verified
- [ ] Monitoring configured

## Rollback
If validation fails:
1. Helm rollback: `helm rollback <service>`
2. Or Velero restore: `velero restore create --from-backup pre-migration-<service>`
```

---

**Next Steps:**

1. ✅ Design document complete
2. **Create implementation plan** - Detailed step-by-step guide
3. **Start Phase 1** - Begin Velero installation and first migrations

Ready to proceed with **all three** - design documented, implementation plan, and Phase 1 kickoff?

---

**Version:** 1.0 | **Last Updated:** 2026-03-18
**Changes:** Initial design complete, ready for implementation phase
