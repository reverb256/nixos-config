{
  pkgs,
  pkgsWithOverlay,
  inputs,
  lib,
  cluster,
  nexusPreferredAffinity,
  aiModelsToml,
  ...
}: let
  # nix-csi scratch image (proven pattern from llama-servers)
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
  # AI Inference Gateway — pre-built container image (loaded into containerd on target node)
  # CRITICAL: Use local registry - docker.io requires auth and is slow
  # Image pushed by nexus:push-gateway-to-registry service
  gatewayImage = "nexus:5000/ai-inference-gateway:2.4.28";
  # Managed-by labels for easykubenix
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
  # AI Model Registry - Read from single source of truth
  aiModels = lib.importTOML aiModelsToml;
  defaultModel = aiModels.defaults.primary;
  fallbackModel = aiModels.defaults.fallback;
  disabledModels = aiModels.defaults.disabled_models or [];

  # Generate DISCOVERY_BACKENDS JSON array.
  # Special handling for NVIDIA NIM: since it's one URL for multiple models,
  # we expand it into multiple entries to maintain the original discovery pattern.
  discoveryBackends = builtins.toJSON (
    lib.concatMap (
      {
        name,
        value,
      }:
        if name == "nvidia-nim"
        then
          lib.map (modelId: {
            inherit (value) url;
            # Use a shorthand name for NIM models (e.g., "nemotron-super")
            name = lib.pipe modelId [
              (builtins.replaceStrings ["nvidia/"] [""])
              (builtins.replaceStrings ["nemotron-3-super-120b-a12b"] ["nemotron-super"])
              (builtins.replaceStrings ["nemotron-3-nano-30b-a3b"] ["nemotron-nano"])
              (builtins.replaceStrings ["nemotron-3-nano-omni-30b-a3b-reasoning"] ["nemotron-omni"])
            ];
          }) (value.models or [])
        else [
          {
            inherit (value) url;
            inherit name;
          }
        ]
    ) (lib.attrsToList aiModels.backends)
  );

  # Model name mapping (aliases to full model identifiers)
  modelNames = {
    "qwen3.5-2b-awq" = aiModels.models.qwen3_5-2b-awq.name or "qwen3.5-2b-awq";
    "qwen3.6-35b-iq3-s" = aiModels.models.qwen3_6-35b-iq3-s.name or "Qwen3.6-35B-A3B-UD-IQ3_S.gguf";
    "glm-5-turbo" = aiModels.models.glm-5-turbo.name or "glm-5-turbo";
    "glm-5.1" = aiModels.models.glm-5_1.name or "glm-5.1";
  };
  # AI Inference Gateway — derive paths from flake input, not hardcoded store paths
in {
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────
    none.Namespace.ai-inference = {
      metadata.labels =
        managed
        // {
          name = "ai-inference";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };
    # ── AI Inference ───────────────────────────────────────────
    ai-inference.ServiceAccount.default = {};
    ai-inference.ServiceAccount.ai-inference-gateway = {};
    ai-inference.ServiceAccount.n8n-sa.automountServiceAccountToken = false;
    ai-inference.ConfigMap.ai-gateway-config.data = {
      AUTH_MODE = "token"; # Token-based authentication
      BACKEND_TYPE = "llama-cpp";
      BACKEND_URL = "http://${cluster.hosts.sentry.ip}:1235";
      DEFAULT_MODEL = modelNames."qwen3.6-35b-iq3-s";
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
    ai-inference.ConfigMap.ai-inference-gateway-config.data = {
      AUTH_MODE = "token"; # Token-based authentication (set GATEWAY_TOKEN via Secret)
      BACKEND_TYPE = "llama-cpp";
      BACKEND_URL = "http://${cluster.hosts.sentry.ip}:1235";
      BACKEND_FALLBACK_URLS = "https://api.z.ai/api/coding/paas/v4,https://integrate.api.nvidia.com/v1";
      ZAI_API_KEY_FILE = "/run/secrets/zai-api-key";
      NVIDIA_NIM_API_KEY_FILE = "/run/secrets/nvidia-api-key";
      DEFAULT_MODEL = "Qwen3.5-4B-Q4_K_M.gguf";
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
      TOKEN_SCOPED_COLLECTIONS = "";
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
      SECONDARY_BACKEND_URL = "http://llama-qwen-vllm-nexus.ai-inference.svc.cluster.local:8040";
      SECONDARY_BACKEND_MODEL = "qwen3.5-2b-awq";
      DISCOVERY_BACKENDS = ''${discoveryBackends} '';
      DISABLED_MODELS = ''${builtins.toJSON disabledModels} '';
      PRIVACY_FILTER_URL = "http://privacy-filter.ai-inference.svc.cluster.local:8080";
      PRIVACY_FILTER_ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_URL = "http://searxng.search.svc.cluster.local:8080";
      MIDDLEWARE__KNOWLEDGE_FABRIC__SEARXNG_MAX_RESULTS = "10";
      MIDDLEWARE__KNOWLEDGE_FABRIC__RRF_K = "60";
      MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__CODE_SEARCH_PATHS = "[\"/etc/nixos\"]";
      MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_ENABLED = "true";
      MIDDLEWARE__KNOWLEDGE_FABRIC__RAG_TOP_K = "10";
      MIDDLEWARE__JWT_AUTH__ENABLED = "true";
      MIDDLEWARE__JWT_AUTH__JWKS_URL = "https://auth.lan/.well-known/jwks";
      MIDDLEWARE__JWT_AUTH__ISSUER = "https://auth.lan";
      MIDDLEWARE__JWT_AUTH__AUDIENCE = "3a331eeb195880d68d9a";
      MIDDLEWARE__JWT_AUTH__SYSTEM_TOKEN = "sovereign-system-token-2026-internal";
    };

      };
    };
    # ── Qdrant Vector Database ──────────────────────────────────
    # Persistent vector store for RAG, knowledge base, embeddings
    # Storage: hostPath at /storage/qdrant (data) + /storage/qdrant-snapshots
    ai-inference.Deployment.qdrant = {
      metadata.labels.app = "qdrant";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "qdrant";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata.labels.app = "qdrant";
          spec = {
            affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100;
                preference.matchExpressions = [
                  {
                    key = "kubernetes.io/hostname";
                    operator = "In";
                    values = ["nexus"];
                  }
                ];
              }
            ];
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              fsGroup = 100;
            };
            containers = {
              _namedlist = true;
              qdrant = {
                image = "qdrant/qdrant:v1.13.7";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 1000;
                  runAsGroup = 100;
                  allowPrivilegeEscalation = false;
                  capabilities.drop = ["ALL"];
                  seccompProfile.type = "RuntimeDefault";
                };
                ports = [
                  {
                    containerPort = 6333;
                    name = "http";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 6334;
                    name = "grpc";
                    protocol = "TCP";
                  }
                ];
                volumeMounts = {
                  _namedlist = true;
                  qdrant-storage = {
                    mountPath = "/qdrant/storage";
                  };
                  qdrant-snapshots = {
                    mountPath = "/qdrant/snapshots";
                  };
                };
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "4Gi";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              qdrant-storage = {
                hostPath = {
                  path = "/storage/qdrant";
                  type = "DirectoryOrCreate";
                };
              };
              qdrant-snapshots = {
                hostPath = {
                  path = "/storage/qdrant-snapshots";
                  type = "DirectoryOrCreate";
                };
              };
            };
          };
        };
      };
    };
    ai-inference.Service.qdrant = {
      metadata.labels.app = "qdrant";
      spec = {
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 6333;
            protocol = "TCP";
            targetPort = 6333;
          }
          {
            name = "grpc";
            port = 6334;
            protocol = "TCP";
            targetPort = 6334;
          }
        ];
        selector.app = "qdrant";
      };
    };
    ai-inference.Role.n8n-role = {
      rules = [
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
    };
    ai-inference.RoleBinding.n8n-rolebinding = {
      subjects = [
        {
          kind = "ServiceAccount";
          name = "n8n-sa";
        }
      ];
      roleRef = {
        kind = "Role";
        name = "n8n-role";
        apiGroup = "rbac.authorization.k8s.io";
      };
    };
    # Gateway needs ConfigMap access for GPU scheduler state (gpu_scheduler.py writes to kube-system)
    none.ClusterRole.ai-inference-gateway-configmap.rules = [
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
    none.ClusterRoleBinding.ai-inference-gateway-configmap = {
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
    # Runs as systemd service on nexus (${cluster.hosts.nexus.ip}:8080).
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
    ai-inference.Service.ai-inference-gateway = {
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
    ai-inference.Deployment.ai-inference-gateway = {
      metadata.labels =
        managed
        // {
          app = "ai-inference-gateway";
          component = "gateway";
        };
      spec = {
        replicas = 2;
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
            affinity = {
              nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [
                {
                  matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "In";
                      values = ["nexus" "sentry"];
                    }
                  ];
                }
              ];
              nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100;
                  preference.matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "In";
                      values = ["nexus"];
                    }
                  ];
                }
              ];
              podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution = [
                {
                  labelSelector.matchLabels.app = "ai-inference-gateway";
                  topologyKey = "kubernetes.io/hostname";
                }
              ];
            }; # HA: nexus+sentry, anti-affinity
            hostNetwork = false;
            serviceAccountName = "ai-inference-gateway";
            automountServiceAccountToken = true; # needed by gpu_scheduler.py kubectl calls
            containers = {
              _namedlist = true;
              ai-gateway = {
                image = gatewayImage;
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsNonRoot = true;
                  allowPrivilegeEscalation = false;
                  capabilities.drop = ["ALL"];
                  seccompProfile.type = "RuntimeDefault";
                };
                # Container image has default Cmd: python -m uvicorn ... --workers 4
                # Override workers to 4 for stability
                # Removed --workers override to fix uvicorn parent process issue
                # Container image default command (single worker) will be used
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
                  DISABLED_MODELS.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "DISABLED_MODELS";
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
                  KILO_API_KEY.valueFrom.secretKeyRef = {
                    key = "KILO_API_KEY";
                  };
                };
              };
            };
          };
        };
      };
    };
    ai-inference.Endpoints.llama-cpp-qwen = {
      metadata.labels = managed // {app = "llama-cpp";};
      subsets = [
        {
          addresses = [{ip = cluster.hosts.nexus.ip;}];
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
    ai-inference.Deployment.redis = {
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
                securityContext = {
                  runAsNonRoot = true;
                  allowPrivilegeEscalation = false;
                  capabilities = {
                    drop = ["ALL"];
                  };
                  seccompProfile = {
                    type = "RuntimeDefault";
                  };
                };
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
                    memory = "1Gi";
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
    ai-inference.Service.redis-service = {
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
    # ── Secrets ──────────────────────────────────────────────────
    # Secrets are populated by kubectl-apply-k8s-secrets systemd service
    # from sops-nix decrypted files at /run/secrets/. These placeholder
    # definitions ensure the Secret objects exist for secretKeyRef lookups.
    ai-inference.Secret.ai-inference-gateway-secrets = {
      type = "Opaque";
      # TODO: Fill from sops-nix key `ai-gateway-zai-api-key` (see modules/system/sops-secrets-registry.nix)
      stringData = {
        "api-keys" = "";
      };
    };
    # Z.AI API key — populated from sops-nix (secrets/ai-gateway-zai-api-key.age)
    ai-inference.Secret.zai-api-key = {
      type = "Opaque";
      stringData.ZAI_API_KEY = "";
    };
    # HuggingFace token — populated from sops-nix (secrets/huggingface-token.age)
    ai-inference.Secret.hf-token = {
      type = "Opaque";
      stringData.token = "";
    };
    # NVIDIA API key — populated from sops-nix (secrets/nvidia-api-key.age)
    ai-inference.Secret.nvidia-api-key = {
      type = "Opaque";
      stringData.NVIDIA_API_KEY = "";
    };
    ai-inference.Secret.kilo-api-key = {
      type = "Opaque";
      stringData.KILO_API_KEY = "";
    };
    # OpenCode API key — populated from sops-nix (secrets/opencode-api-key.age)
    ai-inference.Secret.opencode-api-key = {
      type = "Opaque";
      stringData.OPENCODE_API_KEY = "";
    };
    # Gateway API token — populated from sops-nix (secrets/ai-gateway-token.age)
    ai-inference.Secret.ai-gateway-token = {
      type = "Opaque";
      stringData.GATEWAY_TOKEN = "";
    };
    # ── Additional NetworkPolicies ───────────────────────────────
    # Allow SearXNG pods to reach AI Inference Gateway
    ai-inference.NetworkPolicy.allow-search-to-gateway = {
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
    ai-inference.NetworkPolicy.allow-gateway-ingress = {
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
    ai-inference.NetworkPolicy.allow-gateway-egress = {
      spec = {
        podSelector.matchLabels.app = "ai-inference-gateway";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
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
            to = [{podSelector.matchLabels.app = "llama-qwen-vllm-nexus";}];
            ports = [
              {
                protocol = "TCP";
                port = 8041;
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
            to = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                protocol = "TCP";
                port = 1235;
              }
              {
                protocol = "TCP";
                port = 8041;
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
    ai-inference.NetworkPolicy.privacy-filter-ingress = {
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
    ai-inference.NetworkPolicy.privacy-filter-egress = {
      spec = {
        podSelector.matchLabels.app = "privacy-filter";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
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
    # ── vLLM Network Policies ─────────────────────────────────────────
    # Restrict access to vLLM endpoints to gateway only
    ai-inference.NetworkPolicy.llama-qwen-vllm-nexus-ingress = {
      spec = {
        podSelector.matchLabels.app = "llama-qwen-vllm-nexus";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{podSelector.matchLabels.app = "ai-inference-gateway";}];
            ports = [
              {
                protocol = "TCP";
                port = 8040;
              }
            ];
          }
        ];
      };
    };
    # ── Zephyr 3090 llama-server Network Policies ─────────────────────
    ai-inference.NetworkPolicy.llama-server-zephyr-3090-moe-ingress = {
      spec = {
        podSelector.matchLabels.app = "llama-server-zephyr-3090-moe";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{podSelector.matchLabels.app = "ai-inference-gateway";}];
            ports = [
              {
                protocol = "TCP";
                port = 1237;
              }
            ];
          }
        ];
      };
    };
    # ── OpenAI Privacy Filter ───────────────────────────────────────
    # PII detection and masking using openai/privacy-filter model
    # Requires transformers >= 5.6.0 (model uses openai_privacy_filter architecture)
    # Scale to 1 when nixpkgs has transformers 5.6.0+
    ai-inference.Deployment.privacy-filter = {
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
                    memory = "1Gi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "4Gi";
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
    ai-inference.Service.privacy-filter = {
      metadata.labels =
        managed
        // {
          app = "privacy-filter";
        };
      spec = {
        type = "NodePort";
        selector.app = "privacy-filter";
        ports = [
          {
            name = "http";
            port = 8080;
            protocol = "TCP";
            targetPort = 8080;
            nodePort = 30935;
          }
        ];
      };
    };
    # ── KB MCP Server (Knowledge Base RAG) ─────────────────────────
    # STUB: Image not built (localhost/kb-mcp:latest doesn't exist).
    # 0 replicas, no pods running. Disabled until image is built.
    # Replaces: kubernetes-manifests/kb-mcp/deployment.yaml, service.yaml
    # Provides vector search over technical eBooks via FastMCP protocol
    ai-inference.Deployment.kb-mcp = {
      metadata.labels =
        managed
        // {
          app = "kb-mcp";
          component = "rag";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "kb-mcp";
        template = {
          metadata.labels =
            managed
            // {
              app = "kb-mcp";
              component = "rag";
            };
          spec = {
            affinity = {
              nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [
                {
                  matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "In";
                      values = ["nexus" "sentry"];
                    }
                  ];
                }
              ];
              nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100;
                  preference.matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "In";
                      values = ["nexus"];
                    }
                  ];
                }
              ];
              podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution = [
                {
                  labelSelector.matchLabels.app = "ai-inference-gateway";
                  topologyKey = "kubernetes.io/hostname";
                }
              ];
            }; # HA: nexus+sentry, anti-affinity
            containers = [
              {
                name = "kb-mcp";
                image = "localhost/kb-mcp:latest";
                imagePullPolicy = "IfNotPresent";
                securityContext = {
                  runAsNonRoot = true;
                  allowPrivilegeEscalation = false;
                  capabilities = {
                    drop = ["ALL"];
                  };
                  seccompProfile = {
                    type = "RuntimeDefault";
                  };
                };
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
                    memory = "1Gi";
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
    ai-inference.Service.kb-mcp = {
      metadata.labels =
        managed
        // {
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
    # ── Model Sync (CronJob) ──────────────────────────────────────────
    # Validates curated models against gateway, deploys Pi/OmP configs.
    # Source of truth for curated model list. Runs every 6h on zephyr.
    # Output: /data/agents/model-sync/ (staging) + ~/.config/pi + ~/.omp/agent (deployed)
    ai-inference.ConfigMap.model-sync-script.data."sync.py" = ''
      #!/usr/bin/env python3
      """Model sync: validates curated models against gateway, writes Pi/OmP configs."""
      import json, os, shutil, subprocess, sys, time, urllib.request
      GATEWAY = os.environ.get("GATEWAY_URL", "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1/models")
      HOST_GATEWAY = os.environ.get("HOST_GATEWAY_URL", "http://10.1.1.110:8080/v1")
      OUT = "/data/agents/model-sync"
      PI_CONFIG = "/home/j_kro/.config/pi/config.yaml"
      OMP_CONFIG = "/home/j_kro/.omp/agent/models.json"
      API_KEY = os.environ.get("API_KEY", "")
      # Direct URLs for local models (bypass gateway catalog)
      LOCAL_URLS = {
          "local/qwen3.5-2b-awq": "http://10.1.1.120:8040/v1",
          "local/qwen3.6-moe-35b": "http://10.1.1.110:1237/v1",
          "local/qwen3.5-4b": "http://10.1.1.140:1235/v1",
      }
      # OpenCode Go middleware for NIM models
      OPENCODE_URL = "http://10.1.1.110:8080/v1"
      os.makedirs(OUT, exist_ok=True)
      # Retry gateway fetch (handles transient failures)
      for attempt in range(3):
          try:
              with urllib.request.urlopen(GATEWAY, timeout=10) as r:
                  models = json.loads(r.read())
              break
          except Exception as e:
              print(f"WARNING: gateway attempt {attempt+1}/3 failed: {e}")
              if attempt < 2:
                  time.sleep(5)
              else:
                  print(f"ERROR: gateway unreachable after 3 attempts")
                  raise SystemExit(1)
      gw_ids = {m["id"] for m in models["data"]}
      print(f"Gateway: {len(models['data'])} models")
      CURATED = """
      glm-5.1|primary|GLM-5.1 744B MoE orchestrator (2x/3x quota)
      glm-5-turbo|primary|GLM-5 Turbo fast agentic (2x/3x quota)
      glm-4.7|primary|GLM-4.7 358B MoE (1x quota)
      glm-4.5-air|fast|GLM-4.5 Air ultra-fast (1x quota)
      local/qwen3.5-2b-awq|fast|Qwen3.5 2B AWQ (Nexus 3060Ti, local)
      local/qwen3.6-moe-35b|reasoning|Carnice Qwen3.6 35B MoE IQ4_XS (Zephyr 3090, local, vision)
      local/qwen3.5-4b|fast|Qwen3.5 4B Q4 (Sentry AMD, local, vision)
      deepseek-ai/deepseek-v4-flash|code|DeepSeek V4 Flash (NIM, rate-limited, 1M ctx)
      opencode/deepseek-v4-flash|code|DeepSeek V4 Flash (OpenCode Go, 5h+weekly cap, fallback)
      qwen/qwen3.5-397b-a17b|code|Qwen3.5 397B A17B (NIM, rate-limited, vision)
      qwen/qwen3.5-122b-a10b|code|Qwen3.5 122B A10B (NIM, rate-limited)
      qwen/qwen3.5-flash-02-23|fast|Qwen3.5 Flash 1M context (rate-limited)
      qwen/qwen3-next-80b-a3b-instruct|reasoning|Qwen3 Next 80B (NIM, rate-limited)
      mistralai/mistral-large-3-675b-instruct-2512|reasoning|Mistral Large 3 675B (rate-limited)
      deepseek-ai/deepseek-v4-pro|reasoning|DeepSeek V4 Pro 1M ctx (NIM, rate-limited)
      deepseek-v4-flash:free|free|DeepSeek V4 Flash Free (Kilo/Zen, 1M, daily quota)
      nvidia/nemotron-3-super-120b-a12b:free|free|Nemotron 3 Super Free (128K, half NIM ctx)
      nvidia/nemotron-3-nano-30b-a3b:free|free|Nemotron 3 Nano Free (128K, half NIM ctx)
      #openrouter/free|free|OpenRouter free router (REMOVED — no longer used)
      """.strip()
      CAT_NAMES = {
          "primary": "PRIMARY", "fast": "FAST", "code": "CODING",
          "context": "LARGE CONTEXT", "reasoning": "REASONING",
          "vision": "VISION", "general": "GENERAL", "free": "FREE TIER",
      }
      def get_ctx(mid):
          for m in models["data"]:
              if m["id"] == mid:
                  return m.get("context_length") or 262144
          return 262144
      def is_vision(mid):
          return any(x in mid.lower() for x in ["vl", "vision", "5v", "3.6", "3.5-4b"])
      def is_reasoning(mid, cat):
          if cat in ("reasoning", "primary"):
              return True
          return any(x in mid.lower() for x in ["reasoning", "large", "675b", "405b", "340b", "deepseek", "next-80", "moe-35b", "v4-flash"])
      def backup(path):
          if os.path.exists(path):
              bak = path + ".bak"
              shutil.copy2(path, bak)
              print(f"  Backup: {bak}")
              return True
          return False
      # Build model lists and providers
      omp_providers = {"gateway": {
          "baseUrl": HOST_GATEWAY,
          "api": "openai-completions",
          "compat": {
              "supportsUsageInStreaming": True,
              "maxTokensField": "max_tokens",
          },
          "models": [],
      }}
      omp_models_local = []  # Local models need separate providers
      omp_models_opencode = []  # OpenCode models through middleware
      pi_lines = [
          "# Pi config - Auto-synced from AI Inference Gateway",
          "# DO NOT EDIT — regenerated by model-sync CronJob every 6h",
          "# Edits will be lost on next sync. Change CURATED list in ai-inference.nix instead.",
          "",
          "model: glm-5.1",
          "smol: local/qwen3.5-2b-awq",
          "plan: glm-4.7",
          "slow: local/qwen3.6-moe-35b",
          "",
          "providers:",
          "  gateway:",
          "    type: openai-compatible",
          f"    baseURL: {HOST_GATEWAY}",
          "    apiKey: ''${ZAI_API_KEY}",
          "  local-vllm:",
          "    type: openai-compatible",
          "    baseURL: http://10.1.1.120:8040/v1",
          "  local-zephyr-3090:",
          "    type: openai-compatible",
          "    baseURL: http://10.1.1.110:1237/v1",
          "  local-sentry:",
          "    type: openai-compatible",
          "    baseURL: http://10.1.1.140:1235/v1",
          "    type: openai-compatible",
          f"    baseURL: {OPENCODE_URL}",
          "    apiKey: ''${OPENCODE_GO_API_KEY}",
          "",
          "models:",
      ]
      found = 0
      missing = 0
      local_found = 0
      opencode_found = 0
      last_cat = ""
      for line in CURATED.split("\n"):
          parts = line.strip().split("|", 2)
          if len(parts) != 3 or not parts[0]:
              continue
          mid, cat, desc = parts
          # Handle local/ prefixed models
          if mid.startswith("local/"):
              local_found += 1
              print(f"  LOC  {mid}")
              url = LOCAL_URLS.get(mid)
              if not url:
                  print(f"  ERROR: No URL for {mid}")
                  continue
              # Extract provider name from URL
              if "8040" in url:
                  provider = "local-vllm"
              elif "1237" in url:
                  provider = "local-zephyr-3090"
              else:
                  provider = "local-sentry"
              ctx = 262144  # Default for local models
              omp_models_local.append({
                  "id": mid,
                  "name": desc,
                  "provider": provider,
                  "reasoning": is_reasoning(mid, cat),
                  "input": ["text", "image"] if is_vision(mid) else ["text"],
                  "contextWindow": ctx,
                  "maxTokens": min(ctx, 262144),
              })
              if cat != last_cat:
                  pi_lines.append(f"  # === {CAT_NAMES.get(cat, cat.upper())} ===")
                  last_cat = cat
              clean = mid.replace("local/", "")
              pi_lines.extend([
                  f"  - id: {mid}",
                  f"    name: {clean}",
                  f"    provider: {provider}",
                  f"    description: {desc}",
                  "",
              ])
              continue
          # Handle opencode/ prefixed models (via middleware)
          if mid.startswith("opencode/"):
              opencode_found += 1
              print(f"  OPE  {mid}")
              # Remove opencode/ prefix for gateway model name
              gw_mid = mid.replace("opencode/", "")
              if gw_mid in gw_ids:
                  found += 1
                  ctx = get_ctx(gw_mid)
                  omp_models_opencode.append({
                      "id": mid,
                      "name": desc,
                      "reasoning": is_reasoning(mid, cat),
                      "input": ["text", "image"] if is_vision(mid) else ["text"],
                      "contextWindow": ctx,
                      "maxTokens": min(ctx, 262144),
                  })
                  if cat != last_cat:
                      pi_lines.append(f"  # === {CAT_NAMES.get(cat, cat.upper())} ===")
                      last_cat = cat
                  clean = mid.replace("opencode/", "")
                  pi_lines.extend([
                      f"  - id: {mid}",
                      f"    name: {clean}",
                      f"    description: {desc}",
                      "",
                  ])
              else:
                  missing += 1
                  print(f"  MISS {mid} (not in gateway)")
              continue
          # Handle gateway models
          if mid in gw_ids:
              found += 1
              print(f"  OK   {mid}")
              ctx = get_ctx(mid)
              max_tok = min(ctx, 262144)
              omp_providers["gateway"]["models"].append({
                  "id": mid,
                  "name": desc,
                  "reasoning": is_reasoning(mid, cat),
                  "input": ["text", "image"] if is_vision(mid) else ["text"],
                  "contextWindow": ctx,
                  "maxTokens": max_tok,
              })
              if cat != last_cat:
                  pi_lines.append(f"  # === {CAT_NAMES.get(cat, cat.upper())} ===")
                  last_cat = cat
              clean = mid.replace(":free", "")
              pi_lines.extend([
                  f"  - id: {mid}",
                  f"    name: {clean}",
                  "    provider: gateway",
                  f"    description: {desc}",
                  "",
              ])
          else:
              missing += 1
              print(f"  MISS {mid}")
      if missing > 0:
          print(f"WARNING: {missing} curated models missing from gateway!")
      else:
          print(f"All {found} curated models found on gateway")
      if local_found > 0:
          print(f"Local models: {local_found} (direct URLs)")
      if opencode_found > 0:
          print(f"OpenCode models: {opencode_found} (via middleware)")
      print(f"Total: {found + local_found + opencode_found} models configured")
      # Generate OmP JSON with all providers
      omp_providers["local-vllm"] = {
          "baseUrl": LOCAL_URLS["local/qwen3.5-2b-awq"],
          "api": "openai-completions",
          "compat": {
              "supportsUsageInStreaming": True,
              "maxTokensField": "max_tokens",
          },
          "models": [m for m in omp_models_local if m["provider"] == "local-vllm"],
      }
      omp_providers["local-zephyr-3090"] = {
          "baseUrl": LOCAL_URLS["local/qwen3.6-moe-35b"],
          "api": "openai-completions",
          "compat": {
              "supportsUsageInStreaming": True,
              "maxTokensField": "max_tokens",
          },
          "models": [m for m in omp_models_local if m["provider"] == "local-zephyr-3090"],
      }
      omp_providers["local-sentry"] = {
          "baseUrl": LOCAL_URLS["local/qwen3.5-4b"],
          "api": "openai-completions",
          "compat": {
              "supportsUsageInStreaming": True,
              "maxTokensField": "max_tokens",
          },
          "models": [m for m in omp_models_local if m["provider"] == "local-sentry"],
      }
          "baseUrl": OPENCODE_URL,
          "api": "openai-completions",
          "compat": {
              "supportsUsageInStreaming": True,
              "maxTokensField": "max_tokens",
          },
          "models": omp_models_opencode,
      }

          NetworkPolicy.vllm-nexus-ingress = {
            spec = {
              podSelector.matchLabels.app = "llama-qwen-vllm-nexus";
              policyTypes = ["Ingress"];
              ingress = [
                {
                  from = [{podSelector.matchLabels.app = "ai-inference-gateway";}];
                  ports = [{
                    protocol = "TCP";
                    port = 8040;
                  }];
                }
              ];
            };
          };
      omp = {
          "providers": omp_providers,
          "modelRoles": {
              "default": "glm-4.7",  # 1x quota, always cheap
              "smol": "local/qwen3.5-2b-awq",  # Unlimited, fastest local
              "slow": "local/qwen3.6-moe-35b",  # Unlimited, best reasoning
              "plan": "deepseek-ai/deepseek-v4-flash",  # NIM, rate-limited fallback
              "commit": "local/qwen3.6-moe-35b",  # Unlimited primary
              "code": "deepseek-ai/deepseek-v4-flash",  # NIM, rate-limited
              "vision": "local/qwen3.6-moe-35b",  # Unlimited, local vision
          },
      }
      # Generate Pi YAML (NO plaintext API key — Pi reads ZAI_API_KEY from env)
      pi_lines.extend([
          "providers:",
          "  gateway:",
          "    type: openai-compatible",
          f"    baseURL: {HOST_GATEWAY}",
          "    apiKey: ''${ZAI_API_KEY}",
          "context:",
          "  maxTokens: 200000",
          "  timeout: 180",
          "tools:",
          "  - bash",
          "  - read",
          "  - write",
          "  - edit",
          "  - glob",
          "  - grep",
          "ui:",
          "  theme: dark",
          "  showThinking: false",
          "  streaming: true",
      ])
      # Write to staging area
      omp_path = os.path.join(OUT, "models-omp.json")
      pi_path = os.path.join(OUT, "models-pi.yaml")
      with open(omp_path, "w") as f:
          json.dump(omp, f, indent=2)
      with open(pi_path, "w") as f:
          f.write("\n".join(pi_lines) + "\n")
      total_models = len(omp_providers["gateway"]["models"]) + len(omp_models_local) + len(omp_models_opencode)
      print(f"Staging: {omp_path} ({total_models} models)")
      print(f"Staging: {pi_path} ({total_models} models)")
      # Deploy to agent config paths with backup
      deployed = 0
      for src, dst in [(omp_path, OMP_CONFIG), (pi_path, PI_CONFIG)]:
          if os.path.exists(src):
              backup(dst)
              os.makedirs(os.path.dirname(dst), exist_ok=True)
              shutil.copy2(src, dst)
              # Fix ownership to j_kro:users (runs as root in pod)
              try:
                  subprocess.run(["chown", "1000:100", dst], check=True, capture_output=True)
              except Exception as e:
                  print(f"  WARNING: chown failed for {dst}: {e}")
              deployed += 1
              print(f"  Deployed: {dst}")
      print(f"Sync complete: {deployed} configs deployed")
    '';
    ai-inference.CronJob.model-sync = {
      metadata.labels = managed // {app = "model-sync";};
      spec = {
        schedule = "0 */6 * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 1;
        jobTemplate.spec.template = {
          metadata.labels = {app = "model-sync";};
          spec = {
            nodeName = "zephyr";
            restartPolicy = "OnFailure";
            securityContext = {
              runAsUser = 0;
              runAsGroup = 0;
              fsGroup = 100;
            };
            containers = {
              _namedlist = true;
              sync = {
                image = "docker.io/library/python:3.13-alpine";
                command = ["python3" "/scripts/sync.py"];
                securityContext = {
                  runAsNonRoot = true;
                  allowPrivilegeEscalation = false;
                  capabilities.drop = ["ALL"];
                  seccompProfile.type = "RuntimeDefault";
                };
                env = {
                  _namedlist = true;
                  GATEWAY_URL = {
                    name = "GATEWAY_URL";
                    value = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1/models";
                  };
                  HOST_GATEWAY_URL = {
                    name = "HOST_GATEWAY_URL";
                    value = cluster.kubernetes.gatewayUrl;
                  };
                  ZAI_API_KEY.valueFrom.secretKeyRef = {
                    name = "zai-api-key";
                    key = "ZAI_API_KEY";
                  };
                  OPENCODE_GO_API_KEY.valueFrom.secretKeyRef = {
                    name = "opencode-api-key";
                    key = "OPENCODE_API_KEY";
                  };
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "200m";
                    memory = "256Mi";
                  };
                };
                volumeMounts = {
                  _namedlist = true;
                  scripts = {mountPath = "/scripts";};
                  output = {mountPath = "/data/agents";};
                  home = {mountPath = "/home/j_kro";};
                };
              };
            };
            volumes = {
              _namedlist = true;
              scripts = {
                configMap.name = "model-sync-script";
                defaultMode = "0755";
              };
              output = {
                hostPath.path = "/data/agents";
                type = "DirectoryOrCreate";
              };
              home = {
                hostPath.path = "/home/j_kro";
                type = "DirectoryOrCreate";
              };
            };
          };
        };
      };
    };
  };
}
