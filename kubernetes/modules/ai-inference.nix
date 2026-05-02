{
  pkgs,
  pkgsWithOverlay,
  inputs,
  lib,
  ...
}: let
  # nix-csi scratch image (proven pattern from llama-servers)
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";

  # AI Inference Gateway — pre-built container image (loaded into containerd on target node)
  gatewayImage = "docker.io/library/ai-inference-gateway:2.4.9";

  # Managed-by labels for easykubenix
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  # AI Inference Gateway — derive paths from flake input, not hardcoded store paths
  gatewayPkg = inputs.ai-gateway.packages.x86_64-linux.ai-inference-gateway;
  gatewayEnv = pkgs.python313.withPackages (_ps: [gatewayPkg]);
  gatewaySitePackages = "${gatewayEnv}/${gatewayEnv.python.sitePackages}";
in {
  config.kubernetes.objects.ai-inference = {
    ServiceAccount.default = {};
    ServiceAccount.ai-inference-gateway = {};
    ServiceAccount.open-webui = {};
    ServiceAccount.prometheus = {};
    ServiceAccount.n8n-sa.automountServiceAccountToken = false;

    ConfigMap.ai-gateway-config.data = {
      AUTH_MODE = "none";
      BACKEND_TYPE = "llama-cpp";
      BACKEND_URL = "http://llama-server-zephyr-3090-moe.ai-inference.svc.cluster.local:1237";
      DEFAULT_MODEL = "Qwen3.6-35B-A3B-UD-IQ3_S.gguf";
      RAG_ENABLED = "true";
      RAG_TOP_K = "5";
      QDRANT_URL = "http://qdrant.ai-inference.svc.cluster.local:6333";
      HYBRID_SEARCH_ENABLED = "true";
      EMBEDDING_MODEL = "BidirLM/BidirLM-Omni-2.5B-Embedding";
      EMBEDDING_DIMENSIONS = "2048";
      EMBEDDING_TRUST_REMOTE_CODE = "true";
      BM25_WEIGHT = "0.300000";
      CHUNK_OVERLAP = "50";
      CHUNK_SIZE = "512";
    };

    ConfigMap.ai-inference-gateway-config.data = {
      AUTH_MODE = "api-key";
      BACKEND_TYPE = "zai";
      BACKEND_URL = "https://api.z.ai/api/coding/paas/v4";
      BACKEND_FALLBACK_URLS = "https://text.pollinations.ai,https://api.kilo.ai/api/gateway";
      DEFAULT_MODEL = "glm-5-turbo";
      GATEWAY_HOST = "0.0.0.0";
      PORT = "8080";
      PYTHONUNBUFFERED = "1";
      ROUTING_ENABLED = "true";
      RATE_LIMIT_ENABLED = "true";
      RATE_LIMIT_RPM = "120";
      SECURITY_PROXY_ENABLED = "false";
      SENTRY_ENABLED = "false";
      QDRANT_URL = "http://qdrant.ai-inference.svc.cluster.local:6333";
      RAG_ENABLED = "true";
      RAG_TOP_K = "10";
      HYBRID_SEARCH_ENABLED = "true";
      EMBEDDING_MODEL = "BidirLM/BidirLM-Omni-2.5B-Embedding";
      EMBEDDING_DEVICE = "cpu";
      EMBEDDING_DIMENSIONS = "2048";
      EMBEDDING_TRUST_REMOTE_CODE = "true";
      BM25_WEIGHT = "0.3";
      CHUNK_OVERLAP = "50";
      CHUNK_SIZE = "512";
      MCP_ENABLED = "true";
      SYSTEM_PROMPTS_ENABLED = "true";
      TOKEN_SCOPED_COLLECTIONS = "true";
      VECTOR_WEIGHT = "0.7";
      HF_HOME = "/home/j_kro/.cache/huggingface";
      HF_HUB_OFFLINE = "0";
      HF_HUB_ENABLE_HF_TRANSFER = "1";
      HF_HUB_CACHE = "/home/j_kro/.cache/huggingface/hub";
      HF_HUB_DISABLE_TELEMETRY = "1";
      HF_HUB_UPDATE_CHECK_DISABLED = "1";
      TRANSFORMERS_CACHE = "/home/j_kro/.cache/huggingface";
      CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      MAX_REQUEST_SIZE = "10485760";
      CIRCUIT_BREAKER_ENABLED = "true";
      REDIS_URL = "redis://redis-service.ai-inference.svc.cluster.local:6379";
      SECONDARY_BACKEND_URL = "http://10.1.1.110:1237";
      SECONDARY_BACKEND_MODEL = "Qwen3.6-35B-A3B-UD-IQ3_S.gguf";
      DISCOVERY_BACKENDS = "[{"name":"vllm-3060ti","base_url":"http://10.1.1.110:8040/v1","priority":12}]";
      PRIVACY_FILTER_URL = "http://privacy-filter.ai-inference.svc.cluster.local:8081";
      PRIVACY_FILTER_ENABLED = "false";
      MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_URL = "http://searxng.search.svc.cluster.local:8080";
      MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_MAX_RESULTS = "10";
      MIDDLEWARE__KNOWLEDGE_FABRIC__RRF_K = "60";
      MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_PATHS = "[\"/etc/nixos\"]";
      MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_TOP_K = "10";
    };

    ConfigMap.prometheus-config.data."prometheus.yml" = ''
      global:
        scrape_interval: 15s
        evaluation_interval: 15s
        external_labels:
          cluster: nixos-k8s
          environment: production

      scrape_configs:
        - job_name: ai-gateway
          static_configs:
            - targets:
                - ai-gateway:8080
              labels:
                app: ai-gateway
                component: gateway

        - job_name: llamacpp
          static_configs:
            - targets:
                - zephyr:9400
              labels:
                app: llamacpp
                component: inference
    '';

    Deployment.open-webui = {
      metadata.labels.app = "open-webui";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "open-webui";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata.labels.app = "open-webui";
          spec = {
            serviceAccountName = "open-webui";
            nodeSelector."kubernetes.io/hostname" = "sentry";
            hostAliases = [{ ip = "10.1.1.100"; hostnames = ["auth.lan" "openwebui.lan"]; }];
            containers = {
              _namedlist = true;
              open-webui = {
                image = "ghcr.io/open-webui/open-webui:0.6.5";
                imagePullPolicy = "IfNotPresent";
                env = {
                  _namedlist = true;
                  OLLAMA_BASE_URLS = {
                    name = "OLLAMA_BASE_URLS";
                    value = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
                  }; # AI inference gateway
                  ENABLE_OLLAMA = {
                    name = "ENABLE_OLLAMA";
                    value = "true";
                  };
                  ENABLE_OPENAI_API = {
                    name = "ENABLE_OPENAI_API";
                    value = "true";
                  };
                  ENABLE_LLM = {
                    name = "ENABLE_LLM";
                    value = "true";
                  };
                  ENABLE_SIGNUP = {
                    name = "ENABLE_SIGNUP";
                    value = "true";
                  };
                  ENABLE_LDAP_LOGIN = {
                    name = "ENABLE_LDAP_LOGIN";
                    value = "false";
                  };
                  OPENAI_API_BASE_URL = {
                    name = "OPENAI_API_BASE_URL";
                    value = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
                  };
                };
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 8080;
                  };
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = 8080;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  webui-data = {
                    mountPath = "/app/backend/data";
                  };
                };
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "768Mi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "3Gi";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              webui-data = {
                hostPath = {
                  path = "/storage/open-webui";
                  type = "DirectoryOrCreate";
                };
              };
            };
          };
        };
      };
    };

    Service.open-webui = {
      metadata.labels.app = "open-webui";
      spec = {
        type = "NodePort";
        ports = [
          {
            name = "http";
            port = 8080;
            protocol = "TCP";
            targetPort = 8080;
            nodePort = 32080;
          }
        ];
        selector.app = "open-webui";
      };
    };

    Role.n8n-role.rules = [
      {
        apiGroups = [""];
        resources = [
          "configmaps"
          "secrets"
          "persistentvolumeclaims"
        ];
        verbs = [
          "get"
          "list"
          "watch"
          "create"
          "update"
        ];
      }
    ];

    RoleBinding.n8n-rolebinding = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "Role";
        name = "n8n-role";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "n8n-sa";
        }
      ];
    };

    # Gateway needs ConfigMap access for GPU scheduler state (gpu_scheduler.py writes to kube-system)
    ClusterRole.ai-inference-gateway-configmap.rules = [
      {
        apiGroups = [""];
        resources = ["configmaps"];
        verbs = [
          "get"
          "list"
          "watch"
          "create"
          "update"
          "patch"
        ];
      }
    ];

    ClusterRoleBinding.ai-inference-gateway-configmap = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "ai-inference-gateway-configmap";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "ai-inference-gateway";
          namespace = "ai-inference";
        }
      ];
    };

    # ── AI Inference Gateway ──────────────────────────────────────
    # Runs as systemd service on nexus (10.1.1.120:8080).
    # Exposed to K8s via Endpoints so pods can reach it at:
    #   ai-inference-gateway.ai-inference.svc.cluster.local:8080
    #
    # The gateway provides:
    #   - OpenAI/Anthropic/Ollama-compatible API
    #   - Intelligent routing (model specialization, latency-aware)
    #   - Circuit breaker + fallback to Z.AI/Pollinations/NIM
    #   - RAG via Qdrant hybrid search (vector + BM25)
    #   - MCP broker (SearXNG, etc.)
    #   - Security filter (rate limiting, PII redaction)
    #   - Knowledge Fabric middleware (SearXNG + RAG + brain wiki)

    Service.ai-inference-gateway = {
      metadata.labels =
        managed
        // {
          app = "ai-inference-gateway";
        };
      spec = {
        type = "ClusterIP";
        ipFamilyPolicy = "SingleStack";
        selector.app = "ai-inference-gateway";
        ports = [
          {
            name = "http";
            port = 8080;
            protocol = "TCP";
            targetPort = 8080;
          }
        ];
      };
    };

    # AI Inference Gateway - migrated from systemd to K8s
    # Uses nix-csi scratch pattern (proven with llama-servers)
    Deployment.ai-inference-gateway = {
      metadata.labels =
        managed
        // {
          app = "ai-inference-gateway";
          component = "gateway";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "ai-inference-gateway";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 1;
            maxUnavailable = 0;
          };
        };
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "ai-inference-gateway";
                component = "gateway";
              };
          };
          spec = {
            nodeName = "nexus"; # Non-infrastructure workloads default to Nexus (46GB RAM)
            hostNetwork = false;
            serviceAccountName = "ai-inference-gateway";
            automountServiceAccountToken = true; # needed by gpu_scheduler.py kubectl calls
            containers = {
              _namedlist = true;
              ai-gateway = {
                image = gatewayImage;
                imagePullPolicy = "IfNotPresent";
                # Container image has default Cmd: python -m uvicorn ... --workers 4
                # Override workers to 1 for stability
                command = [
                  "python"
                  "-m"
                  "uvicorn"
                  "ai_inference_gateway.main:app"
                  "--host"
                  "0.0.0.0"
                  "--port"
                  "8080"
                  "--workers"
                  "1"
                  "--log-level"
                  "info"
                ];
                env = {
                  _namedlist = true;
                  AUTH_MODE.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "AUTH_MODE";
                  };
                  BACKEND_TYPE.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "BACKEND_TYPE";
                  };
                  BACKEND_URL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "BACKEND_URL";
                  };
                  BACKEND_FALLBACK_URLS.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "BACKEND_FALLBACK_URLS";
                  };
                  DEFAULT_MODEL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "DEFAULT_MODEL";
                  };
                  PORT.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "PORT";
                  };
                  PYTHONUNBUFFERED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "PYTHONUNBUFFERED";
                  };
                  QDRANT_URL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "QDRANT_URL";
                  };
                  ROUTING_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "ROUTING_ENABLED";
                  };
                  CIRCUIT_BREAKER_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "CIRCUIT_BREAKER_ENABLED";
                  };
                  RATE_LIMIT_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "RATE_LIMIT_ENABLED";
                  };
                  RAG_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "RAG_ENABLED";
                  };
                  EMBEDDING_MODEL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "EMBEDDING_MODEL";
                  };
                  EMBEDDING_DEVICE.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "EMBEDDING_DEVICE";
                  };
                  EMBEDDING_DIMENSIONS.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "EMBEDDING_DIMENSIONS";
                  };
                  EMBEDDING_TRUST_REMOTE_CODE.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "EMBEDDING_TRUST_REMOTE_CODE";
                  };
                  MCP_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MCP_ENABLED";
                  };
                  REDIS_URL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "REDIS_URL";
                  };
                  CURL_CA_BUNDLE.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "CURL_CA_BUNDLE";
                  };
                  HF_HOME.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "HF_HOME";
                  };
                  HF_HUB_OFFLINE.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "HF_HUB_OFFLINE";
                  };
                  HF_HUB_ENABLE_HF_TRANSFER.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "HF_HUB_ENABLE_HF_TRANSFER";
                  };
                  TRANSFORMERS_CACHE.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "TRANSFORMERS_CACHE";
                  };
                  SECONDARY_BACKEND_URL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "SECONDARY_BACKEND_URL";
                  };
                  SECONDARY_BACKEND_MODEL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "SECONDARY_BACKEND_MODEL";
                  };
                  DISCOVERY_BACKENDS.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "DISCOVERY_BACKENDS";
                  };
                  SSL_CERT_FILE.value = "/etc/ssl/certs/ca-bundle.crt";
                  REQUESTS_CA_BUNDLE.value = "/etc/ssl/certs/ca-bundle.crt";
                  HF_TOKEN.valueFrom.secretKeyRef = {
                    name = "hf-token";
                    key = "token";
                  };
                  USER.value = "nobody";
                  HOME.value = "/tmp";
                  TORCH_HOME.value = "/tmp/.torch";
                  TORCHINDUCTOR_CACHE_DIR.value = "/tmp/.torch/inductor";
                  LOG_LEVEL.value = "INFO";
                  PYTHONPATH.value = "/app";
                  PATH.value = "/bin:/usr/bin";
                  SEARXNG_URL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_URL";
                  };
                  ZAI_API_KEY.valueFrom.secretKeyRef = {
                    name = "zai-api-key";
                    key = "ZAI_API_KEY";
                  };
                  NVIDIA_API_KEY.valueFrom.secretKeyRef = {
                    name = "nvidia-api-key";
                    key = "NVIDIA_API_KEY";
                  };
                  NVIDIA_NIM_API_KEY.valueFrom.secretKeyRef = {
                    name = "nvidia-api-key";
                    key = "NVIDIA_API_KEY";
                  };
                  OPENROUTER_API_KEY.valueFrom.secretKeyRef = {
                    name = "openrouter-api-key";
                    key = "OPENROUTER_API_KEY";
                  };
                  POLLINATIONS_API_KEY.valueFrom.secretKeyRef = {
                    name = "pollinations-api-key";
                    key = "POLLINATIONS_API_KEY";
                  };
                  KILO_API_KEY.valueFrom.secretKeyRef = {
                    name = "kilo-api-key";
                    key = "KILO_API_KEY";
                  };
                  OPENCODE_API_KEY.valueFrom.secretKeyRef = {
                    name = "opencode-api-key";
                    key = "OPENCODE_API_KEY";
                  };
                  MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED";
                  };
                  MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_ENABLED";
                  };
                  MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_URL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_URL";
                  };
                  MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_MAX_RESULTS.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_MAX_RESULTS";
                  };
                  MIDDLEWARE__KNOWLEDGE_FABRIC__RRF_K.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__RRF_K";
                  };
                  MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_ENABLED";
                  };
                  MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_ENABLED";
                  };
                  MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_TOP_K.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_TOP_K";
                  };
                };
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "2Gi";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8080;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8080;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  "hf-cache" = {
                    mountPath = "/home/j_kro/.cache/huggingface";
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                  ai-memory = {
                    mountPath = "/run/ai-inference/memory";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              hf-cache.hostPath = {
                path = "/home/j_kro/.cache/huggingface";
                type = "Directory";
              };
              tmp.emptyDir = {};
              ai-memory.emptyDir = {};
            };
          };
        };
      };
    };


    # ── Gateway HPA ───────────────────────────────────────────
    HorizontalPodAutoscaler.ai-inference-gateway-hpa = {
      spec = {
        scaleTargetRef = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          name = "ai-inference-gateway";
        };
        minReplicas = 1;
        maxReplicas = 3;
        metrics = [
          {
            type = "Resource";
            resource = {
              name = "cpu";
              target = {
                type = "Utilization";
                averageUtilization = 70;
              };
            };
          }
          {
            type = "Resource";
            resource = {
              name = "memory";
              target = {
                type = "Utilization";
                averageUtilization = 80;
              };
            };
          }
        ];
      };
    };
    # ── NetworkPolicies ────────────────────────────────────────
    NetworkPolicy.default-deny = {
      spec = {
        podSelector = {};
        policyTypes = [
          "Ingress"
          "Egress"
        ];
      };
    };
    NetworkPolicy.allow-internal = {
      spec = {
        podSelector = {};
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        ingress = [{from = [{namespaceSelector.matchLabels.name = "ai-inference";}];}];
        egress = [
          {to = [{namespaceSelector.matchLabels.name = "ai-inference";}];}
          {
            to = [
              {
                namespaceSelector = {};
                podSelector.matchLabels."k8s-app" = "kube-dns";
              }
            ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
          {
            to = [{podSelector.matchLabels.app = "privacy-filter";}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
        ];
      };
    };

    # Qdrant vector database — migrated from systemd to K8s StatefulSet
    Deployment.qdrant = {
      metadata.labels.app = "qdrant";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "qdrant";
        strategy.type = "Recreate";
        template = {
          metadata.labels.app = "qdrant";
          spec = {
            nodeName = "sentry";
            containers = [
              {
                name = "qdrant";
                image = "docker.io/qdrant/qdrant:v1.13.4";
                ports = [
                  {
                    containerPort = 6333;
                    name = "http";
                  }
                  {
                    containerPort = 6334;
                    name = "grpc";
                  }
                ];
                volumeMounts = [
                  {
                    name = "qdrant-data";
                    mountPath = "/qdrant/storage";
                  }
                ];
                resources = {
                  requests.memory = "1Gi";
                  limits.memory = "4Gi";
                };
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 6333;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 6333;
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 20;
                };
              }
            ];
            volumes = [
              {
                name = "qdrant-data";
                hostPath = {
                  path = "/storage/qdrant";
                  type = "DirectoryOrCreate";
                };
              }
            ];
          };
        };
      };
    };

    # ── LimitRange ───────────────────────────────────────────────
    # No GPU in default/defaultRequest/max — prevents auto-injection
    # GPU workloads must explicitly request GPUs in their deployment specs
    LimitRange.ai-inference-limits = {
      metadata.labels.app = "gpu-scheduler";
      spec.limits = [
        {
          type = "Container";
          default = {
            cpu = "2";
            memory = "4Gi";
          };
          defaultRequest = {
            cpu = "500m";
            memory = "1Gi";
          };
          max = {
            cpu = "8";
            memory = "16Gi";
          };
          min = {
            cpu = "100m";
            memory = "128Mi";
          };
          maxLimitRequestRatio = {
            cpu = "10";
            memory = "4";
          };
        }
      ];
    };

    # ── Knowledge Fabric API ─────────────────────────────────────
    Deployment.knowledge-fabric-api = {
      metadata.labels = {
        app = "knowledge-fabric-api";
        component = "brain";
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "knowledge-fabric-api";
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            app = "knowledge-fabric-api";
            component = "brain";
          };
          spec = {
            nodeName = "nexus";
            automountServiceAccountToken = false;
            containers = [
              {
                name = "api";
                image = "python:3.12-slim";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "python3"
                  "-c"
                  # Knowledge Fabric API stub - RRF middleware runs in gateway
                  ''
                    from http.server import HTTPServer, BaseHTTPRequestHandler
                    import json
                    class Handler(BaseHTTPRequestHandler):
                      def do_GET(self):
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/json')
                        self.end_headers()
                        self.wfile.write(b'{"status": "healthy", "service": "knowledge-fabric-api"}')
                      def do_POST(self):
                        if self.path == '/brain/query':
                          content_length = int(self.headers.get('Content-Length', 0))
                          body = self.rfile.read(content_length).decode() if content_length else '{}'
                          self.send_response(200)
                          self.send_header('Content-Type', 'application/json')
                          self.end_headers()
                          response = {"results": [], "status": "ready", "note": "RRF handled by gateway middleware"}
                          self.wfile.write(json.dumps(response).encode())
                        else:
                          self.send_response(404)
                          self.end_headers()
                      def log_message(self, format, *args):
                        print(f"[brain] {format % args}")
                    print("Starting Knowledge Fabric API on port 3000")
                    HTTPServer(('0.0.0.0', 3000), Handler).serve_forever()
                  ''
                ];
                ports = [
                  {
                    containerPort = 3000;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "200m";
                    memory = "128Mi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = 3000;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
              }
            ];
            tolerations = [
              {
                key = "workstation";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              }
              {
                key = "interactive";
                operator = "Equal";
                value = "true";
                effect = "NoExecute";
              }
            ];
          };
        };
      };
    };

    Service.knowledge-fabric-api = {
      metadata.labels.app = "knowledge-fabric-api";
      spec = {
        type = "ClusterIP";
        selector.app = "knowledge-fabric-api";
        ports = [
          {
            name = "http";
            port = 3000;
            protocol = "TCP";
            targetPort = 3000;
          }
        ];
      };
    };

    # ── Embed Server removed: gateway handles embeddings via BidirLM ──
    # Previously: HuggingFace TEI (nomic-embed-text-v2-moe) with CUDA driver
    # mismatch (compat layer 575.x vs host 595.x). Replaced by built-in
    # BidirLM-Omni-2.5B-Embedding endpoint at /v1/embeddings.

    # ── llama-server (Qwen on Nexus) ─────────────────────────────
    Deployment.llama-server = {
      metadata.labels = {
        app = "llama-cpp";
        purpose = "llm-inference";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "llama-cpp";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata.labels.app = "llama-cpp";
          spec = {
            nodeName = "nexus";
            hostNetwork = true;
            containers = [
              {
                name = "llama-server";
                image = "alpine:3.21";
                command = ["/run/current-system/sw/bin/llama-server"];
                args = [
                  "--model=/models/Qwen3.5-0.8B.Q8_0.gguf"
                  "--host=0.0.0.0"
                  "--port=8080"
                  "--ctx-size=16384"
                  "--threads=16"
                  "--metrics"
                ];
                env = [
                  {
                    name = "CUDA_VISIBLE_DEVICES";
                    value = "";
                  }
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 8080;
                    hostPort = 8080;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "2";
                    memory = "2Gi";
                  };
                  limits = {
                    cpu = "8";
                    memory = "4Gi";
                  };
                };
                volumeMounts = [
                  {
                    name = "models";
                    mountPath = "/models";
                    readOnly = true;
                  }
                  {
                    name = "nixos-bin";
                    mountPath = "/run/current-system/sw/bin";
                    readOnly = true;
                  }
                  {
                    name = "nixos-lib";
                    mountPath = "/run/current-system/sw/lib";
                    readOnly = true;
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8080;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8080;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                };
              }
            ];
            volumes = [
              {
                name = "models";
                hostPath = {
                  path = "/home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF";
                  type = "Directory";
                };
              }
              {
                name = "nixos-bin";
                hostPath = {
                  path = "/run/current-system/sw/bin";
                  type = "Directory";
                };
              }
              {
                name = "nixos-lib";
                hostPath = {
                  path = "/run/current-system/sw/lib";
                  type = "Directory";
                };
              }
            ];
          };
        };
      };
    };

    Service.llama-server = {
      metadata.labels.app = "llama-server";
      spec = {
        type = "ClusterIP";
        selector.app = "llama-server";
        ports = [
          {
            port = 8080;
            targetPort = 8080;
            protocol = "TCP";
            name = "http";
          }
        ];
      };
    };

    # ── llama-cpp-qwen Service+Endpoints (Nexus hostNetwork) ─────
    Service.llama-cpp-qwen = {
      metadata.labels.app = "llama-cpp";
      spec = {
        type = "ClusterIP";
        ports = [
          {
            port = 8080;
            targetPort = 8080;
            protocol = "TCP";
            name = "http";
          }
          {
            port = 9090;
            targetPort = 9090;
            protocol = "TCP";
            name = "metrics";
          }
        ];
      };
    };

    Endpoints.llama-cpp-qwen = {
      metadata.labels.app = "llama-cpp";
      subsets = [
        {
          addresses = [{ip = "10.1.1.120";}];
          ports = [
            {
              port = 8080;
              name = "http";
              protocol = "TCP";
            }
            {
              port = 9090;
              name = "metrics";
              protocol = "TCP";
            }
          ];
        }
      ];
    };

    # ── MCP Gateway Proxy removed (was forwarding localhost:8080 -> embed-server:30880) ──

    # ── Redis for AI Gateway ─────────────────────────────────────
    Deployment.redis = {
      metadata.labels.app = "redis";
      spec = {
        replicas = 1;
        selector.matchLabels.app = "redis";
        template = {
          metadata.labels.app = "redis";
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            containers = [
              {
                name = "redis";
                image = "redis:7-alpine";
                command = [
                  "redis-server"
                  "--save"
                  ""
                  "--appendonly"
                  "no"
                ];
                args = [
                  "--maxmemory"
                  "256mb"
                  "--maxmemory-policy"
                  "allkeys-lru"
                ];
                ports = [
                  {
                    containerPort = 6379;
                    name = "redis";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
                volumeMounts = [
                  {
                    name = "redis-data";
                    mountPath = "/data";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "redis-data";
                emptyDir.sizeLimit = "512Mi";
              }
            ];
          };
        };
      };
    };

    Service.redis-service = {
      metadata.labels.app = "redis";
      spec = {
        type = "ClusterIP";
        selector.app = "redis";
        ports = [
          {
            port = 6379;
            targetPort = 6379;
            name = "redis";
          }
        ];
      };
    };

    # ── Observability (Prometheus + Grafana) ─────────────────────
    ServiceAccount.grafana-sa.automountServiceAccountToken = false;

    ClusterRole.prometheus.rules = [
      {
        apiGroups = [""];
        resources = [
          "nodes"
          "nodes/proxy"
          "services"
          "endpoints"
          "pods"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        nonResourceURLs = ["/metrics"];
        verbs = ["get"];
      }
    ];

    ClusterRoleBinding.prometheus = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "prometheus";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "prometheus";
          namespace = "ai-inference";
        }
      ];
    };

    Deployment.prometheus = {
      metadata.labels.app = "prometheus";
      spec = {
        replicas = 1;
        selector.matchLabels.app = "prometheus";
        template = {
          metadata.labels.app = "prometheus";
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            serviceAccountName = "prometheus";
            containers = [
              {
                name = "prometheus";
                image = "prom/prometheus:v2.53.0";
                args = [
                  "--config.file=/etc/prometheus/prometheus.yml"
                  "--storage.tsdb.path=/prometheus"
                  "--web.console.libraries=/etc/prometheus/console_libraries"
                  "--web.console.templates=/etc/prometheus/consoles"
                  "--storage.tsdb.retention.time=30d"
                  "--web.enable-lifecycle"
                ];
                ports = [
                  {
                    containerPort = 9090;
                    name = "http";
                  }
                ];
                env = [
                  {
                    name = "POD_IP";
                    valueFrom.fieldRef.fieldPath = "status.podIP";
                  }
                ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/prometheus";
                  }
                  {
                    name = "storage";
                    mountPath = "/prometheus";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/-/healthy";
                    port = 9090;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/-/ready";
                    port = 9090;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 5;
                };
                resources = {
                  requests = {
                    cpu = "200m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "1";
                    memory = "2Gi";
                  };
                };
              }
            ];
            volumes = [
              {
                name = "config";
                configMap.name = "prometheus-config";
              }
              {
                name = "storage";
                emptyDir.sizeLimit = "4Gi";
              }
            ];
          };
        };
      };
    };

    Service.prometheus = {
      metadata.labels.app = "prometheus";
      spec = {
        type = "ClusterIP";
        selector.app = "prometheus";
        ports = [
          {
            port = 9090;
            targetPort = 9090;
            name = "http";
          }
        ];
      };
    };

    Deployment.grafana = {
      metadata.labels.app = "grafana";
      spec = {
        replicas = 1;
        selector.matchLabels.app = "grafana";
        template = {
          metadata.labels.app = "grafana";
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            containers = [
              {
                name = "grafana";
                image = "grafana/grafana:11.1.0";
                env = [
                  {
                    name = "GF_SECURITY_ADMIN_USER";
                    value = "admin";
                  }
                  {
                    name = "GF_SECURITY_ADMIN_PASSWORD";
                    value = "admin";
                  }
                  {
                    name = "GF_USERS_ALLOW_SIGN_UP";
                    value = "false";
                  }
                  {
                    name = "GF_INSTALL_PLUGINS";
                    value = "";
                  }
                  {
                    name = "GF_SERVER_ROOT_URL";
                    value = "http://localhost:3000";
                  }
                ];
                ports = [
                  {
                    containerPort = 3000;
                    name = "http";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
              }
            ];
          };
        };
      };
    };

    Service.grafana = {
      metadata.labels.app = "grafana";
      spec = {
        type = "ClusterIP";
        selector.app = "grafana";
        ports = [
          {
            port = 3000;
            targetPort = 3000;
            name = "http";
          }
        ];
      };
    };

    Role.grafana-role.rules = [
      {
        apiGroups = [""];
        resources = [
          "configmaps"
          "secrets"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
    ];

    RoleBinding.grafana-rolebinding = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "Role";
        name = "grafana-role";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "grafana-sa";
        }
      ];
    };

    # ── Secrets ──────────────────────────────────────────────────
    # Secrets are populated by kubectl-apply-k8s-secrets systemd service
    # from agenix-decrypted files at /run/agenix/. These placeholder
    # definitions ensure the Secret objects exist for secretKeyRef lookups.
    Secret.open-webui-secrets = {
      type = "Opaque";
      stringData.webui-secret-key = "";
    };

    Secret.ai-inference-gateway-secrets = {
      type = "Opaque";
      stringData = {
        "api-keys" = ''
          default=sk-rep...-key
        '';
      };
    };

    # Z.AI API key — populated from agenix (secrets/ai-gateway-zai-api-key.age)
    Secret.zai-api-key = {
      type = "Opaque";
      stringData.ZAI_API_KEY = ""; # placeholder — populated by kubectl-apply-k8s-secrets
    };

    # HuggingFace token — populated from agenix (secrets/huggingface-token.age)
    Secret.hf-token = {
      type = "Opaque";
      stringData.token = "";
    };

    # NVIDIA API key — populated from agenix (secrets/nvidia-api-key.age)
    Secret.nvidia-api-key = {
      type = "Opaque";
      stringData.NVIDIA_API_KEY = "";
    };

    # OpenRouter API key — populated from agenix (secrets/openrouter-api-key.age)
    Secret.openrouter-api-key = {
      type = "Opaque";
      stringData.OPENROUTER_API_KEY = "";
    };

    # Pollinations API key — populated from agenix (secrets/pollinations-api-key.age)
    Secret.pollinations-api-key = {
      type = "Opaque";
      stringData.POLLINATIONS_API_KEY = "";
    };

    # Kilo API key — populated from agenix (secrets/kilo-api-key.age)
    Secret.kilo-api-key = {
      type = "Opaque";
      stringData.KILO_API_KEY = "";
    };

    # OpenCode API key — populated from agenix (secrets/opencode-api-key.age)
    Secret.opencode-api-key = {
      type = "Opaque";
      stringData.OPENCODE_API_KEY = "";
    };

    # ── Additional NetworkPolicies ───────────────────────────────
    # Allow SearXNG pods to reach AI Inference Gateway
    NetworkPolicy.allow-search-to-gateway = {
      spec = {
        podSelector.matchLabels.app = "ai-inference-gateway";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [
              {
                namespaceSelector.matchLabels.name = "search";
                podSelector.matchLabels.app = "searxng";
              }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
        ];
      };
    };

    # Allow gateway ingress from ingress-system and intra-namespace
    NetworkPolicy.allow-gateway-ingress = {
      spec = {
        podSelector.matchLabels.app = "ai-inference-gateway";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels.name = "ingress-system";}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
          {
            from = [{podSelector = {};}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
        ];
      };
    };

    # Allow gateway egress to dependencies
    # Includes ipBlock for hostNetwork pods (llama-servers use hostNetwork)
    NetworkPolicy.allow-gateway-egress = {
      spec = {
        podSelector.matchLabels.app = "ai-inference-gateway";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
            ];
          }
          {
            ports = [
              {
                protocol = "TCP";
                port = 443;
              }
            ];
          }
          {
            to = [{namespaceSelector.matchLabels.name = "search";}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
          {
            to = [{podSelector.matchLabels.app = "qdrant";}];
            ports = [
              {
                protocol = "TCP";
                port = 6333;
              }
            ];
          }
          {
            to = [{podSelector.matchLabels.app = "redis";}];
            ports = [
              {
                protocol = "TCP";
                port = 6379;
              }
            ];
          }
          {
            to = [{podSelector.matchLabels.app = "llama-server-sentry";}];
            ports = [
              {
                protocol = "TCP";
                port = 1235;
              }
            ];
          }
          {
            to = [{podSelector.matchLabels.app = "llama-server-zephyr";}];
            ports = [
              {
                protocol = "TCP";
                port = 1235;
              }
            ];
          }
          {
            to = [{podSelector.matchLabels.app = "llama-server-zephyr-3060ti";}];
            ports = [
              {
                protocol = "TCP";
                port = 1236;
              }
            ];
          }
          {
            to = [{podSelector.matchLabels.app = "privacy-filter";}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
          {
            to = [{ipBlock.cidr = "10.1.1.0/24";}];
            ports = [
              {
                protocol = "TCP";
                port = 1235;
              }
              {
                protocol = "TCP";
                port = 1236;
              }
              {
                protocol = "TCP";
                port = 1237;
              }
            ];
          }
        ];
      };
    };

    # Privacy filter network policies
    NetworkPolicy.privacy-filter-ingress = {
      spec = {
        podSelector.matchLabels.app = "privacy-filter";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels.name = "ingress-system";}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
          {
            from = [{podSelector.matchLabels.name = "ai-inference";}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
            ];
          }
        ];
      };
    };

    NetworkPolicy.privacy-filter-egress = {
      spec = {
        podSelector.matchLabels.app = "privacy-filter";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
            ];
          }
          {
            to = [
              {
                ipBlock.cidr = "0.0.0.0/0";
                except = [
                  "10.0.0.0/8"
                  "172.16.0.0/12"
                  "192.168.0.0/16"
                ];
              }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 443;
              }
            ];
          }
        ];
      };
    };

    # Open WebUI network policy
    NetworkPolicy.open-webui = {
      spec = {
        podSelector.matchLabels.app = "open-webui";
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "ingress-system";}];
            ports = [
              {
                port = 8080;
                protocol = "TCP";
              }
            ];
          }
          {from = [{podSelector = {};}];}
        ];
        egress = [{}];
      };
    };

    # ── OpenAI Privacy Filter ───────────────────────────────────────
    # PII detection and masking using openai/privacy-filter model
    # Requires transformers >= 5.6.0 (model uses openai_privacy_filter architecture)
    # Scale to 1 when nixpkgs has transformers 5.6.0+
    Deployment.privacy-filter = {
      metadata.labels =
        managed
        // {
          app = "privacy-filter";
          component = "pii-detection";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "privacy-filter";
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "privacy-filter";
                component = "pii-detection";
              };
            annotations."nix-csi/discard" = "true";
          };
          spec = {
            nodeName = "sentry";
            automountServiceAccountToken = false;
            containers = {
              _namedlist = true;
              privacy-filter = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgsWithOverlay.privacy-filter}/bin/privacy-filter-server"];
                securityContext.privileged = true;
                env = {
                  _namedlist = true;
                  HF_HOME = {
                    name = "HF_HOME";
                    value = "/var/cache/privacy-filter";
                  };
                  PYTHONUNBUFFERED = {
                    name = "PYTHONUNBUFFERED";
                    value = "1";
                  };
                  LD_LIBRARY_PATH = {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib:/nix/store";
                  };
                };
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "2Gi";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8080;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8080;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    readOnly = true;
                  };
                  "hf-cache" = {
                    mountPath = "/var/cache/privacy-filter";
                  };
                  nvidia-libs = {
                    mountPath = "/run/opengl-driver/lib";
                    readOnly = true;
                  };
                  tmp = {mountPath = "/tmp";};
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix.hostPath = {
                path = "/nix";
                type = "Directory";
              };
              hf-cache.hostPath = {
                path = "/home/j_kro/.cache/huggingface";
                type = "Directory";
              };
              nvidia-libs.hostPath.path = "/run/opengl-driver/lib";
              tmp.emptyDir = {};
            };
          };
        };
      };
    };

    Service.privacy-filter = {
      metadata.labels =
        managed
        // {
          app = "privacy-filter";
        };
      spec = {
        type = "ClusterIP";
        selector.app = "privacy-filter";
        ports = [
          {
            name = "http";
            port = 8080;
            protocol = "TCP";
            targetPort = 8080;
          }
        ];
      };
    };

    # ── KB MCP Server (Knowledge Base RAG) ─────────────────────────
    # Replaces: kubernetes-manifests/kb-mcp/deployment.yaml, service.yaml
    # Provides vector search over technical eBooks via FastMCP protocol
    Deployment.kb-mcp = {
      metadata.labels = {
        app = "kb-mcp";
        component = "rag";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "kb-mcp";
        template = {
          metadata.labels = {
            app = "kb-mcp";
            component = "rag";
          };
          spec = {
            nodeName = "nexus";
            containers = [
              {
                name = "kb-mcp";
                image = "localhost/kb-mcp:latest";
                imagePullPolicy = "IfNotPresent";
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                env = [
                  {
                    name = "QDRANT_HOST";
                    value = "qdrant.ai-inference.svc.cluster.local";
                  }
                  {
                    name = "QDRANT_PORT";
                    value = "6333";
                  }
                  {
                    name = "KB_PORT";
                    value = "8080";
                  }
                  {
                    name = "KB_HOST";
                    value = "0.0.0.0";
                  }
                  {
                    name = "KB_COLLECTION";
                    value = "knowledge_base";
                  }
                  {
                    name = "KB_MODEL";
                    value = "all-MiniLM-L6-v2";
                  }
                  {
                    name = "PYTHONUNBUFFERED";
                    value = "1";
                  }
                  {
                    name = "HOME";
                    value = "/tmp";
                  }
                  {
                    name = "USER";
                    value = "kb-mcp";
                  }
                  {
                    name = "HF_HOME";
                    value = "/tmp/huggingface";
                  }
                  {
                    name = "TRANSFORMERS_CACHE";
                    value = "/tmp/huggingface/transformers";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
                readinessProbe = {
                  tcpSocket.port = 8080;
                  initialDelaySeconds = 15;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 6;
                };
                livenessProbe = {
                  tcpSocket.port = 8080;
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  timeoutSeconds = 10;
                  failureThreshold = 3;
                };
                volumeMounts = [
                  {
                    name = "huggingface-cache";
                    mountPath = "/tmp/huggingface";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "huggingface-cache";
                emptyDir.sizeLimit = "1Gi";
              }
            ];
            tolerations = [
              {
                key = "workstation";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              }
              {
                key = "interactive";
                operator = "Equal";
                value = "true";
                effect = "NoExecute";
              }
            ];
          };
        };
      };
    };

    Service.kb-mcp = {
      metadata.labels = {
        app = "kb-mcp";
        component = "rag";
      };
      spec = {
        type = "ClusterIP";
        ports = [
          {
            port = 8080;
            targetPort = 8080;
            name = "http";
            protocol = "TCP";
          }
        ];
        selector.app = "kb-mcp";
      };
    };
  };
}
