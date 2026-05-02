# K8s Deployment Reference — Easykubenix Patterns

Complete working examples from the cluster. Use these as copy-paste templates.

## Full Scratch Deployment (NVIDIA GPU)

Source: `kubernetes/modules/llama-servers.nix`

```nix
{
  pkgs,
  pkgsWithOverlay,
  config,
  lib,
  ...
}: let
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  zephyrTolerations = [
    { key = "workstation"; operator = "Exists"; }
    { key = "interactive"; operator = "Exists"; }
    { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
  ];

  zephyrVolumes = {
    _namedlist = true;
    nix.hostPath = { path = "/nix"; type = "Directory"; };
    nvidia-libs.hostPath.path = "/run/opengl-driver/lib";
    models.hostPath.path = "/home/j_kro/.lmstudio/models";
  };
in {
  config.kubernetes.objects.ai-inference = {
    Deployment.my-gpu-app = {
      metadata.labels = managed // {
        app = "my-gpu-app";
        host = "zephyr";
        gpu = "rtx3090";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = { app = "my-gpu-app"; host = "zephyr"; };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels = managed // { app = "my-gpu-app"; host = "zephyr"; gpu = "rtx3090"; };
            annotations."nix-csi/discard" = "true";
          };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            automountServiceAccountToken = false;
            priorityClassName = "high-priority-ai";
            tolerations = zephyrTolerations;
            containers = {
              _namedlist = true;
              my-app = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server"];
                args = ["--model" "/models/my-model.gguf" "--host" "0.0.0.0" "--port" "1235"];
                env = {
                  _namedlist = true;
                  NVIDIA_VISIBLE_DEVICES = { name = "NVIDIA_VISIBLE_DEVICES"; value = "1"; };
                  CUDA_VISIBLE_DEVICES = { name = "CUDA_VISIBLE_DEVICES"; value = "0"; };
                  LD_LIBRARY_PATH = { name = "LD_LIBRARY_PATH"; value = "/run/opengl-driver/lib:/nix/store"; };
                };
                ports = [{ containerPort = 1235; name = "http"; protocol = "TCP"; }];
                livenessProbe = {
                  tcpSocket.port = 1235;
                  initialDelaySeconds = 120;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 1235;
                  initialDelaySeconds = 60;
                  periodSeconds = 10;
                  failureThreshold = 10;
                };
                resources = {
                  requests = { memory = "4Gi"; cpu = "500m"; };
                  limits = { memory = "16Gi"; cpu = "4"; };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = { mountPath = "/nix"; readOnly = true; };
                  nvidia-libs = { mountPath = "/run/opengl-driver/lib"; readOnly = true; };
                  models = { mountPath = "/models"; readOnly = true; };
                };
              };
            };
            volumes = zephyrVolumes;
          };
        };
      };
    };

    Service.my-gpu-app = {
      metadata.labels = managed // { app = "my-gpu-app"; };
      spec = {
        type = "ClusterIP";
        ports = [{ name = "http"; port = 1235; protocol = "TCP"; targetPort = 1235; }];
        selector = { app = "my-gpu-app"; host = "zephyr"; };
      };
    };
  };
}
```

## Full Scratch Deployment (AMD GPU / Vulkan)

Source: `kubernetes/modules/llama-servers.nix`

```nix
Deployment.my-amd-app = {
  # ... same boilerplate as above ...
  spec.template.spec = {
    nodeName = "sentry";
    containers.my-app = {
      image = scratchImage;
      command = ["${pkgsWithOverlay.llama-cpp-vulkan}/bin/llama-server"];
      env = {
        _namedlist = true;
        LD_LIBRARY_PATH = { name = "LD_LIBRARY_PATH"; value = "/run/opengl-driver/lib:/nix/store"; };
        VK_ICD_FILENAMES = { name = "VK_ICD_FILENAMES"; value = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json"; };
      };
      volumeMounts = {
        _namedlist = true;
        nix = { mountPath = "/nix"; readOnly = true; };
        dev-dri = { mountPath = "/dev/dri"; };
        models = { mountPath = "/models"; readOnly = true; };
        opengl = { mountPath = "/run/opengl-driver/lib"; readOnly = true; };
        vulkan-icd = { mountPath = "/run/opengl-driver/share/vulkan/icd.d"; readOnly = true; };
      };
    };
    volumes = {
      _namedlist = true;
      nix.hostPath = { path = "/nix"; type = "Directory"; };
      dev-dri.hostPath = { path = "/dev/dri"; type = "Directory"; };
      models.hostPath.path = "/home/j_kro/.lmstudio/models";
      opengl.hostPath.path = "/run/opengl-driver/lib";
      vulkan-icd.hostPath.path = "/run/opengl-driver/share/vulkan/icd.d";
    };
  };
};
```

## Easykubenix _namedlist Convention

Easykubenix uses `_namedlist = true` to distinguish named lists (where keys become labels/selectors) from regular lists.

**Always use `_namedlist = true` on:**
- `containers`
- `volumes`
- `volumeMounts`
- `env`
- Any attrset that should produce named map in YAML

**Never use on:**
- `ports` (regular list of objects)
- `args` (regular list of strings)
- `command` (regular list)
- `tolerations` (regular list)
