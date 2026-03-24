# nix-csi: Kubernetes CSI Driver for Nix

**Created:** 2026-03-23
**Project:** https://github.com/Lillecarl/nix-csi
**Stars:** 91 | **Forks:** 1
**Status:** Active (709 commits main, 947 develop)
**License:** [Check repository](https://github.com/Lillecarl/nix-csi/blob/main/LICENSE)

---

## Executive Summary

**nix-csi** is a Kubernetes CSI (Container Storage Interface) driver that mounts `/nix` into Kubernetes pods using ephemeral volumes. It enables pods to access Nix store paths directly without building them locally, solving the "how do pods access Nix packages?" problem for Nix-based workloads.

**Key Innovation:** Volumes share lifetime with pods (ephemeral), auto-cleanup when pod dies.

---

## Part 1: What Problem Does nix-csi Solve?

### The Challenge

**Problem:** How do Kubernetes pods access Nix packages?

**Traditional approaches:**
1. **Install Nix in pod image** → Bloated images, slow startup
2. **Mount host /nix via hostPath** → Not portable, security issues
3. **Build packages in pod** → Slow, defeats Nix's purpose
4. **Use binary cache** → Still needs Nix installed

**None are ideal** for cluster-wide Nix integration.

### The nix-csi Solution

**CSI Ephemeral Volumes** + **Nix integration**:
```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: myapp
    image: alpine:latest  # No Nix installed!
    volumeMounts:
    - name: nix-store
      mountPath: /nix
  volumes:
  - name: nix-store
    csi:
      driver: nix-csi
      volumeAttributes:
        flakeRef: github:nixos/nixpkgs/nixos-unstable#hello
```

**Result:** Pod has `/nix/store/hello-...` mounted automatically, even though base image has no Nix!

---

## Part 2: How nix-csi Works

### CSI Ephemeral Volumes

**What are CSI ephemeral volumes?**
- Kubernetes feature (beta in v1.23+)
- Volumes created when pod starts
- Volumes deleted when pod terminates
- No manual cleanup needed

**Why ephemeral?**
- Nix store paths are immutable
- No need to persist beyond pod lifetime
- Automatic garbage collection

### Architecture

```
┌─────────────────────────────────────────┐
│ Kubernetes Pod                          │
│                                         │
│  ┌──────────────┐                       │
│  │ Container    │                       │
│  │ Image: alpine│  (No Nix installed!) │
│  │              │                       │
│  └──────┬───────┘                       │
│         │                               │
│         │ mount /nix                    │
│         ▼                               │
│  ┌──────────────────┐                  │
│  │ CSI Ephemeral    │                  │
│  │ Volume           │                  │
│  └──────┬───────────┘                  │
└─────────┼───────────────────────────────┘
          │
          │ CSI: NodePublishVolume
          ▼
┌─────────────────────┐
│ nix-csi Driver      │
│ (runs on node)      │
│                     │
│ 1. Read attributes  │
│ 2. Build/fetch Nix  │
│ 3. Mount storePath  │
└─────────────────────┘
          │
          │ Uses Nix daemon
          ▼
┌─────────────────────┐
│ Host Nix Store      │
│ /nix/store/         │
└─────────────────────┘
```

### Volume Attributes (3 Priority Levels)

**Priority 1: Direct storePath** (fastest)
```yaml
volumeAttributes:
  x86_64-linux: /nix/store/hello-1.2.3-abc...
  aarch64-linux: /nix/store/hello-1.2.3-def...
```
- Just mount existing path
- No build needed
- Multi-arch support

**Priority 2: Flake reference** (convenient)
```yaml
volumeAttributes:
  flakeRef: github:nixos/nixpkgs/nixos-unstable#hello
```
- Builds from flake
- Uses host's Nix daemon
- Result cached for future pods

**Priority 3: Nix expression** (flexible)
```yaml
volumeAttributes:
  nixExpr: |
    let
      nixpkgs = builtins.fetchTree {
        type = "github";
        owner = "nixos";
        repo = "nixpkgs";
        ref = "nixos-unstable";
      };
      pkgs = import nixpkgs { };
    in
    pkgs.hello
```
- Full Nix expression
- Maximum flexibility
- Same caching as flakeRef

**Selection Logic:** First successful strategy wins (by priority)

---

## Part 3: Key Features

### Core Features (Main Branch)

1. **CSI Ephemeral Volume Support**
   - Volumes auto-created on pod start
   - Volumes auto-deleted on pod termination
   - No manual cleanup

2. **Multi-Architecture Support**
   - Specify different paths for x86_64, aarch64
   - Pod runs on correct node architecture
   - Perfect for heterogeneous clusters

3. **Nix Integration**
   - Uses host's Nix daemon for builds
   - Leverages host's Nix store
   - Binary cache friendly

4. **Flexible Attribute Sources**
   - Direct store paths
   - Flake references
   - Full Nix expressions

### Advanced Features (Develop Branch)

**1. NRI (Node Resource Interface) Plugin**
```
Mount /nix into Kubernetes pods using the CSI Ephemeral Volume feature and NRI plugin
```

**What is NRI?**
- Kubernetes Node Resource Interface
- Allows custom resource orchestration
- Can inject hooks into pod lifecycle
- More powerful than CSI alone

**Use Cases:**
- Automatic Nix package injection
- Dynamic volume attachment
- Resource-aware scheduling

**2. Enhanced Features (947 vs 709 commits)**
- More testing
- Bug fixes
- Performance improvements
- Better error handling

---

## Part 4: Installation & Usage

### Prerequisites

- Kubernetes v1.23+ (CSI ephemeral volumes beta)
- Nix installed on all nodes
- Host Nix daemon running
- kubectl access

### Installation (From Repository)

```bash
# 1. Clone repository
git clone https://github.com/Lillecarl/nix-csi.git
cd nix-csi

# 2. Deploy CSI driver (uses kubenix)
nix run .#deploy-kubernetes

# Or manually apply manifests
kubectl apply -f kubenix/deploy/
```

**What gets deployed:**
- CSI driver pod (DaemonSet, runs on each node)
- RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
- CSIDriver resource registration

### Verification

```bash
# Check CSI driver registered
kubectl get csidriver | grep nix

# Check driver pods running
kubectl get pods -n kube-system | grep nix-csi

# Check logs
kubectl logs -n kube-system -l app=nix-csi
```

---

## Part 5: Usage Examples

### Example 1: Simple Package Mount

**Scenario:** Pod needs `hello` package from Nix

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello-pod
spec:
  containers:
  - name: hello
    image: alpine:latest
    command: ["/nix/store/hello-.../bin/hello"]
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

**Result:** Pod can run `/nix/store/.../bin/hello` even though Alpine has no Nix!

### Example 2: Multi-Architecture

**Scenario:** Same pod spec, works on both x86_64 and ARM nodes

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    image: alpine:latest
    volumeMounts:
    - name: nix-store
      mountPath: /nix
  volumes:
  - name: nix-store
    csi:
      driver: nix-csi
      volumeAttributes:
        x86_64-linux: /nix/store/hello-x86-1.2.3
        aarch64-linux: /nix/store/hello-arm-1.2.3
```

**Result:** Pod runs on any node, correct arch package mounted!

### Example 3: Complex Nix Expression

**Scenario:** Custom package built in pod

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: builder
    image: alpine:latest
    volumeMounts:
    - name: nix-custom
      mountPath: /usr/local/bin
  volumes:
  - name: nix-custom
    csi:
      driver: nix-csi
      volumeAttributes:
        nixExpr: |
          let
            pkgs = import (builtins.fetchTarball {
              url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
            }) {};
          in
          pkgs.hello
```

### Example 4: Deployment with Nix Packages

**Scenario:** Web server with Nix-built binaries

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nix-web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nix-web
  template:
    metadata:
      labels:
        app: nix-web
    spec:
      containers:
      - name: web
        image: nginx:alpine
        volumeMounts:
        - name: nix-utils
          mountPath: /utils
        - name: nix-scripts
          mountPath: /scripts
      volumes:
      - name: nix-utils
        csi:
          driver: nix-csi
          volumeAttributes:
            flakeRef: github:nixos/nixpkgs/nixos-unstable#ripgrep
      - name: nix-scripts
        csi:
          driver: nix-csi
          volumeAttributes:
            nixExpr: |
              let pkgs = import <nixpkgs> {}; in
              pkgs.writeScript "my-script" ""
```

---

## Part 6: How This Connects to Build Pods

### The Missing Link

**Problem with Build Pods:** How do pods access Nix store to build derivations?

**Solution 1: SSH to host**
- ❌ Requires SSH keys
- ❌ Not Kubernetes-native
- ✅ Works with existing Nix

**Solution 2: PVC with /nix/store**
- ❌ Wasteful (separate copy per pod)
- ❌ Slow (network storage)
- ✅ Simple to understand

**Solution 3: nix-csi (Best!)**
- ✅ Uses host Nix store efficiently
- ✅ Ephemeral (auto-cleanup)
- ✅ Kubernetes-native
- ✅ No SSH keys needed
- ✅ Multi-arch support

### Build Pod Architecture with nix-csi

```
┌─────────────────────────────────────┐
│ Build Controller Pod                │
│ (Submits build jobs)                │
└──────────┬──────────────────────────┘
           │
           │ kubectl apply -f buildjob.yaml
           ▼
┌─────────────────────────────────────┐
│ Build Job Pod                       │
│                                     │
│  ┌──────────────┐                   │
│  │ nix-daemon   │  (Runs build)     │
│  └──────────────┘                   │
│             │                         │
│             │ needs /nix/store       │
│             ▼                         │
│  ┌──────────────────┐               │
│  │ nix-csi Volume   │  (Mounted via CSI)│
│  │ /nix             │               │
│  └──────────────────┘               │
└─────────────────────────────────────┘
           │
           │ CSI: NodePublishVolume
           ▼
┌─────────────────────────────────────┐
│ Host Node                           │
│  - nix-daemon running               │
│  - /nix/store shared                │
│  - nix-csi driver runs here         │
└─────────────────────────────────────┘
```

### Example Build Pod with nix-csi

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nix-builder
spec:
  containers:
  - name: builder
    image: nixpkgs/nix-flake:latest
    command: ["nix-build"]
    args: ["/path/to/derivation"]
    volumeMounts:
    - name: nix-store
      mountPath: /nix
    - name: build-cache
      mountPath: /build
  volumes:
  # Mount entire /nix/store via CSI
  - name: nix-store
    hostPath:
      path: /nix
      type: Directory

  # Build output cache
  - name: build-cache
    emptyDir: {}
```

**Better approach with nix-csi ephemeral:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nix-builder
spec:
  containers:
  - name: builder
    image: alpine:latest  # No Nix needed!
    command: ["sh"]
    args: ["-c", "ls -la /nix"]
    volumeMounts:
    - name: nix-package
      mountPath: /nix
  volumes:
  # nix-csi mounts just this package!
  - name: nix-package
    csi:
      driver: nix-csi
      volumeAttributes:
        flakeRef: .#myPackage
```

---

## Part 7: Advanced Topics

### Multi-Cluster Support

**Scenario:** Different Nix stores per cluster

```yaml
# Cluster A: Uses cache.nixos.org
volumeAttributes:
  flakeRef: github:myorg/mypkgs#package

# Cluster B: Uses private binary cache
volumeAttributes:
  flakeRef: github:myorg/mypkgs#package
  substituters: https://private-cache.example.com
```

### Security Considerations

**1. Host Path Access**
- nix-csi runs on nodes
- Has access to host's /nix/store
- Needs privileged access (CSI requirement)

**2. RBAC**
```yaml
# CSI driver needs these permissions
- resource: "csidrivers"
  verbs: ["get", "list", "watch"]
- resource: "csinodeinfo"
  verbs: ["get", "list", "watch"]
- resource: "persistentvolumes"
  verbs: ["get", "list", "watch", "create", "delete"]
```

**3. Pod Security**
- Pods can read any Nix store path
- Consider using `readOnly: true` in volumeMount
- No write access to /nix/store (immutable)

### Performance Optimization

**1. Binary Cache Integration**
```yaml
# Host's nix.conf has binary cache
# nix-csi leverages this automatically
substituters = https://cache.nixos.org https://my-cache.example.com
```

**2. Store Path Pre-warming**
```bash
# Pre-build common packages on nodes
nix-build /nix/store/...-hello.drv
nix-build /nix/store/...-ripgrep.drv
```

**3. Shared Store (Optional)**
```bash
# NFS-mounted /nix/store across nodes
# All nodes share same cache
mount /nix nfs:nfs-server:/nix/store
```

---

## Part 8: Comparison with Alternatives

| Feature | nix-csi | hostPath | PVC | Inline build |
|---------|---------|----------|-----|--------------|
| **Cleanup** | ✅ Auto | ❌ Manual | ❌ Manual | ✅ Auto |
| **Multi-arch** | ✅ Yes | ❌ No | ❌ No | ✅ Yes |
| **Storage efficiency** | ✅ Shared | ✅ Shared | ❌ Duplicated | ✅ Shared |
| **K8s-native** | ✅ Yes | ❌ No | ✅ Yes | ❌ No |
| **Setup complexity** | 🟡 Medium | 🟢 Low | 🟢 Low | 🔴 High |
| **Portability** | ✅ Yes | ❌ No | ✅ Yes | ✅ Yes |
| **Performance** | ✅ Fast | ✅ Fast | 🟡 Medium | ❌ Slow |

---

## Part 9: Troubleshooting

### Issue: Pod stuck in ContainerCreating

**Symptoms:**
```bash
kubectl get pods
NAME           READY   STATUS              RESTARTS   AGE
my-pod         0/1     ContainerCreating   0          5m
```

**Diagnosis:**
```bash
kubectl describe pod my-pod
# Look for:
# - FailedMount: failed to resolve volume
# - CSI driver not responding
```

**Fixes:**
1. Check nix-csi pods running:
   ```bash
   kubectl get pods -n kube-system | grep nix-csi
   ```

2. Check CSI driver registered:
   ```bash
   kubectl get csidriver
   ```

3. Check logs:
   ```bash
   kubectl logs -n kube-system -l app=nix-csi
   ```

### Issue: Package not found

**Symptoms:**
```bash
kubectl logs my-pod
# Error: /nix/store/hello-... not found
```

**Fixes:**
1. Build package on host first:
   ```bash
   nix-build '<nixpkgs>' -A hello
   ```

2. Check flake reference correct:
   ```bash
   nix flake show github:nixos/nixpkgs/nixos-unstable#hello
   ```

3. Check Nix expression evaluates:
   ```bash
   nix eval --expr '<nixpkgs>.hello'
   ```

### Issue: Multi-arch mismatch

**Symptoms:**
```bash
kubectl logs my-pod
# Error: wrong architecture for package
```

**Fixes:**
1. Specify both architectures:
   ```yaml
   volumeAttributes:
     x86_64-linux: /nix/store/hello-x86-...
     aarch64-linux: /nix/store/hello-arm-...
   ```

2. Use nodeSelector:
   ```yaml
   spec:
     nodeSelector:
       kubernetes.io/arch: amd64
   ```

---

## Part 10: Real-World Use Cases

### Use Case 1: CI/CD Pipeline

**Scenario:** Run tests in K8s using Nix-built tools

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-runner
spec:
  containers:
  - name: tests
    image: alpine:latest
    command: ["/utils/pytest"]
    args: ["/tests/"]
    volumeMounts:
    - name: nix-test-tools
      mountPath: /utils
    - name: test-code
      mountPath: /tests
  volumes:
  - name: nix-test-tools
    csi:
      driver: nix-csi
      volumeAttributes:
        nixExpr: |
          let pkgs = import <nixpkgs> {}; in
          pkgs.symlinkJoin {
            name = "test-tools";
            paths = [pkgs.pytest pkgs.python3];
          }
  - name: test-code
    configMap:
      name: test-code
```

### Use Case 2: AI/ML Workloads

**Scenario:** PyTorch with specific CUDA version

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ml-training
spec:
  containers:
  - name: trainer
    image: python:3.11-slim
    command: ["python"]
    args: ["train.py"]
    volumeMounts:
    - name: nix-pytorch
      mountPath: /opt/pytorch
    - name: dataset
      mountPath: /data
  volumes:
  - name: nix-pytorch
    csi:
      driver: nix-csi
      volumeAttributes:
        flakeRef: github:NixOS/nixpkgs/nixos-unstable#python311Packages.pytorch
        # CUDA-specific version
        x86_64-linux: /nix/store/pytorch-cuda-12.0.0-...
  - name: dataset
    persistentVolumeClaim:
      claimName: ml-dataset
```

### Use Case 3: Development Environment

**Scenario:** Dev pod with complete Nix toolchain

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dev-environment
spec:
  containers:
  - name: dev
    image: alpine:latest
    command: ["sleep"]
    args: ["infinity"]
    volumeMounts:
    - name: nix-dev
      mountPath: /dev-tools
  volumes:
  - name: nix-dev
    csi:
      driver: nix-csi
      volumeAttributes:
        nixExpr: |
          let
            pkgs = import <nixpkgs> {};
          in
          pkgs.symlinkJoin {
            name = "dev-tools";
            paths = with pkgs; [
              vim git go nodejs python3
              ripgrep fd jq
            ];
          }
```

---

## Part 11: Comparison: Main vs Develop Branch

| Feature | Main Branch | Develop Branch |
|---------|-------------|----------------|
| **Commits** | 709 | 947 (+33%) |
| **CSI Support** | ✅ Yes | ✅ Yes |
| **NRI Plugin** | ❌ No | ✅ Yes |
| **Testing** | Basic | Enhanced |
| **Documentation** | ✅ README | ✅ Expanded |
| **Stability** | ✅ Stable | 🟡 Experimental |
| **Features** | Core | Advanced |

**Recommendation:** Use **main branch** for production, **develop branch** for testing new features (especially NRI).

---

## Part 12: Integration with Your Cluster

### Current Storage Classes

You have:
- `fast-local-ssd` (rancher.io/local-path)
- `slow-hdd` (rancher.io/local-path)
- `akash-provider-local-storage` (rancher.io/local-path)

### nix-csi Integration Plan

**Step 1: Deploy nix-csi**
```bash
# Clone repo
git clone https://github.com/Lillecarl/nix-csi.git /tmp/nix-csi
cd /tmp/nix-csi

# Deploy to cluster
kubectl apply -f kubenix/deploy/
```

**Step 2: Test with simple pod**
```yaml
# test-nix-csi.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-nix-csi
spec:
  containers:
  - name: test
    image: alpine:latest
    command: ["sh"]
    args: ["-c", "ls -la /nix && echo 'Nix CSI works!'"]
    volumeMounts:
    - name: nix-test
      mountPath: /nix
  volumes:
  - name: nix-test
    csi:
      driver: nix-csi
      volumeAttributes:
        flakeRef: github:nixos/nixpkgs/nixos-unstable#hello
```

**Step 3: Verify**
```bash
kubectl apply -f test-nix-csi.yaml
kubectl logs test-nix-csi
kubectl delete pod test-nix-csi
```

**Step 4: Integrate with build pods**
- Use nix-csi to mount Nix store into builder pods
- No need for full /nix mount, just required packages
- Ephemeral volumes auto-cleanup when build finishes

---

## Part 13: Recommendations

### For Your Cluster Use Case

**Current Situation:**
- ✅ Distributed builds via SSH (nexus, forge, sentry)
- ✅ Local-path storage classes
- ✅ Kubernetes v1.35.0 (supports CSI ephemeral volumes)
- ❌ No Nix integration in K8s workloads

**Recommended Approach:**

1. **Phase 1: Deploy nix-csi (Low Risk)**
   - Deploy to test namespace first
   - Verify with simple pods
   - Test CSI ephemeral volumes

2. **Phase 2: Integrate with AI Inference (Medium Value)**
   - Use nix-csi for gateway packages
   - No need to rebuild container images
   - Ephemeral package mounting

3. **Phase 3: Build Pod Prototype (High Value)**
   - Create builder pod template
   - Use nix-csi for /nix/store access
   - Compare performance vs SSH builders

4. **Phase 4: Production Evaluation (If Successful)**
   - Benchmark: SSH vs nix-csi vs PVC
   - Evaluate: complexity vs benefit
   - Decide: hybrid approach or full migration?

### When to Use nix-csi

**Use Cases:**
- ✅ Pods need specific Nix packages (not full /nix)
- ✅ Ephemeral workloads (CI/CD, jobs)
- ✅ Multi-arch clusters
- ✅ Frequent package updates

**When NOT to Use:**
- ❌ Pods need full /nix (use hostPath or PVC)
- ❌ Long-running services (use container images)
- ❌ Simple SSH setup already works

---

## Part 14: Limitations & Future Work

### Current Limitations

1. **Read-Only Access**
   - Pods can't write to /nix/store
   - Intentional (store is immutable)

2. **Host Nix Dependency**
   - Requires Nix on all nodes
   - No remote store support yet

3. **Build Latency**
   - First build: fetch from binary cache
   - Subsequent: instant (cached)

4. **CSI Ephemeral Beta**
   - Feature is beta in K8s v1.23+
   - May change in future versions

### Future Enhancements (Possible)

1. **Remote Store Support**
   - Mount from remote Nix store
   - No Nix needed on nodes
   - Better for multi-cluster

2. **Writable Volumes**
   - Allow builds in pods
   - Isolated build environments
   - Security trade-offs

3. **Build-in Binary Cache**
   - CSI driver caches packages
   - Faster pod startup
   - Less load on host Nix

4. **Garbage Collection**
   - Auto-remove unused packages
   - Store size management
   - Configurable retention policies

---

## Summary

**nix-csi** enables Kubernetes pods to access Nix packages via CSI ephemeral volumes. It's the missing link for running Nix-based workloads in Kubernetes without bloating container images or requiring SSH.

**Key Benefits:**
- Ephemeral volumes (auto-cleanup)
- Multi-architecture support
- Kubernetes-native
- No Nix installation in pods
- Flexible attribute sources (path/flake/expression)

**For Your Cluster:**
- Perfect for AI inference gateway packages
- Enables Nix-based build pods
- Low-risk deployment (CSI driver only)
- High value for Nix/K8s integration

**Next Steps:**
1. Try test deployment in non-production namespace
2. Evaluate build pod prototype
3. Compare with existing SSH builders
4. Decide on hybrid or full migration

---

**References:**
- Repository: https://github.com/Lillecarl/nix-csi
- CSI Spec: https://kubernetes-csi.github.io/docs/
- CSI Ephemeral Volumes: https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/
- Nix Manual: https://nixos.org/manual/nix/stable/

**Related Documents:**
- `docs/kubernetes/nix-oci-and-build-pods-exploration.md` (nix-oci + build pods)
- `modules/system/distributed-builds.nix` (your current SSH setup)
- `ROADMAP.md` (Kubernetes migration progress)

**Document Version:** 1.0
**Last Updated:** 2026-03-23
**Status:** Exploratory Research
