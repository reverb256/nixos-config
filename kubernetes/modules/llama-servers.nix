# LLM inference deployments - llama-server via hostPath /nix/store
#
# Uses minimal scratch image with /nix/store bind-mounted from host.
# The Nix-built llama-server binary runs directly - no Docker image build needed.
# Binary auto-updates when NixOS is rebuilt (reads live /nix/store).
#
# Zephyr GPU layout:
#   GPU 0 = RTX 3060 Ti (8GB)  → E4B model (port 1236) [DISABLED - needs GPU isolation]
#   GPU 1 = RTX 3090 (24GB)    → 26B-A4B model (port 1235, coordinator-monitored)
#
# GPU ISOLATION NOTE:
#   nvidia-container-runtime on NixOS is broken (libnvidia-container dlopen can't find
#   libnvidia-ml.so.1 due to NixOS glibc LD_LIBRARY_PATH handling in hook context).
#   Both pods run privileged with CUDA_VISIBLE_DEVICES as a hint (llama.cpp respects it).
#   This means llama.cpp will only use the specified GPU, but the other GPU is still
#   visible in /dev. For inference-only workloads this is safe.
#
# The mining-inference-coordinator watches :1235 on zephyr to detect inference
# activity on the 3090 and shifts gpu-miner-zephyr to the 3060 Ti.
#
# Sentry:
#   AMD RX 5600 XT (6GB, ROCm, gfx1010) → E2B model
{ pkgs, pkgsWithOverlay, config, lib, ... }:
let
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
  managed = { "app.kubernetes.io/managed-by" = "easykubenix"; };

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
in
{
  config.kubernetes.objects.ai-inference = {

    # ── Zephyr RTX 3090 (GPU 1) — Qwen3.6-35B-A3B MoE ──────────────
    # 16.6GB UD-Q3_K_M GGUF weights + KV cache (turbo4 compressed).
    # Only 3B active params per token = fast generation despite 35B total.
    # 262K native context, 64K configured. 5.7GB VRAM free for KV cache.
    # Q3_K_M chosen over Q4_K_XL (21GB) to free VRAM for 2x context window.
    # Decode speed: ~104 tok/s (within 2% of Q4_K_XL).
    # mmproj disabled — crashes turboquant binary (SIGSEGV in clip_model_loader).
    Deployment.llama-server-zephyr = {
      metadata.labels = managed // { app = "llama-server-zephyr"; host = "zephyr"; gpu = "rtx3090"; };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = { app = "llama-server-zephyr"; host = "zephyr"; };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels = managed // { app = "llama-server-zephyr"; host = "zephyr"; gpu = "rtx3090"; };
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
              llama-server = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = [ "${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server" ];
                args = [
                  "--model" "/models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q3_K_M.gguf"
                  "--mmproj" "/models/unsloth/Qwen3.6-35B-A3B-GGUF/mmproj-F16.gguf"
                  "--host" "0.0.0.0"
                  "--port" "1235"
                  "-ngl" "99"
                  "-c" "262144"
                  "-t" "4"
                  "--fit" "off"
                  "--batch-size" "128"
                  "--ubatch-size" "32"
                  "--flash-attn" "on"
                  "--parallel" "1"
                  "--cache-type-k" "turbo4"
                  "--cache-type-v" "turbo4"
                  "--temp" "0.6"
                  "--top-k" "20"
                  "--top-p" "0.95"
                  "--min-p" "0.00"
                  "--presence-penalty" "0.0"
                  "--repeat-penalty" "1.0"
                  "--metrics"
                  "--reasoning-format" "deepseek"
                  "--jinja"
                ];
                env = {
                  _namedlist = true;
                  # CUDA enumeration order differs from nvidia-smi:
                  # CUDA device 0 = RTX 3090, CUDA device 1 = RTX 3060 Ti
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
                  limits = { memory = "20Gi"; cpu = "4"; };
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

    Service.llama-server-zephyr = {
      metadata.labels = managed // { app = "llama-server-zephyr"; };
      spec = {
        type = "ClusterIP";
        ports = [{ name = "http"; port = 1235; protocol = "TCP"; targetPort = 1235; }];
        selector = { app = "llama-server-zephyr"; host = "zephyr"; };
      };
    };

    # ── Zephyr RTX 3060 Ti (GPU 0) — E4B ───────────────────────────
    # E4B model (4.6GB) + mmproj (1.8GB) = 6.4GB, fits in 8GB VRAM.
    # Runs alongside the 3090 deployment. Both privileged, GPU selection via CUDA_VISIBLE_DEVICES.
    Deployment.llama-server-zephyr-3060ti = {
      metadata.labels = managed // { app = "llama-server-zephyr-3060ti"; host = "zephyr"; gpu = "rtx3060ti"; };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = { app = "llama-server-zephyr-3060ti"; host = "zephyr"; };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels = managed // { app = "llama-server-zephyr-3060ti"; host = "zephyr"; gpu = "rtx3060ti"; };
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
              llama-server = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = [ "${pkgsWithOverlay.llama-cpp}/bin/llama-server" ];
                args = [
                  "--model" "/models/unsloth/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-IQ4_NL.gguf"
                  "--mmproj" "/models/unsloth/gemma-4-E4B-it-GGUF/mmproj-F32.gguf"
                  "--host" "0.0.0.0"
                  "--port" "1236"
                  "-ngl" "99"
                  "-c" "8192"
                  "-t" "4"
                  "--fit" "off"
                  "--batch-size" "32"
                  "--ubatch-size" "8"
                  "--flash-attn" "on"
                  "--parallel" "1"
                  "--cache-type-k" "q4_0"
                  "--cache-type-v" "q4_0"
                  "--temp" "1.0"
                  "--top-k" "64"
                  "--top-p" "0.95"
                  "--min-p" "0.05"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  # CUDA enumeration order differs from nvidia-smi:
                  # CUDA device 0 = RTX 3090, CUDA device 1 = RTX 3060 Ti
                  NVIDIA_VISIBLE_DEVICES = { name = "NVIDIA_VISIBLE_DEVICES"; value = "0"; };
                  CUDA_VISIBLE_DEVICES = { name = "CUDA_VISIBLE_DEVICES"; value = "1"; };
                  LD_LIBRARY_PATH = { name = "LD_LIBRARY_PATH"; value = "/run/opengl-driver/lib:/nix/store"; };
                };
                ports = [{ containerPort = 1236; name = "http"; protocol = "TCP"; }];
                livenessProbe = {
                  tcpSocket.port = 1236;
                  initialDelaySeconds = 120;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 1236;
                  initialDelaySeconds = 60;
                  periodSeconds = 10;
                  failureThreshold = 10;
                };
                resources = {
                  requests = { memory = "4Gi"; cpu = "500m"; };
                  limits = { memory = "8Gi"; cpu = "2"; };
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

    Service.llama-server-zephyr-3060ti = {
      metadata.labels = managed // { app = "llama-server-zephyr-3060ti"; };
      spec = {
        type = "ClusterIP";
        ports = [{ name = "http"; port = 1236; protocol = "TCP"; targetPort = 1236; }];
        selector = { app = "llama-server-zephyr-3060ti"; host = "zephyr"; };
      };
    };

    # ── Sentry AMD RX 5600 XT (ROCm, gfx1010) — E2B ─────────────────────────
    Deployment.llama-server-sentry = {
      metadata.labels = managed // { app = "llama-server-sentry"; host = "sentry"; };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = { app = "llama-server-sentry"; host = "sentry"; };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels = managed // { app = "llama-server-sentry"; host = "sentry"; };
            annotations."nix-csi/discard" = "true";
          };
          spec = {
            nodeName = "sentry";
            hostNetwork = true;
            automountServiceAccountToken = false;
            containers = {
              _namedlist = true;
              llama-server = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = [ "${pkgsWithOverlay.llama-cpp-rocm}/bin/llama-server" ];
                args = [
                  "--model" "/models/unsloth/gemma-4-E2B-it-GGUF/gemma-4-E2B-it-IQ4_NL.gguf"
                  "--mmproj" "/models/unsloth/gemma-4-E2B-it-GGUF/mmproj-F32.gguf"
                  "--host" "0.0.0.0"
                  "--port" "1235"
                  "-ngl" "99"
                  "-c" "8192"
                  "-t" "4"
                  "--fit" "off"
                  "--batch-size" "32"
                  "--ubatch-size" "8"
                  "--ubatch-size" "16"
                  "--flash-attn" "on"
                  "--parallel" "1"
                  "--cache-type-k" "q4_0"
                  "--cache-type-v" "q4_0"
                  "--temp" "1.0"
                  "--top-k" "64"
                  "--top-p" "0.95"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  ROC_ENABLE_PRE_VEGA = { name = "ROC_ENABLE_PRE_VEGA"; value = "1"; };
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
                  limits = { memory = "8Gi"; cpu = "2"; };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = { mountPath = "/nix"; readOnly = true; };
                  dev-dri = { mountPath = "/dev/dri"; };
                  dev-kfd = { mountPath = "/dev/kfd"; };
                  models = { mountPath = "/models"; readOnly = true; };
                  opengl = { mountPath = "/run/opengl-driver/lib"; readOnly = true; };
                  tmp = { mountPath = "/tmp"; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix.hostPath = { path = "/nix"; type = "Directory"; };
              dev-dri.hostPath = { path = "/dev/dri"; type = "Directory"; };
              dev-kfd.hostPath = { path = "/dev/kfd"; type = "CharDevice"; };
              models.hostPath.path = "/home/j_kro/.lmstudio/models";
              opengl.hostPath.path = "/run/opengl-driver/lib";
              tmp.emptyDir = {};
            };
          };
        };
      };
    };

    Service.llama-server-sentry = {
      metadata.labels = managed // { app = "llama-server-sentry"; };
      spec = {
        type = "ClusterIP";
        ports = [{ name = "http"; port = 1235; protocol = "TCP"; targetPort = 1235; }];
        selector.app = "llama-server-sentry";
      };
    };
  };
}
