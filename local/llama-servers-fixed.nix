# LLM inference deployments - llama-server via hostPath /nix/store
#
# Uses minimal scratch image with /nix/store bind-mounted from host.
# The Nix-built llama-server binary runs directly - no Docker image build needed.
# Binary auto-updates when NixOS is rebuilt (reads live /nix/store).
#
# GPU layout:
#   Nexus GPU 0 = RTX 3060 Ti (8GB)  → Qwen3.5-2B-AWQ via vLLM+TurboQuant (port 8040)
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
}:
let
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
  # vLLM+TurboQuant OCI container image
  # Built: local build -> nexus:5000 -> mirrored to GHCR
  vllmImage = "ghcr.io/reverb256/vllm-turboquant:0.20.0";
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
in
{
  config.kubernetes.objects.ai-inference = {
    # ── Zephyr RTX 3090 (GPU 1) — Qwen3.6-35B-A3B MoE ──────────────────────
    #   MoE 35B (3B active) with A3B + IQ4_XS quantization.
    #   Target: /home/j_kro/.lmstudio/models/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf
    # ── Nexus RTX 3060 Ti — Qwen3.5-2B-AWQ via vLLM + TurboQuant (OCI) ───
    # OCI container: ghcr.io/reverb256/vllm-turboquant:0.20.0
    # Contains torch 2.6, vllm 0.8.3, turboquant 0.1.0, flashinfer
    # TurboQuant KV cache compression (k3v4, buffer=128) via monkey-patch
    #
    # Model: /home/j_kro/.lmstudio/models/QuantTrio/Qwen3.5-2B-AWQ
    # Mounted at /models/QuantTrio/Qwen3.5-2B-AWQ
    #
    # Old deployment was scratch+venv (removed); this is the OCI image replacement.
    Deployment.llama-qwen-vllm-nexus = {
      metadata.labels = managed // {
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
            labels = managed // {
              app = "llama-qwen-vllm-nexus";
              host = "nexus";
              gpu = "rtx3060ti";
            };
          };
          spec = {
            nodeName = "nexus";
            hostNetwork = true;
            automountServiceAccountToken = false;
            priorityClassName = "high-priority-ai";
            tolerations = zephyrTolerations;
            containers = {
              _namedlist = true;
              vllm = {
                image = vllmImage;
                imagePullPolicy = "Always";
                command = [ "/bin/bash" ];
                args = [
                  "-c"
                  ''
                    set -e
                    mkdir -p /tmp/vllm-cache /tmp/torch-cache /tmp/triton-cache /tmp/hf-cache 2>/dev/null || true
                    export HOME=/tmp
                    export USER=j_kro
                    export VLLM_CACHE_ROOT=/tmp/vllm-cache
                    export TORCHINDUCTOR_CACHE_DIR=/tmp/torch-cache
                    export TRITON_CACHE_DIR=/tmp/triton-cache
                    export TRANSFORMERS_CACHE=/tmp/hf-cache
                    export HF_HOME=/tmp/hf-cache
                    exec python3 << 'PYEOF'
import os, sys

# Apply turboquant monkey-patch
sys.path.insert(0, "/opt/turboquant")
from turboquant.vllm_attn_backend import enable_no_alloc
enable_no_alloc(key_bits=3, value_bits=4, buffer_size=128)

# Read config from env
max_model_len = int(os.environ.get("VLLM_MAX_MODEL_LEN", "180000"))
gpu_memory_util = float(os.environ.get("VLLM_GPU_MEMORY_UTILIZATION", "0.85"))
lang_only = os.environ.get("VLLM_LANGUAGE_MODEL_ONLY", "true").lower() == "true"

from vllm.entrypoints.openai.api_server import make_arg_parser, run_server
from vllm.utils.argparse_utils import FlexibleArgumentParser

parser = make_arg_parser(FlexibleArgumentParser())
args_list = [
    "--model", "/models/QuantTrio/Qwen3.5-2B-AWQ",
    "--served-model-name", "qwen3.5-2b-awq",
    "--port", "8040",
    "--host", "0.0.0.0",
    "--gpu-memory-utilization", str(gpu_memory_util),
    "--max-num-seqs", "16",
    "--max-model-len", str(max_model_len),
    "--quantization", "awq",
    "--enable-prefix-caching",
    "--performance-mode", "throughput",
    "--no-enable-log-requests",
]
if lang_only:
    args_list.append("--language-model-only")
args = parser.parse_args(args_list)
import asyncio
asyncio.run(run_server(args))
PYEOF
                  ''
                ];
                env = {
                  _namedlist = true;
                  VLLM_WORKER_MULTIPROCESSING_METHOD = {
                    name = "VLLM_WORKER_MULTIPROCESSING_METHOD";
                    value = "spawn";
                  };
                  VLLM_MAX_MODEL_LEN = {
                    name = "VLLM_MAX_MODEL_LEN";
                    value = "180000";
                  };
                  VLLM_LANGUAGE_MODEL_ONLY = {
                    name = "VLLM_LANGUAGE_MODEL_ONLY";
                    value = "true";
                  };
                  VLLM_GPU_MEMORY_UTILIZATION = {
                    name = "VLLM_GPU_MEMORY_UTILIZATION";
                    value = "0.85";
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
                  home-jkro = {
                    mountPath = "/home/j_kro";
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
            volumes = {
              _namedlist = true;
              home-jkro.hostPath = {
                path = "/home/j_kro";
                type = "Directory";
              };
              models.hostPath = {
                path = "/home/j_kro/.lmstudio/models";
                type = "Directory";
              };
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

    Service.llama-qwen-vllm-nexus = {
      metadata.labels = managed // {
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
        selector.app = "llama-qwen-vllm-nexus";
      };
    };

    # ── Zephyr RTX 3090 — Carnice Qwen3.6-MoE-35B-A3B (Primary local model) ──
    # Carnice finetune of Qwen3.6-35B-A3B MoE. IQ4_XS quantization fits 24GB 3090.
    # 256K context via turbo4 KV compression, 16 threads for Zen3 5950X.
    Deployment.llama-server-zephyr-3090-moe = {
      metadata.labels = managed // {
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
            labels = managed // {
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
            tolerations = zephyrTolerations ++ [
              {
                key = "node.kubernetes.io/disk-pressure";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            containers = {
              _namedlist = true;
              llama-server = {
                image = vllmImage;
                imagePullPolicy = "Always";
                command = [ "${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server" ];
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
                  "99"
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
            volumes = zephyrVolumes // {
              _namedlist = true;
              dflash.hostPath.path = "/home/j_kro/.lmstudio/models/dflash";
            };
          };
        };
      };
    };

    Service.llama-server-zephyr-3090-moe = {
      metadata.labels = managed // {
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
          host = "sentry";
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
      metadata.labels = managed // {
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
            labels = managed // {
              app = "llama-server-sentry";
              host = "sentry";
            };
            annotations."nix-csi/discard" = "true";