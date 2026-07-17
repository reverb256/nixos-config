# nix-oci and Nix Build Pods: Exploration Guide

**Created:** 2026-03-23
**Status:** Exploratory Research
**Related:** Distributed builds, Kubernetes integration, OCI images

---

## Executive Summary

**nix-oci** is a set of tools for building OCI container images using Nix's reproducible build system. "Nix build pods" refers to running Nix daemon builds inside Kubernetes pods instead of traditional SSH remote hosts.

**Current State:** You're using SSH-based distributed builds to nexus, forge, sentry. No Nix pods running in Kubernetes yet.

---

## Part 1: What is nix-oci?

### Overview

nix-oci bridges two ecosystems:
- **Nix:** Reproducible, declarative package management
- **OCI:** Open Container Initiative (Docker, Podman) runtime format

### Key Projects

| Project | Stars | Purpose | Backend |
|---------|-------|---------|---------|
| **Dauliac/nix-oci** | 89 | flake-parts module for OCI repo management | nix2container |
| **NotAShelf/nix-oci** | 1 | Build OCI images from NixOS rootfs | rootfs derivations |
| **shikanime-studio/nix-containers** | 0 | Build OCI from Nix flakes | Custom |
| **nix2oci** | - | Direct Nix → OCI conversion | CLI tool |

### Core Concepts

#### 1. Declarative Container Images

Instead of Dockerfiles:
```dockerfile
# Traditional Dockerfile
FROM alpine:3.19
RUN apk add --no-cache python3 curl
CMD ["python3"]
```

With nix-oci:
```nix
# Declarative Nix
{
  packages = with pkgs; [ python3 curl ];
  entrypoint = "${pkgs.python3}/bin/python3";
}
```

#### 2. nix2container Backend

**nix2container** is the underlying technology:
- Converts Nix store paths to OCI layers
- Creates reproducible image manifests
- Supports Docker/Podman registries

```bash
# Example workflow
nix build .#myImage
# Result: OCI-compliant tarball in /nix/store/...
```

#### 3. Key Features

From **Dauliac/nix-oci**:

- **Debug-friendly variants:** Add `curl`, `bash` with infinite sleep for troubleshooting
- **Monorepo support:** Share Nix store packages across multiple containers
- **Minimalistic containers:** Single-binary images, non-root by default
- **Accelerated builds:** Leverage Nix store to avoid redundant layer storage
- **Docker/Podman compatible:** Works with existing container tools

---

## Part 2: What are "Nix Build Pods"?

### Traditional Distributed Builds (Your Current Setup)

**File:** `/etc/nix/machines`
```
ssh-ng://j_kro@nexus x86_64-linux /etc/nixos/ssh/id_ed25519 6 5 big-parallel
ssh-ng://j_kro@forge x86_64-linux /etc/nixos/ssh/id_ed25519 1 2 big-parallel
ssh-ng://j_kro@sentry x86_64-linux /etc/nixos/ssh/id_ed25519 4 3 big-parallel
```

**How it works:**
1. Local Nix daemon reads `/etc/nix/machines`
2. SSH connects to remote hosts
3. Remote `nix-daemon` builds derivations
4. Results shipped back via SSH

**Limitations:**
- Requires SSH access and keys
- Remote hosts must be configured
- Scaling requires manual SSH setup
- No resource isolation or scheduling

### Kubernetes Build Pods (The Concept)

**Idea:** Run `nix-daemon` inside Kubernetes pods instead of SSH hosts

**Benefits:**
- **Elastic scaling:** Autoscale based on build queue
- **Resource isolation:** CPU/memory limits per pod
- **Scheduling:** Use Kubernetes scheduler for placement
- **No SSH keys:** Use Kubernetes service accounts
- **GPU support:** Build CUDA packages on GPU nodes
- **Storage integration:** Use PVCs for Nix store

**Architecture:**
```
┌─────────────┐
│ Local Nix   │
│ Daemon      │
└──────┬──────┘
       │
       │ kubectl exec? (TBD)
       │
┌──────▼──────────────────────┐
│  Kubernetes Service         │
│  nix-builder-service        │
└──────┬──────────────────────┘
       │
       ├─────────────────┬──────────────┐
       │                 │              │
┌──────▼──────┐   ┌─────▼─────┐   ┌───▼────────┐
│ nix-builder-│   │ nix-builder│   │ nix-builder│
│ pod-1       │   │ pod-2      │   │ pod-N      │
│ (CPU: 4)    │   │ (CPU: 2)   │   │ (GPU: 1)   │
└─────────────┘   └───────────┘   └────────────┘
```

### Implementation Challenges

**1. Protocol Translation**
- Nix speaks SSH to remote builders
- Need Kubernetes-aware protocol or SSH-over-k8s
- **Option:** Use `kubectl exec` to run builds
- **Option:** HTTP/gRPC API wrapper for nix-daemon

**2. Nix Store Persistence**
- Nix store must be shared or accessible
- **Option:** PVC per pod (slow, wasteful)
- **Option:** NFS-mounted `/nix/store` (better)
- **Option:** Distributed binary cache (fastest)

**3. Network Topology**
- Pods need to receive build instructions
- Results need to be shipped back
- **Option:** Build queue system (Redis, NATS)
- **Option:** Direct socket connection

---

## Part 3: Current Tools in Nixpkgs

### Container Build Tools

| Tool | Purpose | Use Case |
|------|---------|----------|
| **kaniko** | Build Dockerfiles in K8s | Not Nix-aware |
| **argo-workflows** | Container-native workflows | Could orchestrate Nix builds |
| **podman** | Podman CLI | Local testing |
| **cri-o** | Kubernetes CRI runtime | Underlying K8s container runtime |

### Missing Pieces

- **No native Nix → Kubernetes builder integration** in Nixpkgs
- **No standard protocol** for Nix → K8s pod communication
- **No reference implementation** of "build pods"

---

## Part 4: Potential Approaches

### Approach 1: SSH-over-Kubernetes (Lowest Effort)

**Concept:** Run SSH server in pods, keep existing Nix machinery

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nix-builder
spec:
  containers:
  - name: nix-daemon
    image: nixpkgs/nix-flake:latest
    command: ["nix-daemon"]
    volumeMounts:
    - name: nix-store
      mountPath: /nix/store
  volumes:
  - name: nix-store
    persistentVolumeClaim:
      claimName: nix-store-pvc
```

**Pros:**
- Works with existing `/etc/nix/machines`
- Minimal code changes
- Uses existing SSH key infrastructure

**Cons:**
- Still requires SSH keys
- Not "Kubernetes-native"

### Approach 2: HTTP/gRPC Wrapper (Most Clean)

**Concept:** Build HTTP API for nix-daemon, K8s service exposes it

```nix
# Hypothetical flake.nix
{
  nixBuilderService = {
    image = pkgs.nix-builder-api;
    replicas = 3;
    resources = {
      cpu = "4";
      memory = "8Gi";
    };
  };
}
```

**Pros:**
- Kubernetes-native
- No SSH keys needed
- Can use K8s service discovery

**Cons:**
- Requires building nix-daemon wrapper
- Protocol design needed
- Not standard in Nix community

### Approach 3: Argo Workflows Orchestration (Enterprise)

**Concept:** Use Argo Workflows to orchestrate Nix builds

```yaml
# argo-workflow.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: nix-build-workflow
spec:
  entrypoint: build-derivation
  templates:
  - name: build-derivation
    container:
      image: nixpkgs/nix-flake
      command: ["nix-build"]
      args: ["{{inputs.drvPath}}"]
```

**Pros:**
- Enterprise-grade orchestration
- Built-in retry, scheduling, resource management
- Already Kubernetes-native

**Cons:**
- Overkill for simple builds
- Learning curve
- Not integrated with `nix-daemon`

---

## Part 5: How nix-oci Connects to Build Pods

### Connection 1: Build Container Images in Pods

**Scenario:** You want to build container images using Nix, but build them in Kubernetes

```bash
# Local: Build OCI image with nix-oci
nix build .#myContainerImage

# Push to registry
skopeo copy nix:/path/to/result docker://registry/myimage:latest

# Deploy to Kubernetes
kubectl apply -f deployment.yaml
```

**With Build Pods:**
```bash
# Submit build job to Kubernetes
kubectl create -f nix-build-job.yaml

# Pod builds image, stores in PVC
# Sidecar pushes to registry when done
```

### Connection 2: Build NixOS System Images

**NotAShelf/nix-oci** approach:
1. Define NixOS configuration
2. Build rootfs derivation
3. Package as OCI image
4. Deploy to Kubernetes

**Use Case:** Run NixOS hosts as Kubernetes pods (unikernel-like)

---

## Part 6: Quick Start Guide

### Trying nix-oci (Dauliac's version)

```bash
# 1. Initialize new flake with nix-oci template
nix flake init -t github:Dauliac/nix-oci

# 2. Define a simple container
# Edit flake.nix to add packages
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    oci-images = {
      myapp = {
        packages = [pkgs.hello pkgs.bash];
        entrypoint = "${pkgs.hello}/bin/hello";
      };
    };
  };
}

# 3. Build the image
nix build .#oci-images.myapp

# 4. Load into Docker/Podman
docker load < result

# 5. Run it
docker run myapp:latest
```

### Setting Up Kubernetes Build Pods (Exploratory)

**Step 1: Create nix-daemon pod**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nix-builder-0
  labels:
    app: nix-builder
spec:
  containers:
  - name: nix-daemon
    image: nixpkgs/nix-flake:latest
    args: ["nix-daemon", "--keep-going"]
    resources:
      requests:
        cpu: "2"
        memory: "4Gi"
      limits:
        cpu: "4"
        memory: "8Gi"
    volumeMounts:
    - name: nix-store
      mountPath: /nix
  volumes:
  - name: nix-store
    emptyDir: {}
```

**Step 2: Expose via SSH (for existing Nix)**
```bash
# Port-forward SSH
kubectl port-forward pod/nix-builder-0 2222:22

# Update /etc/nix/machines
ssh-ng://root@localhost:2222 x86_64-linux - 4 4 big-parallel
```

**Step 3: Test distributed build**
```bash
nix-build -E 'with import <nixpkgs> {}; hello'
```

---

## Part 7: Recommendations

### For Your Cluster

**Current State Assessment:**
- ✅ Distributed builds working via SSH
- ✅ 3 remote builders (nexus, forge, sentry)
- ✅ Load balancing via machines file
- ❌ No Kubernetes integration
- ❌ Manual SSH key management

**Recommended Path Forward:**

1. **Short Term (Easy Wins)**
   - Try **nix-oci** for building container images
   - Build AI inference gateway images with Nix
   - Push to your private registry

2. **Medium Term (Exploration)**
   - Prototype **SSH-over-Kubernetes** build pod
   - Test with PVC-backed Nix store
   - Compare performance vs SSH builders

3. **Long Term (If Needed)**
   - Design HTTP/gRPC wrapper for nix-daemon
   - Contribute to Nix community if successful
   - Consider Argo Workflows for complex build pipelines

### When to Use Build Pods

**Use Cases:**
- **Elastic scaling:** Build surge during CI/CD
- **GPU builds:** CUDA packages need GPU access
- **Isolation:** Untrusted derivations in containers
- **Multi-tenant:** Different teams share cluster

**When to Stick with SSH:**
- **Stable infrastructure:** Fixed build farm
- **Low latency:** Direct SSH is faster
- **Simplicity:** Already working, why change?

---

## Part 8: Related Projects

### OCI Image Building
- **nix2container:** Backend library for OCI images
- **dockerTools:** Nixpkgs container builders
- **skopeo:** Copy images between registries

### Kubernetes + Nix
- **kubenix:** Generate Kubernetes manifests from Nix (not build pods)
- **helm2nix:** Convert Helm charts to Nix
- **terraform-nixos:** NixOS provisioning via Terraform

### CI/CD
- **hercules-ci:** Nix-based CI/CD (uses agents, not pods)
- **nix-build-remote:** Remote build orchestration
- **Cachix:** Binary cache hosting (not builds)

---

## Summary

**nix-oci** provides declarative, reproducible container image building using Nix. "Nix build pods" would move distributed Nix builds from SSH hosts to Kubernetes pods, enabling elastic scaling and better resource management.

**Key Takeaway:** nix-oci is production-ready for building images. Build pods are experimental and would require custom implementation or community contributions.

**Next Steps:**
1. Try `nix flake init -t github:Dauliac/nix-oci` locally
2. Build a simple container image
3. Prototype a single nix-daemon pod in Kubernetes
4. Test SSH-over-k8s vs existing SSH builders

---

**References:**
- Dauliac/nix-oci: https://github.com/Dauliac/nix-oci
- NotAShelf/nix-oci: https://github.com/NotAShelf/nix-oci
- nix2container: https://github.com/nlewo/nix2container
- Nix manual (distributed builds): https://nixos.org/manual/nix/stable/

**Document Version:** 1.0
**Last Updated:** 2026-03-23
