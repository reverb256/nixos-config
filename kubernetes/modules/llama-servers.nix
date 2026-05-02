# LLM inference deployments - llama-server via hostPath /nix/store
#
# Uses minimal scratch image with /nix/store bind-mounted from host.
# The Nix-built llama-server binary runs directly - no Docker image build needed.
# Binary auto-updates when NixOS is rebuilt (reads live /nix/store).
#
# Zephyr GPU layout:
#   GPU 0 = RTX 3060 Ti (8GB)  → Qwen3.5-4B-AWQ via vLLM (port 8040, concurrency)
#   GPU 1 = RTX 3090 (24GB)    → 35B MoE model (port 1235, coordinator-monitored)
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
#   AMD RX 5700 XT (6GB, ROCm, gfx1010) → 4B model
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
  zephyrVolumes = {
    _namedlist = true;
    nix.hostPath = {
      path = "/nix";
      type = "Directory";
    };
    nvidia-libs.hostPath.path = "/run/opengl-driver/lib";
    models.hostPath.path = "/home/j_kro/.lmstudio/models";
  };
in {
  config.kubernetes.objects.ai-inference = {
    # ── Zephyr RTX 3090 (GPU 1) — Qwen3.6-35B-A3B MoE ──────────────────────
    #   MoE 35B (15B active) with A3B + IQ3_S quantization.
    #   Target: /home/j_kro/.lmstudio/models/Qwen3.6-35B-A3B-UD-IQ3_S.gguf
    Deployment.llama-server-zephyr = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr";
          host = "zephyr";
          gpu = "rtx3090";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "llama-server-zephyr";
          host = "zephyr";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "llama-server-zephyr";
                host = "zephyr";
                gpu = "rtx3090";
              };
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
                command = ["${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/Qwen3.6-35B-A3B-UD-IQ3_S.gguf"
                  # DFlash draft model for speculative decoding
                  "-md"
                  "/dflash/dflash-draft-3.6-q8_0.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1235"
                  "-ngl"
                  "40"
                  "-c"
                  "262144"
                  "-t"
                  "4"
                  "--flash-attn"
                  "on"
                  # DFlash speculative decoding — entire block in single forward pass
                  "--spec-type"
                  "dflash"
                  "--draft-max"
                  "22"
                  # TurboQuant KV cache: 3.8x compression, lossless quality
                  "-ctk"
                  "turbo4"
                  "-ctv"
                  "turbo4"
                  "--parallel"
                  "1"
                  "--temp"
                  "0.7"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  # CUDA enumeration order differs from nvidia-smi:
                  # CUDA device 0 = RTX 3090, CUDA device 1 = RTX 3060 Ti
                  NVIDIA_VISIBLE_DEVICES = {
                    name = "NVIDIA_VISIBLE_DEVICES";
                    value = "1";
                  };
                  CUDA_VISIBLE_DEVICES = {
                    name = "CUDA_VISIBLE_DEVICES";
                    value = "0";
                  };
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib:/nix/store";
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

    Service.llama-server-zephyr = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr";
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
        selector = {
          app = "llama-server-zephyr";
          host = "zephyr";
        };
      };
    };

    # ── Zephyr RTX 3060 Ti (GPU 0) — Qwen3.5-4B-AWQ via vLLM (concurrency) ──────
    # vLLM for concurrent request handling (vs llama-cpp for single-stream).
    # AWQ 4-bit fits in 8GB VRAM with room for KV cache.
    # hostNetwork + CUDA_VISIBLE_DEVICES=1 selects the 3060Ti (PCI enumeration).
    Deployment.llama-qwen-vllm-zephyr-3060ti = {
      metadata.labels =
        managed
        // {
          app = "llama-qwen-vllm-zephyr-3060ti";
          host = "zephyr";
          gpu = "rtx3060ti";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "llama-qwen-vllm-zephyr-3060ti";
          host = "zephyr";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "llama-qwen-vllm-zephyr-3060ti";
                host = "zephyr";
                gpu = "rtx3060ti";
              };
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
              vllm = {
                image = "vllm/vllm-openai:v0.19.1";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "python3"
                  "-m"
                  "vllm.entrypoints.openai.api_server"
                ];
                args = [
                  "--model"
                  "/models/QuantTrio/Qwen3.5-4B-AWQ"
                  "--served-model-name"
                  "qwen3.5-4b-awq"
                  "--port"
                  "8040"
                  "--host"
                  "0.0.0.0"
                  "--quantization"
                  "awq"
                  "--gpu-memory-utilization"
                  "0.95"
                  "--max-num-seqs"
                  "16"
                  "--max-model-len"
                  "32768"
                  "--enable-prefix-caching"
                  "--disable-log-requests"
                ];
                env = {
                  _namedlist = true;
                  CUDA_VISIBLE_DEVICES = {
                    name = "CUDA_VISIBLE_DEVICES";
                    value = "1";
                  };
                  VLLM_WORKER_MULTIPROCESING_METHOD = {
                    name = "VLLM_WORKER_MULTIPROCESING_METHOD";
                    value = "spawn";
                  };
                };
                resources = {
                  requests = {
                    cpu = "1";
                    memory = "4Gi";
                    nvidia.com/gpu = "1";
                  };
                  limits = {
                    cpu = "2";
                    memory = "8Gi";
                    nvidia.com/gpu = "1";
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
                  initialDelaySeconds = 120;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8040;
                  };
                  initialDelaySeconds = 60;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  models = {
                    mountPath = "/models";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              models.hostPath = {
                path = "/home/j_kro/.lmstudio/models";
                type = "Directory";
              };
            };
          };
        };
      };
    };

    Service.llama-qwen-vllm-zephyr-3060ti = {
      metadata.labels =
        managed
        // {
          app = "llama-qwen-vllm-zephyr-3060ti";
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
        selector.app = "llama-qwen-vllm-zephyr-3060ti";
      };
    };

    # ── Zephyr RTX 3090 Burst — hermes-qwen3.5-35b-a3b MoE (Speed) ──────────────
    # MoE: 35B total / ~3B active per token. Blazing fast for agentic workloads.
    # Scaled to 0 by default — scale up when mining is paused.
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
                command = ["${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/Qwen3.6-35B-A3B-UD-IQ3_S.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1237"
                  "-ngl"
                  "99"
                  "-c"
                  "32768"
                  "-t"
                  "4"
                  "--flash-attn"
                  "on"
                  "-ctk"
                  "turbo4"
                  "-ctv"
                  "turbo4"
                  "--parallel"
                  "1"
                  "--temp"
                  "0.7"
                  "--metrics"
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

    # ── Zephyr RTX 3090 Burst — Ornstein-Hermes-3.6-27b-SABER (Quality) ────────
    # Dense 27B with SABER refusal shaping, multimodal preserved.
    # Scaled to 0 by default — scale up when mining is paused.
    Deployment.llama-server-zephyr-3090-dense = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr-3090-dense";
          host = "zephyr";
          gpu = "rtx3090";
        };
      spec = {
        replicas = 0;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "llama-server-zephyr-3090-dense";
          host = "zephyr";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "llama-server-zephyr-3090-dense";
                host = "zephyr";
                gpu = "rtx3090";
              };
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
                command = ["${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/GestaltLabs/Ornstein-Hermes-3.6-27b-SABER-GGUF/Ornstein-Hermes-3.6-27b-SABER-Q5_K_M.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1238"
                  "-ngl"
                  "99"
                  "-c"
                  "32768"
                  "-t"
                  "4"
                  "--flash-attn"
                  "on"
                  "-ctk"
                  "turbo4"
                  "-ctv"
                  "turbo4"
                  "--parallel"
                  "1"
                  "--temp"
                  "0.7"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  NVIDIA_VISIBLE_DEVICES = {
                    name = "NVIDIA_VISIBLE_DEVICES";
                    value = "1";
                  };
                  CUDA_VISIBLE_DEVICES = {
                    name = "CUDA_VISIBLE_DEVICES";
                    value = "0";
                  };
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib:/nix/store";
                  };
                };
                ports = [
                  {
                    containerPort = 1238;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 1238;
                  initialDelaySeconds = 120;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 1238;
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
                    memory = "24Gi";
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
                };
              };
            };
            volumes = zephyrVolumes;
          };
        };
      };
    };

    Service.llama-server-zephyr-3090-dense = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr-3090-dense";
        };
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 1238;
            protocol = "TCP";
            targetPort = 1238;
          }
        ];
        selector = {
          app = "llama-server-zephyr-3090-dense";
          host = "zephyr";
        };
      };
    };



    # ── Sentry AMD RX 5600 XT (Vulkan/RADV, gfx1010) — Qwen3-4B-Wrist-On-Hermes ──────
    # Vulkan backend: RADV (Mesa) outperforms ROCm on RDNA1 for token generation.
    # Flash attention required: quantized V cache (q4_0) needs flash_attn since llama.cpp b3880+.
    # 256K context, q4_0 KV cache (lighter than iq4_nl, faster decompression).
    # NOTE: thinking (reasoning tokens) is DISABLED for this deployment.
    #       The Qwen3-4B-Wrist-On-Hermes model does NOT use <｜end▁of▁sentence｜> thinking tokens
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
                command = ["${pkgsWithOverlay.llama-cpp-vulkan}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/mradermacher/Qwen3-4B-Wrist-On-Hermes-i1-GGUF/Qwen3-4B-Wrist-On-Hermes.i1-Q4_K_M.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1235"
                  "-ngl"
                  "99"
                  "-c"
                  "262144"
                  "-t"
                  "4"
                  "--fit"
                  "off"
                  "--batch-size"
                  "128"
                  "--ubatch-size"
                  "32"
                  "--flash-attn"
                  "on"
                  "--parallel"
                  "1"
                  "--cache-type-k"
                  "q4_0"
                  "--cache-type-v"
                  "q4_0"
                  "--temp"
                  "0.6"
                  "--top-k"
                  "20"
                  "--top-p"
                  "0.95"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib:/nix/store";
                  };
                  VK_ICD_FILENAMES = {
                    name = "VK_ICD_FILENAMES";
                    value = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
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
                  opengl = {
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
            volumes = {
              _namedlist = true;
              nix.hostPath = {
                path = "/nix";
                type = "Directory";
              };
              dev-dri.hostPath = {
                path = "/dev/dri";
                type = "Directory";
              };
              models.hostPath.path = "/home/j_kro/.lmstudio/models";
              dflash.hostPath.path = "/home/j_kro/.cache/huggingface/hub/models--spiritbuun--Qwen3.6-27B-DFlash-GGUF/snapshots/5e4442a299deb9282b3dfe179de6e8330b19d9de";
              opengl.hostPath.path = "/run/opengl-driver/lib";
              vulkan-icd.hostPath.path = "/run/opengl-driver/share/vulkan/icd.d";
              tmp.emptyDir = {};
            };
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

    # ── Zephyr RTX 3090 Burst — Ornstein-Hermes-3.6-27b-SABER (131K ctx) ──────
    # Dense 27B with SABER refusal shaping, 131K context via turbo4 KV compression.
    # Scaled to 0 by default — scale up when mining is paused.
    Deployment.llama-server-zephyr-3090-ornstein = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr-3090-ornstein";
          host = "zephyr";
          gpu = "rtx3090";
        };
      spec = {
        replicas = 0;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "llama-server-zephyr-3090-ornstein";
          host = "zephyr";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "llama-server-zephyr-3090-ornstein";
                host = "zephyr";
                gpu = "rtx3090";
              };
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
                command = ["${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/GestaltLabs/Ornstein-Hermes-3.6-27b-SABER-GGUF/Ornstein-Hermes-3.6-27b-SABER-Q5_K_M.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1237"
                  "-ngl"
                  "99"
                  "-c"
                  "131072"
                  "-t"
                  "4"
                  "--flash-attn"
                  "on"
                  "-ctk"
                  "turbo4"
                  "-ctv"
                  "turbo4"
                  "--parallel"
                  "1"
                  "--temp"
                  "0.7"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  NVIDIA_VISIBLE_DEVICES = {
                    name = "NVIDIA_VISIBLE_DEVICES";
                    value = "1";
                  };
                  CUDA_VISIBLE_DEVICES = {
                    name = "CUDA_VISIBLE_DEVICES";
                    value = "0";
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
                };
              };
            };
            volumes = zephyrVolumes;
          };
        };
      };
    };

    Service.llama-server-zephyr-3090-ornstein = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr-3090-ornstein";
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
          app = "llama-server-zephyr-3090-ornstein";
          host = "zephyr";
        };
      };
    };

    # ── Zephyr RTX 3090 Burst — hermes-qwen3.5-35b-a3b MoE (131K ctx) ────────
    # MoE: 35B total / ~3B active per token. 131K context via turbo4 KV compression.
    # Scaled to 0 by default — scale up when mining is paused.
    Deployment.llama-server-zephyr-3090-hermes = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr-3090-hermes";
          host = "zephyr";
          gpu = "rtx3090";
        };
      spec = {
        replicas = 0;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "llama-server-zephyr-3090-hermes";
          host = "zephyr";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "llama-server-zephyr-3090-hermes";
                host = "zephyr";
                gpu = "rtx3090";
              };
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
                command = ["${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/Qwen3.6-35B-A3B-UD-IQ3_S.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1238"
                  "-ngl"
                  "99"
                  "-c"
                  "131072"
                  "-t"
                  "4"
                  "--flash-attn"
                  "on"
                  "-ctk"
                  "turbo4"
                  "-ctv"
                  "turbo4"
                  "--parallel"
                  "1"
                  "--temp"
                  "0.7"
                  "--metrics"
                ];
                env = {
                  _namedlist = true;
                  NVIDIA_VISIBLE_DEVICES = {
                    name = "NVIDIA_VISIBLE_DEVICES";
                    value = "1";
                  };
                  CUDA_VISIBLE_DEVICES = {
                    name = "CUDA_VISIBLE_DEVICES";
                    value = "0";
                  };
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib:/nix/store";
                  };
                };
                ports = [
                  {
                    containerPort = 1238;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = 1238;
                  initialDelaySeconds = 120;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 1238;
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
                };
              };
            };
            volumes = zephyrVolumes;
          };
        };
      };
    };

    Service.llama-server-zephyr-3090-hermes = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr-3090-hermes";
        };
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 1238;
            protocol = "TCP";
            targetPort = 1238;
          }
        ];
        selector = {
          app = "llama-server-zephyr-3090-hermes";
          host = "zephyr";
        };
      };
    };
  };
}
