# Nix Pods in Kubernetes - Analysis & Approaches

**Date:** 2026-03-13 | **Cluster:** NixOS 4-node K8s v1.35.0

---

## Executive Summary

| Approach | Best For | Complexity | K8s Native |
|----------|----------|------------|------------|
| **Nixery** | Ad-hoc build jobs, CI/CD | Low | ✅ Yes |
| **Custom Nix-built Images** | Production services | Medium | ✅ Yes |
| **nixos-container** | System containers | High | ⚠️ Requires privileged |
| **Arion** | Multi-container NixOS setups | High | ❌ No (separate orchestrator) |

---

## 1. Nixery - On-Demand Container Registry

### What is Nixery?

Nixery is an ad-hoc container registry that builds images on-the-fly from Nix packages.

**URL:** `https://nixery.dev`

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  nixery.dev/shell/git/htop/tmux                             │
│     │       │    │    │                                     │
│     │       │    │    └─ Package: tmux                      │
│     │       │    └────── Package: htop                      │
│     │       └─────────── Package: git                       │
│     └─────────────────── Meta-package: shell (bash+coreutils) │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │  Nix builds image on     │
              │  first request, caches   │
              │  subsequent pulls        │
              └─────────────────────────┘
```

### Meta-Packages

| Meta-package | Includes |
|--------------|----------|
| `shell` | bash, coreutils, findutils, utillinux, procps |
| `toolchain` | gcc, clang, cmake, ninja, meson |
| `arm64` | ARM64 binaries (multi-arch) |

### Kubernetes Examples

```yaml
# One-off build job
apiVersion: batch/v1
kind: Job
metadata:
  name: nix-build
spec:
  template:
    spec:
      containers:
      - name: builder
        image: nixery.dev/shell/git/ninja/meson
        command: ["bash"]
        args: ["-c", "git clone ... && meson setup build"]
      restartPolicy: OnFailure
```

### Advantages

- **Declarative by URL** - The image spec IS the package list
- **Reproducible** - Same packages = same image hash
- **Minimal** - Only includes what you specify
- **No Dockerfile** - URL defines the image
- **Cached** - Subsequent pulls are fast

### Limitations

- **First pull is slow** - Must build the image
- **No custom configuration** - Can't add arbitrary files
- **Registry dependency** - Requires nixery.dev availability
- **Single layer** - Not optimized for partial updates

### For Your Cluster

```yaml
# k8s/jobs/nixery-build.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: nix-build-worker
  namespace: build-jobs
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: zephyr  # Build on workstation
      containers:
      - name: builder
        # Complete C/C++ build environment from Nix
        image: nixery.dev/toolchain/git/ninja/ cmake/ ccache
        command: ["bash"]
        args: ["-c", "echo 'Ready for Nix builds!' && sleep 3600"]
        resources:
          requests:
            memory: "1Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "4000m"
        volumeMounts:
        - name: workspace
          mountPath: /workspace
      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: build-workspace
      restartPolicy: Never
```

---

## 2. Custom Nix-Built Images

### Building Images Declaratively

```nix
# images/myapp/image.nix
{ pkgs, ... }:
pkgs.dockerTools.buildLayeredImage {
  name = "myapp";
  tag = "latest";
  config.Cmd = [ "/bin/myapp" ];
  layers = [
    # Base layer with runtime dependencies
    (pkgs.dockerTools.layerDependencies {
      layers = map (p: p.override { inherit pname; })
        [ pkgs.glibc pkgs.zlib ];
    })

    # Application layer
    (pkgs.dockerTools.buildLayer {
      deps = [ pkgs.myapp ];
      proot = true;
    })
  ];
}
```

### Flake-Based Image Building

```nix
# flake.nix
{
  outputs = { self, nixpkgs, ... }: {
    packages.x86_64-linux = {
      # OCI image
      default = nixpkgs.ociImage {
        name = "my-service";
        tag = "v1.0";
        config = {
          Cmd = [ "/bin/my-service" ];
          WorkingDir = "/app";
          ExposedPorts = { "8080/tcp" = {}; };
        };
        copyToRoot = pkgs.runCommand "my-service-root" {
          buildInputs = with pkgs; [ coreutils my-service ];
          command = ''
            mkdir -p $out/bin $out/app
            ln -s ${pkgs.my-service}/bin/my-service $out/bin/
            cp -r ${pkgs.my-service}/share/* $out/app/
          '';
        };
      };
    };
  };
}
```

### Building and Pushing

```bash
# Build the image
nix build .#packages.x86_64-linux.default

# Load into Podman
podman load -i result

# Tag and push to local registry
podman tag localhost/my-service:v1 registry.cluster.local/my-service:v1
podman push registry.cluster.local/my-service:v1
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-service
  template:
    metadata:
      labels:
        app: my-service
    spec:
      containers:
      - name: my-service
        image: registry.cluster.local/my-service:v1
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
```

---

## 3. nixos-container - System Containers

### What It Is

Lightweight NixOS containers that run systemd inside, created via:

```nix
# containers.mycontainer = {
#   config = { config, pkgs, ... }: {
#     environment.systemPackages = [ pkgs.git pkgs.vim ];
#     services.openssh.enable = true;
#   };
# };
```

### Limitations for Kubernetes

| Issue | Impact | Workaround |
|-------|--------|------------|
| Requires systemd | K8s expects PID 1 to be the app | Use privileged mode |
| Shared kernel namespaces | Conflicts with K8s pod model | Use separate VMs |
| Not OCI-compliant | Requires conversion | Build custom images |

### When to Use

- **Pre-K8s:** On individual hosts via libvirt or systemd-nspawn
- **Build environments:** `nixos-rebuild build` in containers
- **Testing:** Test NixOS configs without rebuilding host

### NOT Recommended for Your Kubernetes Migration

The systemd requirement conflicts with Kubernetes' pod model. Consider **Nixery** or **custom images** instead.

---

## 4. Arion - Declarative Multi-Container

### What It Is

Arion is a NixOS-based container orchestrator, successor to GNU Habitat.

```nix
# arion-compose.nix
{ pkgs, lib, ... }: {
  config = {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      settings = {
        log_connections = true;
        port = 5432;
      };
    };

    services.redis = {
      enable = true;
      settings = {
        bind = "0.0.0.0";
        port = 6379;
      };
    };
  };
}
```

### Arion vs Kubernetes

| Feature | Arion | Kubernetes |
|---------|-------|------------|
| Scope | Single host | Multi-node cluster |
| Service discovery | mDNS | CoreDNS |
| Load balancing | Built-in | Service/Ingress |
| GPU support | Manual | Device plugins |
| Ecosystem | Growing | Mature |

### Recommendation

**Don't use Arion alongside Kubernetes.** Choose one:
- **Kubernetes** for multi-node, production workloads
- **Arion** for single-host, declarative multi-container setups

---

## 5. Recommended Strategy for Your Cluster

### Phase 1: Use Nixery for CI/CD (Immediate)

```yaml
# k8s/ci/nix-builder.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: nix-builder
  namespace: ci
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: zephyr
      containers:
      - name: builder
        # Complete build environment
        image: nixery.dev/toolchain/git/ ninja/ cmake/ nodejs_22/ python312
        command: ["bash"]
        workingDir: /workspace
      restartPolicy: OnFailure
```

### Phase 2: Build Custom Images for Production Services

```nix
# images/ai-inference/image.nix
{ pkgs, ... }:
pkgs.dockerTools.buildLayeredImage {
  name = "ai-inference";
  tag = "v1.0";

  includedPackages = with pkgs; [
    python312
    python312Packages.torch
    python312Packages.transformers
    cudaPackages_12.cudatoolkit
  ];

  config = {
    Cmd = [ "python3", "-m", "inference_server"];
    Env = [
      "PYTHONPATH=/app"
      "CUDA_VISIBLE_DEVICES=0"
    ];
  };
}
```

### Phase 3: NixOS-Based K8s Nodes (Already Done)

Your cluster is already running NixOS on all nodes. This means:
- K8s itself runs on NixOS
- You can use Nix to configure K8s components
- System packages are managed declaratively

```nix
# Already in your cluster
services.kubernetes = {
  enable = true;
  roles = ["master" "node"];
  flannel.enable = true;
};
```

---

## 6. Example: Migrating a Service to Nix-Based Image

### Before (Docker Hub)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: glitchtip
spec:
  template:
    spec:
      containers:
      - name: web
        image: glitchtip/glitchtip:latest  # ❌ External registry
```

### After (Nix-Built)

```nix
# images/glitchtp/default.nix
{ pkgs, ... }:
pkgs.dockerTools.buildLayeredImage {
  name = "glitchtip";
  tag = "v4.0.0";

  includedPackages = with pkgs; [
    python312
    python312Packages.django
    python312Packages.celery
    python312Packages.psycopg2
  ];

  config = {
    Cmd = [ "gunicorn", "glitchtip.config.wsgi"];
    WorkingDir = "/app";
  };
}
```

```bash
# Build and deploy
nix build .#packages.x86_64-linux.glitchtip
podman load -i result
podman push registry.cluster.local/glitchtip:v4.0.0
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: glitchtip
spec:
  template:
    spec:
      containers:
      - name: web
        image: registry.cluster.local/glitchtip:v4.0.0  # ✅ Built by Nix
```

---

## 7. Comparison Matrix

| Approach | Image Build Time | Image Size | Reproducibility | Update Mechanism |
|----------|------------------|------------|-----------------|-------------------|
| **Nixery** | First: slow, Cached: instant | Minimal | ✅ Perfect | nixpkgs channel update |
| **Custom Nix image** | Medium (local build) | Optimized | ✅ Perfect | `nixos-rebuild switch` |
| **Docker Hub** | Pre-built | Variable | ⚠️ Variable | Manual rebuild |

---

## 8. Next Steps

### Immediate (Week 1)

1. **Test Nixery with a simple pod:**
   ```bash
   kubectl run nix-test --image=nixery.dev/shell/htop --command=htop --restart=Never
   ```

2. **Create a Nixery-based CI job template** in `k8s/jobs/`

### Short-term (Weeks 2-3)

1. **Create image definitions** for critical services
2. **Set up local registry** (if not already available)
3. **Build pipeline integration** with `nix build`

### Long-term (Months 2-3)

1. **Migrate all custom services** to Nix-built images
2. **Implement image update automation** via flake updates
3. **Document image provenance** (Nix store hashes)

---

## 9. References

- **Nixery:** https://nixery.dev
- **NixOS Containers:** https://nixos.org/manual/nixos/stable/#sec-containers
- **DockerTools in Nixpkgs:** https://search.nixos.org/options?query=dockerTools
- **Arion:** https://github.com/hercules-ci/arion

---

**Status:** Ready for implementation | **Priority:** Medium
