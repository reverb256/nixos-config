# LLM inference deployments — llama-server via nix-csi
#
# Runs GPU-accelerated LLM inference as K8s pods using nix-csi to mount
# the Nix-built llama-server binary directly. No Docker image needed.
#
# Pattern: nix-csi scratch image + CSI ephemeral volume for Nix store
# binary + hostPath for GPU driver + hostPath for model files
#
# nix-csi resolves the Nix store path at pod creation time, so the binary
# auto-updates when the Nix config is rebuilt (no stale image problem).
{ pkgs, pkgsWithOverlay, config, lib, ... }:
let
  # nix-csi scratch image — minimal container that nix-csi mounts /nix into
  nixCsiScratch = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";

  managed = { "app.kubernetes.io/managed-by" = "easykubenix"; };
in
{
  config.kubernetes.objects.ai-inference = {

    # ── Zephyr llama-server (CUDA, RTX 3060 Ti, Gemma 4 E4B vision) ──
    # Uses CUDA_VISIBLE_DEVICES=1 to target 3060 Ti (GPU 1 in CUDA ordering)
    # 3090 (GPU 0) is reserved for lolMiner
    Deployment.llama-server-zephyr = {
      metadata.labels = managed // { app = "llama-server-zephyr"; host = "zephyr"; };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = { app = "llama-server-zephyr"; host = "zephyr"; };
        strategy.type = "Recreate";
        template = {
          metadata.labels = managed // { app = "llama-server-zephyr"; host = "zephyr"; };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            automountServiceAccountToken = false;
            priorityClassName = "high-priority-ai";
            tolerations = [
              { key = "workstation"; operator = "Exists"; }
              { key = "interactive"; operator = "Exists"; }
              { key = "node-role.kubernetes.io/control-plane"; operator = "Exists"; effect = "NoSchedule"; }
            ];
            containers = {
              _namedlist = true;
              llama-server = {
                image = nixCsiScratch;
                imagePullPolicy = "IfNotPresent";
                command = [ "/nix/bin/llama-server" ];
                args = [
                  "--model" "/models/lmstudio-community/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf"
                  "--mmproj" "/models/lmstudio-community/gemma-4-E4B-it-GGUF/mmproj-gemma-4-E4B-it-BF16.gguf"
                  "--host" "0.0.0.0"
                  "--port" "1235"
                  "-ngl" "99"
                  "-c" "131072"
                  "-t" "4"
                  "--batch-size" "64"
                  "--ubatch-size" "16"
                  "--flash-attn" "on"
                  "--parallel" "1"
                  "--chat-template-kwargs" ''{"enable_thinking":false}''
                  "--reasoning-budget" "0"
                  "--cache-type-k" "q4_0"
                  "--cache-type-v" "q4_0"
                  "--cache-ram" "0"
                  "--temp" "1.0"
                  "--top-k" "64"
                  "--top-p" "0.95"
                  "--min-p" "0.05"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  CUDA_VISIBLE_DEVICES = { name = "CUDA_VISIBLE_DEVICES"; value = "1"; };
                  LD_LIBRARY_PATH = { name = "LD_LIBRARY_PATH"; value = "/run/opengl-driver/lib:/nix/lib"; };
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
                  nix-store = { mountPath = "/nix"; };
                  dev = { mountPath = "/dev"; };
                  nvidia-libs = { mountPath = "/run/opengl-driver/lib"; readOnly = true; };
                  models = { mountPath = "/models"; readOnly = true; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              # nix-csi ephemeral volume — mounts the Nix-built llama-cpp binary
              nix-store = {
                csi = {
                  driver = "nix.csi.store";
                  volumeAttributes.x86_64-linux = "${pkgsWithOverlay.llama-cpp}";
                };
              };
              dev.hostPath.path = "/dev";
              nvidia-libs.hostPath.path = "/run/opengl-driver/lib";
              models.hostPath.path = "/home/j_kro/.lmstudio/models";
            };
          };
        };
      };
    };

    Service.llama-server-zephyr = {
      metadata.labels = managed // { app = "llama-server-zephyr"; };
      spec = {
        type = "ClusterIP";
        ports = [{ name = "http"; port = 1235; protocol = "TCP"; targetPort = 1235; }];
        selector.app = "llama-server-zephyr";
      };
    };

    # ── Sentry llama-server (ROCm, RX 5600 XT, Gemma 4 E2B) ────
    # Disabled until sentry is redeployed with the fixed llama-cpp-rocm package.
    # Enable by setting replicas = 1 after deploy.
    Deployment.llama-server-sentry = {
      metadata.labels = managed // { app = "llama-server-sentry"; host = "sentry"; };
      spec = {
        replicas = 0;
        revisionHistoryLimit = 1;
        selector.matchLabels = { app = "llama-server-sentry"; host = "sentry"; };
        strategy.type = "Recreate";
        template = {
          metadata.labels = managed // { app = "llama-server-sentry"; host = "sentry"; };
          spec = {
            nodeName = "sentry";
            hostNetwork = true;
            automountServiceAccountToken = false;
            containers = {
              _namedlist = true;
              llama-server = {
                image = nixCsiScratch;
                imagePullPolicy = "IfNotPresent";
                command = [ "/nix/bin/llama-server" ];
                args = [
                  "--model" "/models/unsloth/gemma-4-E2B-it-GGUF/gemma-4-E2B-it-IQ4_NL.gguf"
                  "--mmproj" "/models/unsloth/gemma-4-E2B-it-GGUF/mmproj-F32.gguf"
                  "--host" "0.0.0.0"
                  "--port" "1235"
                  "-ngl" "99"
                  "-c" "131072"
                  "-t" "4"
                  "--batch-size" "64"
                  "--ubatch-size" "16"
                  "--flash-attn" "on"
                  "--parallel" "1"
                  "--cache-type-k" "q4_0"
                  "--cache-type-v" "q4_0"
                  "--cache-ram" "0"
                  "--temp" "1.0"
                  "--top-k" "64"
                  "--top-p" "0.95"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  ROC_ENABLE_PRE_VEGA = { name = "ROC_ENABLE_PRE_VEGA"; value = "1"; };
                  LD_LIBRARY_PATH = { name = "LD_LIBRARY_PATH"; value = "/run/opengl-driver/lib:/nix/lib"; };
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
                  requests = { memory = "2Gi"; cpu = "500m"; };
                  limits = { memory = "6Gi"; cpu = "2"; };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix-store = { mountPath = "/nix"; };
                  dev-dri = { mountPath = "/dev/dri"; };
                  dev-kfd = { mountPath = "/dev/kfd"; };
                  models = { mountPath = "/models"; readOnly = true; };
                  opengl = { mountPath = "/run/opengl-driver/lib"; readOnly = true; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              # nix-csi ephemeral volume — mounts the Nix-built llama-cpp-rocm binary
              nix-store = {
                csi = {
                  driver = "nix.csi.store";
                  volumeAttributes.x86_64-linux = "${pkgsWithOverlay.llama-cpp-rocm}";
                };
              };
              dev-dri.hostPath = { path = "/dev/dri"; type = "Directory"; };
              dev-kfd.hostPath = { path = "/dev/kfd"; type = "CharDevice"; };
              models.hostPath.path = "/home/j_kro/.lmstudio/models";
              opengl.hostPath.path = "/run/opengl-driver/lib";
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
