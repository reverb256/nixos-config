# nix-csi Integration

## What is nix-csi?

nix-csi is a Kubernetes CSI (Container Storage Interface) driver that mounts
Nix store paths directly into pods using ephemeral inline volumes. It
eliminates the need to build container images for internal workloads.

**Upstream:** https://github.com/Lillecarl/nix-csi
**License:** GPL-2.0
**CSI Driver Name:** `nix.csi.store`

## How It Works

```
Traditional:  nix build -> dockerTools.buildImage -> push registry -> kube pull -> run
nix-csi:      nix build -> nix copy --to ssh://node -> pod mounts closure -> run
```

### Architecture

1. **CSI Driver DaemonSet** runs on every K3s node with `system-node-critical`
   priority. It implements the CSI `NodePublishVolume` gRPC interface.

2. **Init Container** (`ghcr.io/lillecarl/nix-csi/lix`) copies a pre-built
   Nix environment into the host's `/var/lib/nix-csi/nix` directory on first
   deployment. This gives the CSI driver a working Nix installation.

3. **CSI Node Service** (`dinit csi`) listens on a unix socket and handles
   volume mount requests from the kubelet. When a pod requests a Nix store
   path, the driver:
   - Fetches/builds the closure via `nix build`
   - Bind-mounts the store path into the pod's filesystem
   - Reports success back to the kubelet

4. **Node Driver Registrar** sidecar registers the CSI driver with the
   kubelet so it knows to route `nix.csi.store` volume requests to our socket.

5. **Liveness Probe** sidecar health-checks the CSI gRPC socket.

### Volume Attribute Priority

When a pod requests a Nix volume, the driver resolves the store path using
this priority:

1. `storePath` (or arch-specific `x86_64-linux`) — direct `/nix/store/...` path
2. `flakeRef` — flake reference to build (e.g., `github:owner/repo#package`)
3. `nixExpr` — inline Nix expression to evaluate

The first successful resolution wins.

## How to Deploy

### Step 1: Add the Module

The module is already included in the kubernetes module list at
`kubernetes/default.nix`. Verify it's listed:

```nix
# kubernetes/default.nix
modules = [
  ./modules/nix-csi.nix    # <-- this line
  ./modules/common.nix
  # ... other modules
];
```

### Step 2: Deploy

```bash
# Rebuild the kubernetes manifests
nix build .#kubernetes

# Or deploy directly
just deploy
```

The DaemonSet will roll out to all 4 nodes (zephyr, nexus, forge, sentry).
Each node gets:
- `/var/lib/nix-csi/nix` — the Nix store managed by nix-csi
- `/var/lib/kubelet/plugins/nix.csi.store/` — CSI socket directory

### Step 3: Verify

```bash
kubectl get csidriver nix.csi.store
kubectl get daemonset -n nix-csi nix-node
kubectl get pods -n nix-csi -o wide
```

All 4 node pods should be Running within ~60 seconds.

## Example Workloads

### Example 1: Simple Package Mount (storePath)

```nix
# In your easykubenix module:
infra.Deployment.my-tool = {
  spec = {
    replicas = 1;
    selector.matchLabels.app = "my-tool";
    template = {
      metadata.labels.app = "my-tool";
      spec = {
        nodeName = "nexus";
        containers = {
          _namedlist = true;
          main = {
            image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
            command = [ "hello" ];
            volumeMounts = {
              _namedlist = true;
              nix-store = { mountPath = "/nix/store"; readOnly = true; };
            };
          };
        };
        volumes = {
          _namedlist = true;
          nix-store.csi = {
            driver = "nix.csi.store";
            readOnly = true;
            volumeAttributes = {
              x86_64-linux = pkgs.hello;  # Direct store path
            };
          };
        };
      };
    };
  };
};
```

### Example 2: Flake Reference (flakeRef)

```nix
volumes = {
  _namedlist = true;
  nix-store.csi = {
    driver = "nix.csi.store";
    readOnly = true;
    volumeAttributes = {
      flakeRef = "github:NixOS/nixpkgs/nixos-unstable#hello";
    };
  };
};
```

### Example 3: AI Gateway with nix-csi (from our cluster)

```nix
# Replacing the container image with a direct nix-csi mount
ai-inference.Deployment.ai-gateway = {
  spec.template.spec = {
    nodeName = "nexus";
    containers = {
      _namedlist = true;
      gateway = {
        # Use scratch as base — nix-csi provides the actual binaries
        image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
        command = [ "/nix/store/...-ai-gateway/bin/gateway" ];
        env = [
          { name = "PORT"; value = "8080"; }
          { name = "BACKEND_URL"; value = "http://llama-server-zephyr:1235"; }
        ];
        volumeMounts = {
          _namedlist = true;
          nix-store = { mountPath = "/nix/store"; readOnly = true; };
        };
      };
    };
    volumes = {
      _namedlist = true;
      nix-store.csi = {
        driver = "nix.csi.store";
        readOnly = true;
        volumeAttributes = {
          x86_64-linux = inputs.ai-gateway.packages.x86_64-linux.default;
        };
      };
    };
  };
};
```

### Example 4: YAML Equivalent

For reference, here's the raw YAML for a pod using nix-csi:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello-nix
spec:
  containers:
  - name: hello
    image: ghcr.io/lillecarl/nix-csi/scratch:1.0.1
    command: ["hello"]
    volumeMounts:
    - name: nix-store
      mountPath: /nix/store
      readOnly: true
  volumes:
  - name: nix-store
    csi:
      driver: nix.csi.store
      readOnly: true
      volumeAttributes:
        flakeRef: github:NixOS/nixpkgs/nixos-unstable#hello
```

## Migration Path for Existing Workloads

### When to Use nix-csi vs nix-oci

| Use Case | Use nix-csi | Use nix-oci |
|----------|:-----------:|:-----------:|
| Internal-only services | YES | no |
| Workloads on this cluster | YES | no |
| Images shared outside cluster | no | YES |
| Client-facing container images | no | YES |
| Open source distribution | no | YES |
| Need to push to Docker Hub/GHCR | no | YES |

### Migration Steps (Per Workload)

1. **Identify candidate** — any Deployment/StatefulSet using an image built
   from a project in `/data/projects/own/`.

2. **Switch image to scratch** — replace the OCI image with the nix-csi
   scratch image:
   ```nix
   # Before:
   image = "localhost:5000/ai-gateway:abc123";

   # After:
   image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
   ```

3. **Add CSI volume** — mount the Nix package via nix-csi:
   ```nix
   volumes.nix-store.csi = {
     driver = "nix.csi.store";
     readOnly = true;
     volumeAttributes.x86_64-linux =
       inputs.ai-gateway.packages.x86_64-linux.default;
   };
   ```

4. **Update volumeMounts** — add the Nix store mount:
   ```nix
   volumeMounts.nix-store = {
     mountPath = "/nix/store";
     readOnly = true;
   };
   ```

5. **Update command** — use the Nix store path:
   ```nix
   command = [ "${inputs.ai-gateway.packages.x86_64-linux.default}/bin/gateway" ];
   ```

6. **Test** — `just deploy` and verify the pod starts healthy.

7. **Remove old image** — once confirmed working, remove the `container`
   output from the project flake (or just stop referencing it).

### Recommended Migration Order

Start with the simplest workloads first:

1. **Redis** — single binary, no complex deps (already in host-services.nix)
2. **searxng** — Python app, straightforward
3. **ai-inference-gateway** — Python FastAPI, most impactful
4. **Monitoring** — prometheus, grafana (large, but well-contained)
5. **Mining** — compute-market workloads (GPU-dependent, test carefully)

### Benefits After Migration

- **Faster deploys** — skip image build + registry push + pull cycle
- **Atomic rollbacks** — point to a different store path, instant switch
- **No registry needed** — for internal workloads, no local registry required
- **Smaller footprint** — shared Nix store paths deduplicate automatically
- **Simpler CI** — `nix build` + `nix copy` replaces docker build + push

## Adding nix-csi as a Flake Input

The upstream project is available as `github:Lillecarl/nix-csi`. To add it:

```nix
# In flake.nix inputs:
nix-csi = {
  url = "github:Lillecarl/nix-csi";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Once added, you can replace the manual DaemonSet/RBAC definitions in
`nix-csi.nix` with the upstream's easykubenix modules:

```nix
# kubernetes/default.nix — future state
easykubenix = import inputs.easykubenix {
  inherit pkgs;
  modules = [
    inputs.nix-csi.kubenixModules.default  # upstream module
    { nix-csi.enable = true; }
    # ... your other modules
  ];
};
```

This gives you automatic updates, proper versioning, and access to
upstream features like the cache StatefulSet and builder architecture.

## Current Status

- [x] nix-csi module created with DaemonSet + RBAC
- [ ] Add nix-csi as flake input to flake.nix
- [ ] Verify DaemonSet deploys on all 4 nodes
- [ ] Convert first workload (Redis) to nix-csi mount
- [ ] Expand to remaining internal workloads
- [ ] Keep nix-oci for images that leave the cluster

## References

- nix-csi GitHub: https://github.com/Lillecarl/nix-csi
- nix-csi DeepWiki: https://deepwiki.com/Lillecarl/nix-csi
- Architecture Plan: /data/projects/docs/NIX-ARCHITECTURE-UPGRADE.md (Phase 3)
- Upstream kubenix modules: kubenix/ directory in the nix-csi repo
