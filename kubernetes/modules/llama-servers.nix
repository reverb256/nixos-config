# LLM inference deployments - llama-server via hostPath /nix/store
#
# Uses minimal scratch image with /nix/store bind-mounted from host.
# The Nix-built llama-server binary runs directly - no Docker image build needed.
# Binary auto-updates when NixOS is rebuilt (reads live /nix/store).
#
# Zephyr GPU layout:
#   GPU 0 = RTX 3060 Ti (8GB)  → Qwen3.5-2B-AWQ via vLLM+TurboQuant (port 8040)
#   GPU 1 = RTX 3090 (24GB)    → 35B MoE model (port 1235, coordinator-monitored)
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
    #   Target: /home/j_kro/.lmstudio/models/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf
    Deployment.llama-server-zephyr = {
      metadata.labels =
        managed
        // {
          app = "llama-server-zephyr";
          host = "zephyr";
          gpu = "rtx3090";
        };
      spec = {
        replicas = 0;
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
                  "/home/j_kro/.lmstudio/models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1235"
                  "-ngl"
                  "99"
                  "-c"
                  "131072"
                  "-t"
                  "12"
                  "--flash-attn"
                  "on"
                  "-ctk"
                  "q8_0"
                  "-ctv"
                  "turbo4"
                  "--temp"
                  "0.0"
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
                    value = "$\{pkgsWithOverlay.llama-cpp-turboquant\}/lib:/run/opengl-driver/lib";
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
                    mountPath = "/home/j_kro/.lmstudio/models";
                    readOnly = true;
                  };
                  # dflash volume removed — draft model is in /models (already mounted)
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

    # ── Zephyr RTX 3060 Ti — Qwen3.5-2B-AWQ via vLLM + TurboQuant ──────
    # Scratch container with host mounts: venv python (torch 2.10, vllm 0.19.1)
    # + TurboQuant KV cache compression (key_bits=3, value_bits=4).
    # Startup script sets CUDA_DEVICE_ORDER=PCI_BUS_ID + CUDA_VISIBLE_DEVICES=0
    # (PCI bus 0 = 3060Ti by address order).
    #
    # Required host mounts beyond standard /nix + nvidia-libs:
    #   /home/j_kro        — venv + startup script + models (ro)
    #   /data/.../Python   — venv python symlink target (ro)
    #   /data/.../turboquant — TurboQuant source (ro)
    #   /lib64             — ELF interpreter (nix-ld) for FHS python
    #   /lib               — kernel modules
    #   USER=j_kro         — torch getpass.getuser() fails as uid 0
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
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgs.bash}/bin/bash"];
                args = [
                  "-c"
                  ''
                    export LD_LIBRARY_PATH=/run/opengl-driver/lib:/nix/store:/run/current-system/sw/lib
                    export PYTHONPATH=/data/projects/own/turboquant
                    export HOME=/tmp
                    export USER=j_kro
                    export VLLM_CACHE_ROOT=/tmp/vllm-cache
                    export TORCHINDUCTOR_CACHE_DIR=/tmp/torch-cache
                    export TRITON_CACHE_DIR=/tmp/triton-cache
                    export TRANSFORMERS_CACHE=/tmp/hf-cache
                    export HF_HOME=/tmp/hf-cache
                    export CC=/run/current-system/sw/bin/gcc
                    /nix/store/*coreutils*/bin/mkdir -p /tmp/vllm-cache /tmp/torch-cache /tmp/triton-cache /tmp/hf-cache 2>/dev/null || true
                    exec /home/j_kro/vllm-env/bin/python3 /home/j_kro/vllm-start-tq.sh
                  ''
                ];
                env = {
                  _namedlist = true;
                  PATH = {
                    name = "PATH";
                    value = "/run/current-system/sw/bin:/usr/bin:/bin";
                  };
                  VLLM_WORKER_MULTIPROCESSING_METHOD = {
                    name = "VLLM_WORKER_MULTIPROCESSING_METHOD";
                    value = "spawn";
                  };
                };
                resources = {
                  requests = {
                    cpu = "2";
                    memory = "6Gi";
                  };
                  limits = {
                    cpu = "4";
                    memory = "10Gi";
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
                  home-jkro = {
                    mountPath = "/home/j_kro";
                    readOnly = true;
                  };
                  turboquant = {
                    mountPath = "/data/projects/own/turboquant";
                    readOnly = true;
                  };
                  python-runtime = {
                    mountPath = "/data/AI/Assets/Python";
                    readOnly = true;
                  };
                  nix-sw = {
                    mountPath = "/run/current-system/sw";
                    readOnly = true;
                  };
                  lib64 = {
                    mountPath = "/lib64";
                  };
                  lib = {
                    mountPath = "/lib";
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
            volumes = {
              _namedlist = true;
              nix.hostPath = {
                path = "/nix";
                type = "Directory";
              };
              nvidia-libs.hostPath.path = "/run/opengl-driver/lib";
              home-jkro.hostPath = {
                path = "/home/j_kro";
                type = "Directory";
              };
              turboquant.hostPath = {
                path = "/data/projects/own/turboquant";
                type = "Directory";
              };
              python-runtime.hostPath = {
                path = "/data/AI/Assets/Python";
                type = "Directory";
              };
              nix-sw.hostPath = {
                path = "/run/current-system/sw";
                type = "Directory";
              };
              lib64.hostPath.path = "/lib64";
              lib.hostPath.path = "/lib";
              tmp.hostPath = {
                path = "/tmp";
                type = "Directory";
              };
              etc.hostPath = {
                path = "/etc";
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
        replicas = 0;
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
            tolerations =
              zephyrTolerations
              ++ [
                {
                  key = "node.kubernetes.io/disk-pressure";
                  operator = "Exists";
                  effect = "NoSchedule";
                }
              ];
            containers = {
              _namedlist = true;
              llama-server = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server"];
                args = [
                  "--model"
                  "/models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1237"
                  "-ngl"
                  "99"
                  "-c"
                  "131072"
                  "-t"
                  "16"
                  "--flash-attn"
                  "on"
                  "-ctk"
                  "turbo4"
                  "-ctv"
                  "turbo4"
                  "--parallel"
                  "4"
                  "--metrics"
                  "-b"
                  "256"
                  "--no-mmap"
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
                  dflash = {
                    mountPath = "/dflash";
                    readOnly = true;
                  };
                };
              };
            };
            volumes =
              zephyrVolumes
              // {
                _namedlist = true;
                dflash.hostPath.path = "/home/j_kro/.lmstudio/models/dflash";
              };
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
                  "/models/Qwen3.6-27B-Q4_K_M.gguf"
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
                  "--metrics"
                  "-b"
                  "256"
                  "-ub"
                  "64"
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


    };

    # ── Zephyr RTX 3090 Burst ── DFlash Speculative Decoding (Qwen3.6-27B) ──
    # Lucebox DFlash: speculative decoding with DDTree draft verification.
    # Expected ~2-4x throughput vs autoregressive (69-78 tok/s vs 31 tok/s).
    # Uses test_dflash binary + OpenAI-compatible server.py from lucebox-hub.
    # Scaled to 0 by default ── scale up when mining is paused (shares GPU with dense).
    Deployment.dflash-zephyr-3090 = {
      metadata.labels =
        managed
        // {
          app = "dflash-zephyr-3090";
          host = "zephyr";
          gpu = "rtx3090";
        };
      spec = {
        replicas = 0;
        revisionHistoryLimit = 1;
        selector.matchLabels = {
          app = "dflash-zephyr-3090";
          host = "zephyr";
        };
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "dflash-zephyr-3090";
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
              dflash-server = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["/nix/store/nixpkgs/path/bin/bash"];
                args = [
                  "-c"
                  ''
                    export LD_LIBRARY_PATH=/run/opengl-driver/lib:/nix/store:/run/current-system/sw/lib
                    export HOME=/tmp
                    export USER=j_kro
                    export TRANSFORMERS_CACHE=/tmp/hf-cache
                    export HF_HOME=/tmp/hf-cache
                    export HF_TOKEN=$(cat /run/agenix/huggingface-token 2>/dev/null || echo "")
                    /nix/store/*coreutils*/bin/mkdir -p /tmp/hf-cache 2>/dev/null || true
                    exec /home/j_kro/vllm-env/bin/python3 /home/j_kro/lucebox-hub/dflash/scripts/server.py \
                      --host 0.0.0.0 \
                      --port 1239 \
                      --target /models/Qwen3.6-27B-Q4_K_M.gguf \
                      --draft /models/draft \
                      --bin /home/j_kro/lucebox-hub/dflash/build/test_dflash \
                      --budget 22 \
                      --max-ctx 16384 \
                      --ctk tq3_0 \
                      --ctv tq3_0
                  ''
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
                    value = "/run/opengl-driver/lib:/nix/store:/run/current-system/sw/lib";
                  };
                };
                ports = [
                  {
                    containerPort = 1239;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 1239;
                  };
                  initialDelaySeconds = 180;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  tcpSocket.port = 1239;
                  initialDelaySeconds = 120;
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
                  nix-sw = {
                    mountPath = "/run/current-system/sw";
                    readOnly = true;
                  };
                  home-jkro = {
                    mountPath = "/home/j_kro";
                    readOnly = true;
                  };
                  models = {
                    mountPath = "/models";
                    readOnly = true;
                  };
                  etc = {
                    mountPath = "/etc";
                    readOnly = true;
                  };
                  lib = {
                    mountPath = "/lib";
                    readOnly = true;
                  };
                  lib64 = {
                    mountPath = "/lib64";
                    readOnly = true;
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
              };
            };
            volumes = zephyrVolumes;
          };
        };
      };
    };

    Service.dflash-zephyr-3090 = {
      metadata.labels =
        managed
        // {
          app = "dflash-zephyr-3090";
        };
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 1239;
            protocol = "TCP";
            targetPort = 1239;
          }
        ];
        selector = {
          app = "dflash-zephyr-3090";
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
        replicas = 0;
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
                  "/models/unsloth/Qwen3.5-4B-GGUF/Qwen3.5-4B-Q4_K_M.gguf"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "1235"
                  "-ngl"
                  "99"
                  "-c"
                  "131072"
                  "-t"
                  "4"
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
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib:/nix/store";
                  };
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
                  "/models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf"
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
