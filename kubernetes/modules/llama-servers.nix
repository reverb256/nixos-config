# LLM inference deployments - llama-server via hostPath /nix/store
#
# Uses minimal scratch image with /nix/store bind-mounted from host.
# The Nix-built llama-server binary runs directly - no Docker image build needed.
# Binary auto-updates when NixOS is rebuilt (reads live /nix/store).
{ pkgs, pkgsWithOverlay, config, lib, ... }:
let
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
  managed = { "app.kubernetes.io/managed-by" = "easykubenix"; };
in
{
  config.kubernetes.objects.ai-inference = {

    Deployment.llama-server-zephyr = {
      metadata.labels = managed // { app = "llama-server-zephyr"; host = "zephyr"; };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = { app = "llama-server-zephyr"; host = "zephyr"; };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels = managed // { app = "llama-server-zephyr"; host = "zephyr"; };
            annotations."nix-csi/discard" = "true";
          };
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
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = [ "${pkgsWithOverlay.llama-cpp}/bin/llama-server" ];
                args = [
                  "--model" "/models/unsloth/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-IQ4_NL.gguf"
                  "--mmproj" "/models/unsloth/gemma-4-E4B-it-GGUF/mmproj-F32.gguf"
                  "--host" "0.0.0.0"
                  "--port" "1235"
                  "-ngl" "-1"
                  "-c" "131072"
                  "-t" "4"
                  "--fit" "on"
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
                  "--min-p" "0.05"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  NVIDIA_VISIBLE_DEVICES = { name = "NVIDIA_VISIBLE_DEVICES"; value = "1"; };
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
                  nvidia-libs = { mountPath = "/run/opengl-driver/lib"; readOnly = true; };
                  models = { mountPath = "/models"; readOnly = true; };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix.hostPath = { path = "/nix"; type = "Directory"; };
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

    # Sentry llama-server (ROCm, RX 5600 XT, Gemma 4 E2B)
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
                  "-c" "65536"
                  "-t" "4"
                  "--fit" "off"
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
                  limits = { memory = "16Gi"; cpu = "2"; };
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