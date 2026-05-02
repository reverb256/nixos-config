    };

    # ── Zephyr RTX 3060 Ti — Qwen3.5-4B via vLLM (concurrency-optimized) ──────
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
                image = "vllm/vllm-openai:v0.6.6";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "python3"
                  "-m"
                  "vllm.entrypoints.openai.api_server"
                ];
                args = [
                  "--model"
                  "Qwen/Qwen3.5-4B-AWQ"
                  "--port"
                  "8040"
                  "--host"
                  "0.0.0.0"
                  "--dtype"
                  "auto"
                  "--max-model-len"
                  "4096"
                  "--gpu-memory-utilization"
                  "0.9"
                  "--max-num-seqs"
                  "8"
                  "--enforce-eager"
                  "false"
                  "--disable-log-requests"
                  "true"
                  "--seed"
                  "42"
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
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  failureThreshold = 5;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8040;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                securityContext.privileged = true;
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
          app = "llama-qwen-vllm";
          host = "zephyr";
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

    # ── Sentry AMD RX 5600 XT (Vulkan/RADV, gfx1010) — Qwen3-4B-Wrist-On-Hermes ──────