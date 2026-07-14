# LLM inference deployments - llama-server via nix-csi /nix/store
#
# Uses minimal scratch image with /nix/store bind-mounted from host.
# The Nix-built llama-server binary runs directly - no Docker image build needed.
# Binary auto-updates when NixOS is rebuilt (reads live /nix/store).
#
# GPU layout:
#   Nexus GPU 0 = RTX 3060 Ti (8GB)  → Qwen3.5-2B-AWQ via vLLM+TurboQuant (port 8040, nix-csi)
#   Zephyr GPU 1 = RTX 3090 (24GB)   → 35B MoE model (port 1237, coordinator-monitored)
#
# GPU ISOLATION NOTE:
#   nvidia-container-runtime on NixOS is broken (libnvidia-container dlopen can't find
#   libnvidia-ml.so.1 due to NixOS glibc LD_LIBRARY_PATH handling in hook context).
#   Both pods run privileged with CUDA_VISIBLE_DEVICES as a hint (llama.cpp respects it).
#   This means llama.cpp will only use the specified GPU, but the other GPU is still
#   visible in /dev. For inference-only workloads this is safe.
#
# The mining-inference-coordinator watches :1237 on zephyr to detect inference
# activity on the 3090 and pauses gpu-miner-zephyr (no 3060Ti fallback).
#
# Sentry:
#   AMD RX 5600 XT (6GB, Vulkan/RADV, gfx1010) → 4B model
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
    {
      key = "workstation";
      operator = "Exists";
    }
    {
      key = "interactive";
      operator = "Exists";
    }
    {
      key = "node-role.kubernetes.io/control-plane";
      operator = "Exists";
      effect = "NoSchedule";
    }
  ];

  baseVolumes = {
    _namedlist = true;
    nix.persistentVolumeClaim = {
      claimName = "nix-store";
      readOnly = true;
    };
    nvidia-libs.hostPath.path = "/run/opengl-driver/lib";
  };

  nexusVolumes =
    baseVolumes
    // {
      tmp.hostPath = {
        path = "/tmp";
        type = "Directory";
      };
      etc.hostPath = {
        path = "/etc";
        type = "Directory";
      };
    };

  zephyrVolumes =
    baseVolumes
    // {
      dflash.hostPath.path = "/home/j_kro/.lmstudio/models/dflash";
    };

  sentryVolumes =
    baseVolumes
    // {
      dev-dri.hostPath = {
        path = "/dev/dri";
        type = "Directory";
      };
      vulkan-icd.hostPath.path = "/run/opengl-driver/share/vulkan/icd.d";
      tmp.emptyDir = {};
      models.hostPath = {
        path = "/home/j_kro/models";
        type = "Directory";
      };
    };
in {
  config.kubernetes.objects.ai-inference = {
    # ── Zephyr RTX 3090 (GPU 1) — Qwen3.6-35B-A3B MoE ──────────────────────
    #   MoE 35B (3B active) with A3B + IQ4_XS quantization.
    #   Target: /home/j_kro/.lmstudio/models/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf
    # ── Nexus RTX 3060 Ti — Qwen3.5-2B-AWQ via vLLM + TurboQuant (nix-csi) ─
    # Nix store path: vllm-turboquant-env (pip-installed vLLM + TurboQuant)
    # Entrypoint: vllm-tq-wrapper (applies TurboQuant monkey-patch, runs API server)
    # Volumes: /nix (nix-csi), /run/opengl-driver/lib (NVIDIA), /models, /tmp
    # No Docker registry dependency - served from host Nix store via nix-csi
    Deployment.llama-qwen-vllm-nexus = {
      metadata.labels =
        managed
        // {
          app = "llama-qwen-vllm-nexus";
          host = "nexus";
          gpu = "rtx3060ti";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "llama-qwen-vllm-nexus";
          host = "nexus";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "llama-qwen-vllm-nexus";
                host = "nexus";
                gpu = "rtx3060ti";
              };
          };
          spec = {
            nodeName = "nexus";
            hostNetwork = true;
            automountServiceAccountToken = false;
            priorityClassName = "medium-priority-ai";
            tolerations = [];
            containers = {
              _namedlist = true;
            } // lib.optionalAttrs (pkgsWithOverlay ? vllm-turboquant-env) {
              vllm = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgsWithOverlay.vllm-turboquant-env}/bin/vllm-tq-wrapper"];
                args = [
                  "--model"
                  "/data/models/QuantTrio/Qwen3.5-2B-AWQ"
                  "--served-model-name"
                  "qwen3.5-2b-awq"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "8040"
                  "--gpu-memory-utilization"
                  "0.85"
                  "--max-num-seqs"
                  "16"
                  "--max-model-len"
                  "180000"
                  "--quantization"
                  "awq"
                  "--enable-prefix-caching"
                  "--enforce-eager"
                ];
                env = {
                  _namedlist = true;
                  VLLM_CACHE_ROOT = {
                    name = "VLLM_CACHE_ROOT";
                    value = "/tmp/vllm-cache";
                  };
                  NVIDIA_VISIBLE_DEVICES = {
                    name = "NVIDIA_VISIBLE_DEVICES";
                    value = "0";
                  };
                  CUDA_VISIBLE_DEVICES = {
                    name = "CUDA_VISIBLE_DEVICES";
                    value = "0";
                  };
                  TORCHINDUCTOR_CACHE_DIR = {
                    name = "TORCHINDUCTOR_CACHE_DIR";
                    value = "/tmp/vllm-cache";
                  };
                };
                resources = {
                  requests = {
                    cpu = "2";
                    memory = "12Gi";
                  };
                  limits = {
                    cpu = "4";
                    memory = "16Gi";
                  };
                };
                ports = [
                  {
                    containerPort = 8040;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8040;
                  };
                  initialDelaySeconds = 180;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8040;
                  };
                  initialDelaySeconds = 90;
                  periodSeconds = 10;
                  failureThreshold = 10;
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    readOnly = true;
                  };
                  nvidia-libs = {
                    mountPath = "/run/opengl-driver/lib";
                    readOnly = true;
                  };
                  models = {
                    mountPath = "/models";
                    readOnly = true;
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                  etc = {
                    mountPath = "/etc";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = nexusVolumes;
          };
        };
      };
    };

    Service.llama-qwen-vllm-nexus = {
      metadata.labels =
        managed
        // {
          app = "llama-qwen-vllm-nexus";
        };
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 8040;
            protocol = "TCP";
            targetPort = 8040;
          }
        ];
        selector = {
          app = "llama-qwen-vllm-nexus";
          host = "nexus";
        };
      };
    };

    # ── Zephyr RTX 3090 — Carnice Qwen3.6-MoE-35B-A3B (Primary local model) ──
    # Carnice finetune of Qwen3.6-35B-A3B MoE. IQ4_XS quantization fits 24GB 3090.
    # 256K context via turbo4 KV compression, 16 threads for Zen3 5950X.
    Deployment.llama-server-zephyr-3090-moe = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr-3090-moe";
          host = "zephyr";
          gpu = "rtx3090";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "llama-server-zephyr-3090-moe";
          host = "zephyr";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "llama-server-zephyr-3090-moe";
                host = "zephyr";
                gpu = "rtx3090";
              };
          };
          spec = {
            nodeName = "zephyr"; # P0: MUST stay on zephyr — RTX 3090 GPU hardware
            hostNetwork = true;
            automountServiceAccountToken = false;
            priorityClassName = "high-priority-ai";
            tolerations = zephyrTolerations;
            containers = {
              _namedlist = true;
            } // lib.optionalAttrs (pkgsWithOverlay ? llama-cpp-turboquant) {
              llama-server = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/mradermacher/Carnice-Qwen3.6-MoE-35B-A3B-GGUF/Carnice-Qwen3.6-MoE-35B-A3B.IQ4_XS.gguf"
                  "--mmproj"
                  "/models/unsloth/Qwen3.6-35B-A3B-GGUF/mmproj-BF16.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1237"
                  "-ngl"
                  "60"
                  "--split-mode"
                  "none"
                  "--main-gpu"
                  "1"
                  "-c"
                  "262144"
                  "-t"
                  "16"
                  "--flash-attn"
                  "on"
                  "-ctk"
                  "turbo4"
                  "-ctv"
                  "turbo4"
                  "--parallel"
                  "1"
                  "--metrics"
                  "-b"
                  "256"
                  "--reasoning"
                  "on"
                  "--chat-template-kwargs"
                  ''{"preserve_thinking": true, "enable_thinking": true}''
                  "--temp"
                  "0.7"
                  "--top-k"
                  "20"
                  "--top-p"
                  "0.8"
                  "--min-p"
                  "0.0"
                  "--presence-penalty"
                  "1.5"
                ];
                env = {
                  _namedlist = true;
                  NVIDIA_VISIBLE_DEVICES = {
                    name = "NVIDIA_VISIBLE_DEVICES";
                    value = "1";
                  };
                  CUDA_VISIBLE_DEVICES = {
                    name = "CUDA_VISIBLE_DEVICES";
                    value = "1";
                  };
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib:/nix/store";
                  };
                };
                ports = [
                  {
                    containerPort = 1237;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 1237;
                  initialDelaySeconds = 120;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 1237;
                  initialDelaySeconds = 60;
                  periodSeconds = 10;
                  failureThreshold = 10;
                };
                resources = {
                  requests = {
                    memory = "4Gi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "16Gi";
                    cpu = "4";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    readOnly = true;
                  };
                  nvidia-libs = {
                    mountPath = "/run/opengl-driver/lib";
                    readOnly = true;
                  };
                  models = {
                    mountPath = "/models";
                    readOnly = true;
                  };
                  dflash = {
                    mountPath = "/dflash";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = zephyrVolumes;
          };
        };
      };
    };

    Service.llama-server-zephyr-3090-moe = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr-3090-moe";
        };
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 1237;
            protocol = "TCP";
            targetPort = 1237;
          }
        ];
        selector = {
          app = "llama-server-zephyr-3090-moe";
          host = "zephyr";
        };
      };
    };

    # ── Sentry AMD RX 5600 XT (Vulkan/RADV, gfx1010) — Qwen3.5-4B ──────
    # Vulkan backend: RADV (Mesa) outperforms ROCm on RDNA1 for token generation.
    # Flash attention required: quantized V cache (q4_0) needs flash_attn since llama.cpp b3880+.
    # 256K context, q4_0 KV cache (lighter than iq4_nl, faster decompression).
    # NOTE: thinking (reasoning tokens) is DISABLED for this deployment.
    #       The Qwen3.5-4B model does NOT use <｜end▁of▁sentence｜> thinking tokens
    #       that are enabled in the -Wrist-On- version. This is a non-thinking build.

    Deployment.llama-server-sentry = {
      metadata.labels =
        managed
        // {
          app = "llama-server-sentry";
          host = "sentry";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "llama-server-sentry";
          host = "sentry";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "llama-server-sentry";
                host = "sentry";
              };
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
                command = ["${pkgsWithOverlay.llama-cpp-vulkan}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/unsloth/Qwen3.5-4B-GGUF/Qwen3.5-4B-Q4_K_M.gguf"
                  "--mmproj"
                  "/models/unsloth/Qwen3.5-4B-GGUF/mmproj-BF16.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1235"
                  "-ngl"
                  "99"
                  "-c"
                  "262144"
                  "-t"
                  "2"
                  "--parallel"
                  "1"
                  "--cont-batching"
                  "--metrics"
                  "--cache-type-k"
                  "q4_0"
                  "--cache-type-v"
                  "q4_0"
                  "--flash-attn"
                  "on"
                ];
                env = {
                  _namedlist = true;
                  HSA_OVERRIDE_GFX_VERSION = {
                    name = "HSA_OVERRIDE_GFX_VERSION";
                    value = "10.3.0";
                  };
                };
                ports = [
                  {
                    containerPort = 1235;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
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
                  requests = {
                    memory = "4Gi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "8Gi";
                    cpu = "2";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    readOnly = true;
                  };
                  dev-dri = {
                    mountPath = "/dev/dri";
                  };
                  models = {
                    mountPath = "/models";
                    readOnly = true;
                  };
                  nvidia-libs = {
                    mountPath = "/run/opengl-driver/lib";
                    readOnly = true;
                  };
                  vulkan-icd = {
                    mountPath = "/run/opengl-driver/share/vulkan/icd.d";
                    readOnly = true;
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
              };
            };
            volumes = sentryVolumes;
          };
        };
      };
    };

    Service.llama-server-sentry = {
      metadata.labels =
        managed
        // {
          app = "llama-server-sentry";
        };
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 1235;
            protocol = "TCP";
            targetPort = 1235;
          }
        ];
        selector.app = "llama-server-sentry";
      };
    };
  };
}
