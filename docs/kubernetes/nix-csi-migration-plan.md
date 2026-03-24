# nix-csi Migration Plan: From SSH Builds to Kubernetes-Native

**Created:** 2026-03-23
**Status:** Strategic Planning
**Related:** nix-oci exploration, distributed-builds.nix
**Target:** Complete Nix/Kubernetes integration using nix-csi

---

## Executive Summary

**Current State:** SSH-based distributed builds to nexus, forge, sentry via `/etc/nix/machines`
**Target State:** nix-csi driver on all nodes, build pods in Kubernetes, ephemeral /nix mounting
**Migration Timeline:** 3-6 months (phased approach)
**Risk Level:** Medium (can roll back at any phase)

**Key Insight:** This isn't just about builds—it's about making **every Kubernetes workload Nix-aware** without container image rebuilds.

---

## Part 1: Current Architecture Analysis

### What You Have Now

```
┌─────────────────────────────────────────────────┐
│ Zephyr (Control Plane)                         │
│  - Local Nix daemon                              │
│  - /etc/nix/machines → SSH to remote builders    │
│  - Builds distribute to: nexus, forge, sentry    │
└─────────────────────────────────────────────────┘
                    │
                    │ SSH (nexus)
                    ▼
┌─────────────────────────────────────────────────┐
│ Nexus (Storage Worker)                          │
│  - nix-daemon running                           │
│  - Accepts SSH connections                      │
│  - Builds and returns store paths               │
└─────────────────────────────────────────────────┘
                    │
                    │ SSH (forge, sentry)
                    ▼
┌─────────────────────────────────────────────────┐
│ Forge/Sentry (GPU/Monitoring)                   │
│  - nix-daemon running                           │
│  - Accepts SSH connections                      │
│  - Builds and returns store paths               │
└─────────────────────────────────────────────────┘
```

### Limitations of Current Approach

| Issue | Impact | Why nix-csi Helps |
|-------|--------|------------------|
| **SSH key management** | Medium complexity | No SSH needed (K8s RBAC) |
| **Static builder list** | Not elastic | K8s auto-scales build pods |
| **Node affinity** | Manual placement | K8s scheduler handles placement |
| **No K8s integration** | Siloed infrastructure | Native K8s resource |
| **Fixed resources** | Over-provision or starve | Request per build |
| **Build isolation** | Shared daemon | Pod per build |

---

## Part 2: Target Architecture (nix-csi)

### Vision: Kubernetes-Native Nix

```
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Build Controller (Deployment/HPA)                   │   │
│  │  - Monitors build queue                             │   │
│  │  - Spawns build pods on demand                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          │ Spawns build job               │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Build Pod (ephemeral)                               │   │
│  │  ┌──────────────┐                                   │   │
│  │  │ nix-daemon   │  (Runs build)                     │   │
│  │  └──────────────┘                                   │   │
│  │             │                                         │   │
│  │             │ CSI ephemeral volume                   │   │
│  │             ▼                                         │   │
│  │  ┌──────────────────┐                               │   │
│  │  │ /nix (mounted)   │  (via nix-csi)                 │   │
│  │  └──────────────────┘                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          │ Returns result                 │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Persistent Volume Store (build results)             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Regular Workloads (AI gateway, web apps, etc.)      │   │
│  │  ┌──────────────┐                                   │   │
│  │  │ Container    │  (No Nix installed!)             │   │
│  │  └──────────────┘                                   │   │
│  │             │                                         │   │
│  │             │ CSI ephemeral volume                   │   │
│  │             ▼                                         │   │
│  │  ┌──────────────────┐                               │   │
│  │  │ /nix (mounted)   │  (specific packages only)      │   │
│  │  └──────────────────┘                               │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ CSI: NodePublishVolume
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Each Node (Zephyr, Nexus, Forge, Sentry)                  │
│  ┌──────────────┐                                         │
│  │ nix-csi      │  (DaemonSet, 1 pod per node)           │
│  │ driver       │                                         │
│  └──────────────┘                                         │
│             │                                               │
│             │ Mounts host /nix/store into pods            │
│             ▼                                               │
│  ┌──────────────────┐                                     │
│  │ /nix/store       │  (Shared Nix store)                │
│  │ (host path)      │                                     │
│  └──────────────────┘                                     │
└─────────────────────────────────────────────────────────────┘
```

### Key Changes

| Component | Before (SSH) | After (nix-csi) |
|-----------|--------------|-----------------|
| **Build execution** | SSH to remote hosts | Kubernetes Job/Pod |
| **/nix access** | SSH mount | CSI ephemeral volume |
| **Scaling** | Edit /etc/nix/machines | HPA on build pods |
| **Scheduling** | SSH connection | K8s scheduler |
| **Authentication** | SSH keys | K8s RBAC |
| **Workload isolation** | Shared daemon | Pod per build |
| **Resource management** | Manual (cores setting) | Resource requests/limits |

---

## Part 3: Migration Strategy

### Phase 1: Coexistence (Weeks 1-4) ✅ LOW RISK

**Goal:** Deploy nix-csi alongside existing SSH builders

**Actions:**

1. **Deploy nix-csi Driver**
   ```bash
   # Clone and deploy
   git clone https://github.com/Lillecarl/nix-csi.git /tmp/nix-csi
   cd /tmp/nix-csi
   kubectl apply -f kubenix/deploy/

   # Verify
   kubectl get csidriver | grep nix
   kubectl get pods -n kube-system | grep nix-csi
   ```

2. **Test Namespace Deployment**
   ```yaml
   # kubectl create namespace nix-csi-test

   # Test pod with nix-csi
   apiVersion: v1
   kind: Pod
   metadata:
     name: test-nix-csi
     namespace: nix-csi-test
   spec:
     containers:
     - name: test
       image: alpine:latest
       command: ["sh"]
       args: ["-c", "ls -la /nix && /nix/store/hello-.../bin/hello"]
       volumeMounts:
       - name: nix-hello
         mountPath: /nix
     volumes:
     - name: nix-hello
       csi:
         driver: nix-csi
         volumeAttributes:
           flakeRef: github:nixos/nixpkgs/nixos-unstable#hello
   ```

3. **Keep SSH Builders Active**
   - Don't modify `/etc/nix/machines`
   - Don't change `distributed-builds.nix`
   - Existing builds continue working

**Success Criteria:**
- ✅ nix-csi driver running on all nodes
- ✅ Test pod can mount Nix packages
- ✅ SSH builders still functional
- ✅ No build failures

**Rollback:** `kubectl delete -f /tmp/nix-csi/kubenix/deploy/`

---

### Phase 2: Gradual Workload Migration (Weeks 5-12) 🟡 MEDIUM RISK

**Goal:** Migrate specific workloads to nix-csi

**Workload Categories:**

#### Category 1: CI/CD Pipelines (Easiest)

**Current:** Jenkins/GitLab runners build via SSH
**Target:** Runners use nix-csi for packages

```yaml
# Example: GitLab runner with nix-csi
apiVersion: v1
kind: Pod
metadata:
  name: gitlab-runner
spec:
  containers:
  - name: runner
    image: gitlab/gitlab-runner:latest
    volumeMounts:
    - name: nix-build-deps
      mountPath: /nix
    - name: runner-config
      mountPath: /etc/gitlab-runner
  volumes:
  - name: nix-build-deps
    csi:
      driver: nix-csi
      volumeAttributes:
        nixExpr: |
          let pkgs = import <nixpkgs> {}; in
          pkgs.symlinkJoin {
            name = "build-tools";
            paths = with pkgs; [
              gnumake gcc python3 nodejs go
            ];
          }
  - name: runner-config
    configMap:
      name: gitlab-runner-config
```

**Benefits:**
- No Nix installation in runner image
- Packages auto-mounted
- Ephemeral (auto-cleanup)

#### Category 2: AI Inference Gateway (High Value)

**Current:** Gateway container has Nix packages baked in
**Target:** Gateway pod mounts packages via nix-csi

```yaml
# modules/services/ai-inference/gateway-k8s-nix-csi.yaml
apiVersion: v1
kind: Deployment
metadata:
  name: ai-inference-gateway
  namespace: ai-inference
spec:
  template:
    spec:
      containers:
      - name: gateway
        image: alpine:latest  # Minimal base image!
        command: ["python3"]
        args: ["-m", "ai_inference_gateway.main"]
        volumeMounts:
        - name: nix-gateway-deps
          mountPath: /usr/local/lib/python3.13/site-packages
        - name: nix-bin
          mountPath: /usr/local/bin
      volumes:
      - name: nix-gateway-deps
        csi:
          driver: nix-csi
          volumeAttributes:
            nixExpr: |
              let
                pkgs = import <nixpkgs> {};
                python = pkgs.python313;
              in
              pkgs.symlinkJoin {
                name = "gateway-packages";
                paths = with python.pkgs; [
                  fastapi uvicorn httpx openai anthropic
                  prometheus-client redis qdrant-client
                  beautifulsoup4 lxml
                ];
              }
      - name: nix-bin
        csi:
          driver: nix-csi
          volumeAttributes:
            nixExpr: |
              let pkgs = import <nixpkgs> {}; in
              pkgs.symlinkJoin {
                name = "binaries";
                paths = [pkgs.python313];
              }
```

**Benefits:**
- **Smaller container images** (Alpine vs full Nix)
- **Faster updates** (no image rebuild for package changes)
- **A/B testing** (mount different package versions)
- **Rollback** (change flakeRef to revert)

#### Category 3: Development Workloads (Medium Effort)

**Current:** Devs SSH into cluster, run Nix commands
**Target:** Dev pods with nix-csi mounted tools

```yaml
# kubectl apply -f dev-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-dev-environment
spec:
  containers:
  - name: dev
    image: alpine:latest
    command: ["sleep"]
    args: ["infinity"]
    volumeMounts:
    - name: dev-tools
      mountPath: /usr/local
    - name: project-src
      mountPath: /src
  volumes:
  - name: dev-tools
    csi:
      driver: nix-csi
      volumeAttributes:
        nixExpr: |
          let
            pkgs = import <nixpkgs> {};
          in
          pkgs.symlinkJoin {
            name = "dev-environment";
            paths = with pkgs; [
              vim git ripgrep fd jq tmux
              go nodejs python3 rustc cargo
              docker-compose kubectl helm
            ];
          }
  - name: project-src
    persistentVolumeClaim:
      claimName: my-project-code
```

**Benefits:**
- Instant dev environments
- No local Nix installation needed
- Consistent tools across team

#### Category 4: Build Infrastructure (Advanced)

**Current:** `nixos-rebuild` uses SSH builders
**Target:** nixos-rebuild runs in K8s pod with nix-csi

```yaml
# kubenix/build-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: nixos-rebuild-zephyr
spec:
  template:
    spec:
      containers:
      - name: rebuilder
        image: nixpkgs/nix-flake:latest
        command: ["nixos-rebuild"]
        args: ["switch", "--install-bootloader", "true"]
        volumeMounts:
        - name: nix-store
          mountPath: /nix
        - name: boot
          mountPath: /boot
        - name: etc
          mountPath: /etc
      volumes:
      - name: nix-store
        hostPath:
          path: /nix
          type: Directory
      - name: boot
        hostPath:
          path: /boot
          type: Directory
      - name: etc
        hostPath:
          path: /etc/nixos
          type: DirectoryOrCreate
      restartPolicy: Never
  backoffLimit: 1
```

**Benefits:**
- Builds run in pods (can schedule anywhere)
- Resource limits per build
- Build history in Kubernetes logs
- Can run multiple builds in parallel

**Success Criteria (Phase 2):**
- ✅ CI/CD runners using nix-csi
- ✅ Gateway migrated to nix-csi
- ✅ Dev pods available
- ✅ SSH builders still operational (fallback)

**Rollback:** Update deployments to use old container images

---

### Phase 3: Build Pod Infrastructure (Weeks 13-20) 🟡 MEDIUM RISK

**Goal:** Implement Kubernetes-native build system

#### Build Queue System

**Component 1: Build Queue (Redis)**

```yaml
# kubernetes-manifests/build/redis.yaml
apiVersion: v1
kind: Service
metadata:
  name: build-queue
  namespace: build-system
spec:
  selector:
    app: build-queue
  ports:
  - port: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: build-queue
  namespace: build-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: build-queue
  template:
    metadata:
      labels:
        app: build-queue
    spec:
      containers:
      - name: redis
        image: redis:7
        ports:
        - containerPort: 6379
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
```

**Component 2: Build Controller**

```yaml
# kubernetes-manifests/build/controller.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: build-controller
  namespace: build-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: build-controller
  template:
    metadata:
      labels:
        app: build-controller
    spec:
      containers:
      - name: controller
        image: ghcr.io/your-org/build-controller:latest
        env:
        - name: REDIS_URL
          value: "redis://build-queue.build-system.svc.cluster.local:6379"
        - name: KUBECONFIG
          value: "/kubeconfig/config"
        volumeMounts:
        - name: kubeconfig
          mountPath: /kubeconfig
        - name: nix-csi-test
          mountPath: /nix
      volumes:
      - name: kubeconfig
        secret:
          secretName: build-controller-kubeconfig
      - name: nix-csi-test
        csi:
          driver: nix-csi
          volumeAttributes:
            flakeRef: .#build-controller-package
```

**Component 3: Build Worker Template**

```yaml
# kubernetes-manifests/build/worker-template.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: nix-build-job
  namespace: build-system
spec:
  template:
    spec:
      containers:
      - name: builder
        image: nixpkgs/nix-flake:latest
        command: ["nix-build"]
        args: ["$(DERIVATION_PATH)"]
        env:
        - name: DERIVATION_PATH
          value: "/drvpath"
        volumeMounts:
        - name: nix-store
          mountPath: /nix
        - name: build-output
          mountPath: /output
      volumes:
      - name: nix-store
        hostPath:
          path: /nix
          type: Directory
      - name: build-output
        emptyDir: {}
      restartPolicy: OnFailure
  backoffLimit: 3
```

#### HorizontalPodAutoscaler for Build Workers

```yaml
# kubernetes-manifests/build/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nix-build-workers
  namespace: build-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: build-worker
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageValue: 700m
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageValue: 1Gi
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

**Success Criteria (Phase 3):**
- ✅ Build queue operational
- ✅ Build controller submitting jobs
- ✅ Workers auto-scaling
- ✅ Build results stored in PVCs

---

### Phase 4: Complete Migration (Weeks 21-24) 🔴 HIGH RISK

**Goal:** nix-csi primary, SSH builders deprecated

#### Actions

1. **Update all workloads to use nix-csi**
   - Gateway deployments
   - CI/CD runners
   - Development pods
   - Build infrastructure

2. **Deprecate SSH builders**
   ```nix
   # modules/system/distributed-builds.nix
   {
     nix = {
       distributedBuilds = lib.mkForce false;  # Disable SSH
       # ... rest of config
     };
   }
   ```

3. **Remove SSH keys**
   ```bash
   # Optional: Remove from /etc/nixos/ssh/
   rm id_ed25519 id_ed25519.pub
   git rm ssh/id_ed25519 ssh/id_ed25519.pub
   ```

4. **Document SSH fallback**
   - Keep SSH builder config in git history
   - Document rollback procedure
   - Emergency runbook

**Success Criteria (Phase 4):**
- ✅ All workloads using nix-csi
- ✅ SSH builders disabled
- ✅ No build failures
- ✅ Performance acceptable

**Rollback:** Re-enable `distributedBuilds = true`, redeploy old workloads

---

## Part 4: Workload Migration Guide

### Pattern 1: Stateful Services (Gateway, Databases)

**Before (SSH builders, container image with Nix):**
```dockerfile
# Container has Nix packages baked in
FROM nixpkgs/nix-flake:latest
COPY . /app
RUN nix-build /app
ENTRYPOINT ["/app/result/bin/gateway"]
```

**After (nix-csi, minimal image):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
spec:
  template:
    spec:
      containers:
      - name: gateway
        image: alpine:latest  # Minimal!
        command: ["python3"]
        args: ["-m", "ai_inference_gateway.main"]
        volumeMounts:
        - name: gateway-deps
          mountPath: /usr/local/lib/python3.13
        - name: nix-bin
          mountPath: /usr/local/bin
      volumes:
      - name: gateway-deps
        csi:
          driver: nix-csi
          volumeAttributes:
            flakeRef: github:your-org/ai-inference-gateway#python-deps
      - name: nix-bin
        csi:
          driver: nix-csi
          volumeAttributes:
            flakeRef: github:nixos/nixpkgs/nixos-unstable#python313
```

**Benefits:**
- Container image: 5GB → 50MB
- Package updates: No rebuild needed
- Rollback: Change flakeRef to previous version

### Pattern 2: CI/CD Pipelines

**Before (SSH builder):**
```yaml
# GitLab CI
job:
  script:
    - nix-build .#myPackage
    - nix-shell .#devEnvironment --run 'pytest'
```

**After (nix-csi pod):**
```yaml
# GitLab CI with nix-csi
job:
  image: alpine:latest  # No Nix needed!
  script:
    - pytest  # Mounted from /nix
  volumes:
  - name: nix-ci-deps
    csi:
      driver: nix-csi
      volumeAttributes:
        nixExpr: |
          let pkgs = import <nixpkgs> {}; in
          pkgs.symlinkJoin {
            name = "ci-tools";
            paths = [pkgs.pytest pkgs.python3];
          }
```

### Pattern 3: Development Environments

**Before (Dev installs Nix locally):**
```bash
# Dev's laptop
nix-shell
# Or
nix-env -iA myPackage
```

**After (nix-csi pod):**
```bash
# kubectl apply -f dev-pod.yaml
kubectl exec -it dev-pod -- sh

# Inside pod: all Nix tools available!
$ vim --version
VIM - Vi IMproved 9.1
$ go version
go version go1.22
```

---

## Part 5: Storage Architecture Changes

### Current Storage

```
Node: Zephyr
  /nix/store (local SSD, 931GB)
  └── All packages stored locally
```

### Target Storage (nix-csi)

```
Node: Zephyr
  /nix/store (local SSD, 931GB)
  └── Shared via CSI to all pods

Node: Nexus
  /nix/store (local HDD, 3.8TB)
  └── Shared via CSI to all pods

Node: Forge
  /nix/store (local SSD, 446GB)
  └── Shared via CSI to all pods

Node: Sentry
  /nix/store (HDD, 230GB + 1TB)
  └── Shared via CSI to all pods
```

**Benefits:**
- No replication needed (pods use local node's store)
- Auto-remounts on pod restart
- Ephemeral (no cleanup needed)

### Optional: Shared NFS Cache (Future Enhancement)

```yaml
# Optional: NFS-mounted /nix/store cache
apiVersion: v1
kind: DaemonSet
metadata:
  name: nix-cache-syncer
spec:
  selector:
    matchLabels:
      app: nix-cache-syncer
  template:
    metadata:
      labels:
        app: nix-cache-syncer
    spec:
      containers:
      - name: syncer
        image: nfs-provisioner:latest
        args:
        - -provisioner=nix-cache
        - -device=/nix/store-cache
        volumeMounts:
        - name: nfs-share
          mountPath: /nfs
      volumes:
      - name: nfs-share
        nfs:
          server: 10.1.1.110
          path: /nix-shared
```

---

## Part 6: Security Changes

### Before: SSH Key Authentication

```bash
# /etc/nix/machines
ssh-ng://j_kro@nexus x86_64-linux /etc/nixos/ssh/id_ed25519 6 5
ssh-ng://j_kro@forge x86_64-linux /etc/nixos/ssh/id_ed25519 1 2
ssh-ng://j_kro@sentry x86_64-linux /etc/nixos/ssh/id_ed25519 4 3
```

**Security concerns:**
- SSH key management
- Key rotation
- Key compromise affects all nodes

### After: Kubernetes RBAC

```yaml
# RBAC for build system
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nix-builder
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["create", "delete"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["create", "delete", "get", "list"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["create", "delete", "get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: nix-builder-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: nix-builder
subjects:
- kind: ServiceAccount
  name: build-controller
  namespace: build-system
```

**Benefits:**
- No SSH keys needed
- K8s RBAC integration
- Audit logging in Kubernetes
- Per-namespace permissions

---

## Part 7: Performance Comparison

### Current: SSH Builders

| Metric | Value |
|--------|-------|
| **Build latency** | ~2-5s (SSH connection + build) |
| **Throughput** | Limited by SSH connections |
| **Scalability** | Manual (edit machines file) |
| **Resource usage** | Fixed (cores setting in nix.conf) |

### Target: nix-csi + Build Pods

| Metric | Value |
|--------|-------|
| **Build latency** | ~1-3s (Pod startup + CSI mount + build) |
| **Throughput** | Elastic (HPA auto-scales) |
| **Scalability** | Automatic (based on queue length) |
| **Resource usage** | Per-pod requests/limits |

**Benchmarks needed:**
- Same build on SSH vs nix-csi
- Concurrent build performance
- Resource utilization comparison
- Cold start vs warm cache

---

## Part 8: Cost Analysis

### Current Costs (SSH Builders)

| Item | Cost |
|------|------|
| **SSH key management** | Low (manual) |
| **Static builder capacity** | Medium (over-provision for peaks) |
| **Maintenance** | Medium (SSH issues, key rotation) |
| **Scalability limits** | High (manual scaling) |

### Target Costs (nix-csi)

| Item | Cost |
|------|------|
| **nix-csi driver** | Low (DaemonSet, minimal resources) |
| **Build queue** | Low (Redis pod) |
| **Build controller** | Low (1 replica) |
| **Elastic scaling** | **Savings** (scale to zero when idle) |
| **Maintenance** | Medium (K8s-native ops) |

**ROI:** Positive if cluster has variable build load

---

## Part 9: Migration Checklist

### Pre-Migration

- [ ] Backup current `/etc/nix/machines`
- [ ] Document current SSH builder performance
- [ ] Create nix-csi-test namespace
- [ ] Deploy nix-csi to test namespace
- [ ] Test with simple pod (hello package)
- [ ] Verify CSI driver registered

### Phase 1: Coexistence (Weeks 1-4)

- [ ] Deploy nix-csi to all nodes
- [ ] Verify nix-csi pods running
- [ ] Test namespace validation
- [ ] Keep SSH builders active
- [ ] Monitor for conflicts

### Phase 2: Workload Migration (Weeks 5-12)

- [ ] Migrate CI/CD runners
- [ ] Migrate AI inference gateway
- [ ] Create dev pod templates
- [ ] Update documentation
- [ ] Train team on new workflows

### Phase 3: Build Infrastructure (Weeks 13-20)

- [ ] Deploy build queue (Redis)
- [ ] Deploy build controller
- [ ] Create build worker templates
- [ ] Configure HPA for workers
- [ ] Test end-to-end builds

### Phase 4: Complete Migration (Weeks 21-24)

- [ ] Update all remaining workloads
- [ ] Disable SSH builders
- [ ] Remove SSH keys
- [ ] Document rollback procedure
- [ ] Run performance benchmarks

---

## Part 10: Rollback Plan

### If Phase 1 Fails

```bash
# Remove nix-csi
kubectl delete -f /tmp/nix-csi/kubenix/deploy/

# Verify SSH builders still work
nix-build '<nixpkgs>' -A hello
```

### If Phase 2 Fails

```bash
# Revert workloads to old images
kubectl rollout undo deployment/ai-inference-gateway

# Or update to previous commit
kubectl set image deployment/ai-inference-gateway \
  gateway=ghcr.io/your-org/gateway:v1.0.0
```

### If Phase 3 Fails

```bash
# Scale down build system
kubectl scale deployment build-controller --replicas=0

# Re-enable SSH builders
# Edit modules/system/distributed-builds.nix
nix.distributedBuilds = true;

# Rebuild
sudo nixos-rebuild switch
```

### If Phase 4 Fails

```bash
# Emergency: Re-enable SSH immediately
sudo nixos-rebuild switch --upgrade \
  --option distributed-builds=true

# Verify builders
cat /etc/nix/machines
```

---

## Part 11: Monitoring & Observability

### Metrics to Track

**Build Performance:**
- Build duration (SSH vs nix-csi)
- Queue length (build system)
- Pod startup time
- CSI mount latency

**Resource Usage:**
- CPU per build (SSH vs pod)
- Memory per build
- Storage usage (Nix store)
- Network traffic

**Reliability:**
- Build success rate
- Pod crash rate
- CSI driver errors
- SSH fallback rate

### Grafana Dashboards

**Dashboard 1: Build System Overview**
- Build queue length
- Active build pods
- Build success/failure rate
- Average build duration

**Dashboard 2: nix-csi Performance**
- CSI mount operations
- Volume creation time
- Driver error rate
- Package cache hit rate

**Dashboard 3: Resource Utilization**
- Build pod CPU usage
- Build pod memory usage
- Nix store size per node
- Binary cache hit rate

### Alerts

```yaml
# Prometheus alerts
groups:
- name: nix-csi-alerts
  rules:
  - alert: NixCSIDriverDown
    expr: up{job="nix-csi"} == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "nix-csi driver is down"

  - alert: BuildQueueBacklog
    expr: redis_queue_length{queue="builds"} > 100
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Build queue backlog detected"

  - alert: BuildFailureRate
    expr: rate(build_failures_total[5m]) > 0.1
    for: 15m
    labels:
      severity: warning
    annotations:
      summary: "High build failure rate"
```

---

## Part 12: Documentation Updates

### Files to Update

1. **CLAUDE.md**
   - Add nix-csi workflow
   - Update build instructions
   - Document pod patterns

2. **ROADMAP.md**
   - Add nix-csi migration phase
   - Update progress tracking

3. **modules/system/distributed-builds.nix**
   - Add nix-csi option
   - Document migration path

4. **New: docs/kubernetes/nix-csi-operations.md**
   - Runbook for nix-csi operations
   - Troubleshooting guide
   - Emergency procedures

5. **New: kubernetes-manifests/build/**
   - Build queue manifests
   - Build controller configs
   - Worker templates

---

## Part 13: Training & Knowledge Transfer

### Team Training Topics

**For Developers:**
- How to use dev pods with nix-csi
- Updated CI/CD workflows
- Debugging Nix packages in pods

**For Ops:**
- nix-csi driver management
- Build system monitoring
- Rollback procedures

**For Platform:**
- Architecture changes
- Security model (RBAC vs SSH)
- Cost optimization strategies

### Documentation Needs

- User guide: "Using Nix packages in your pods"
- Operator guide: "Managing the nix-csi build system"
- Architecture doc: "How nix-csi works internally"

---

## Part 14: Success Criteria

### Phase 1 (Coexistence)

- ✅ nix-csi deployed without breaking existing builds
- ✅ Test namespace functional
- ✅ No regression in build times

### Phase 2 (Workload Migration)

- ✅ 50% of workloads using nix-csi
- ✅ Gateway successfully migrated
- ✅ CI/CD pipelines operational
- ✅ Developer adoption > 70%

### Phase 3 (Build Infrastructure)

- ✅ Build queue operational
- ✅ Auto-scaling functional
- ✅ Build performance ≥ SSH builders
- ✅ Cost savings evident

### Phase 4 (Complete Migration)

- ✅ 95% of workloads using nix-csi
- ✅ SSH builders deprecated
- ✅ Documentation complete
- ✅ Team trained

---

## Part 15: Timeline Summary

| Phase | Duration | Risk | Effort | Value |
|-------|----------|------|--------|-------|
| **Phase 1: Coexistence** | 4 weeks | Low | Low | Foundation |
| **Phase 2: Workload Migration** | 8 weeks | Medium | Medium | High |
| **Phase 3: Build Infrastructure** | 8 weeks | Medium | High | Very High |
| **Phase 4: Complete Migration** | 4 weeks | High | Low | Cleanup |

**Total: 24 weeks (6 months)**

---

## Part 16: Decision Matrix

| Factor | SSH Builders | nix-csi | Recommendation |
|--------|-------------|---------|----------------|
| **Setup complexity** | Low | Medium | Start with SSH, add nix-csi |
| **Scalability** | Manual | Auto | **nix-csi wins** |
| **K8s integration** | Poor | Excellent | **nix-csi wins** |
| **Operational overhead** | Low | Medium | SSH for simple cases |
| **Build performance** | Good | Good | Tie |
| **Team familiarity** | High | Low | Training needed |
| **Cost efficiency** | Low | High | **nix-csi wins** |

**Verdict:** Hybrid approach
- **Keep SSH** for simple builds, low-volume workloads
- **Use nix-csi** for elastic K8s workloads, CI/CD, dev environments

---

## Part 17: Hybrid Architecture (Recommended)

```
┌─────────────────────────────────────────────────────┐
│ Build Request Router                               │
│  - Simple builds → SSH builders                    │
│  - K8s workloads → nix-csi build pods              │
│  - CI/CD → nix-csi                                 │
└─────────────────────────────────────────────────────┘
         │                          │
         │ SSH                      │ nix-csi
         ▼                          ▼
┌──────────────────┐    ┌─────────────────────┐
│ SSH Builders     │    │ nix-csi Build Pods │
│ (nexus, forge,   │    │ (Elastic, scalable)  │
│  sentry)         │    │                     │
└──────────────────┘    └─────────────────────┘
```

**Benefits of Hybrid:**
- Best of both worlds
- Gradual migration path
- Risk mitigation
- Cost optimization

---

## Part 18: Next Actions (Immediate)

### This Week

1. **Explore nix-csi**
   ```bash
   # Clone and test locally
   git clone https://github.com/Lillecarl/nix-csi.git /tmp/nix-csi
   cd /tmp/nix-csi
   nix run .#deploy-kubernetes
   ```

2. **Create test namespace**
   ```bash
   kubectl create namespace nix-csi-test
   ```

3. **Deploy test pod**
   ```yaml
   # test-nix-csi.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: test-nix-csi
     namespace: nix-csi-test
   spec:
     containers:
     - name: test
       image: alpine:latest
       command: ["sh"]
       args: ["-c", "ls -la /nix && echo 'Success!'"]
       volumeMounts:
       - name: nix-hello
         mountPath: /nix
     volumes:
     - name: nix-hello
       csi:
         driver: nix-csi
         volumeAttributes:
           flakeRef: github:nixos/nixpkgs/nixos-unstable#hello
   ```

4. **Document findings**
   - Create `docs/kubernetes/nix-csi-test-results.md`
   - Record performance, issues, lessons learned

### This Month

1. **Proof of Concept**
   - Migrate one non-critical service
   - Measure performance
   - Document process

2. **Team Review**
   - Present migration plan
   - Get feedback
   - Adjust timeline

3. **Decision Point**
   - Proceed with full migration?
   - Stay with hybrid?
   - Abandon nix-csi?

---

## Summary

**Migrating to nix-csi** means transforming from SSH-based distributed builds to Kubernetes-native Nix integration. The migration is **medium-risk, high-value** and should be done **gradually over 6 months**.

**Key Benefits:**
- Elastic build scaling
- K8s-native workflows
- No SSH key management
- Better resource utilization
- Nix packages without Nix in containers

**Recommended Approach:**
- **Phase 1:** Deploy nix-csi alongside SSH (coexistence)
- **Phase 2:** Migrate workloads gradually
- **Phase 3:** Build K8s-native build system
- **Phase 4:** Complete migration (or stay hybrid)

**Critical Success Factors:**
- Comprehensive testing at each phase
- Clear rollback procedures
- Team training and documentation
- Performance monitoring and optimization

**Next Step:** Try nix-csi in test namespace, validate assumptions, then decide on full migration.

---

**Document Version:** 1.0
**Last Updated:** 2026-03-23
**Status:** Strategic Planning
**Related:** nix-oci exploration, nix-csi exploration, distributed-builds.nix
