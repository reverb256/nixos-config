{
  pkgs,
  pkgsWithOverlay,
  inputs,
  lib,
  cluster,
  nexusPreferredAffinity,
  ...
}: let
  # nix-csi scratch image (proven pattern from llama-servers)
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";

  # AI Inference Gateway — pre-built container image (loaded into containerd on target node)
  # CRITICAL: Use local registry - docker.io requires auth and is slow
  # Image pushed by nexus:push-gateway-to-registry service
  gatewayImage = "nexus:5000/ai-inference-gateway:2.4.9";

  # Managed-by labels for easykubenix
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
  # AI Inference Gateway — derive paths from flake input, not hardcoded store paths
in {
  config.kubernetes.objects.ai-inference = {
    ServiceAccount.default = {};
    ServiceAccount.ai-inference-gateway = {};
    ServiceAccount.open-webui = {};
    ServiceAccount.n8n-sa.automountServiceAccountToken = false;

    ConfigMap.ai-gateway-config.data = {
      AUTH_MODE = "none";
      BACKEND_TYPE = "llama-cpp";
      BACKEND_URL = "http://${cluster.hosts.sentry.ip}:1235";
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
      BACKEND_URL = "http://${cluster.hosts.sentry.ip}:1235";
      BACKEND_FALLBACK_URLS = ""; # Dead backends removed (see git log)
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
      SECONDARY_BACKEND_URL = "http://${cluster.hosts.zephyr.ip}:8040";
      SECONDARY_BACKEND_MODEL = "qwen3.5-2b-awq";
      DISCOVERY_BACKENDS = ''[{"url": "http://${cluster.hosts.zephyr.ip}:8040", "model": "qwen3.5-2b-awq", "name": "vLLM-3060Ti"}]''; # vLLM Qwen3.5-2B-AWQ on 3060Ti (port 8040)
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
      JWT_AUTH_ENABLED = "true";
      JWT_AUTH_JWKS_URL = "https://auth.lan/.well-known/jwks";
      JWT_AUTH_ISSUER = "https://auth.lan";
      JWT_AUTH_AUDIENCE = "3a331eeb195880d68d9a";
      JWT_AUTH_REFRESH_INTERVAL = "300";
    };

    # NOTE: Prometheus + Grafana removed — see kubernetes/modules/monitoring.nix
    # for the canonical monitoring stack (monitoring namespace).

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
            hostAliases = [
              {
                ip = cluster.kubernetes.vip;
                hostnames = ["auth.lan" "openwebui.lan"];
              }
            ];
            containers = {
              _namedlist = true;
              open-webui = {
                image = "ghcr.io/open-webui/open-webui:v0.9.2";
                imagePullPolicy = "IfNotPresent";
                env = {
                  _namedlist = true;
                  OLLAMA_BASE_URLS = {
                    name = "OLLAMA_BASE_URLS";
                    value = "http://ai-inference.ai-inference.svc.cluster.local:11434";
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
                    value = "http://ai-inference.ai-inference.svc.cluster.local:11434";
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
                { matchExpressions = [{ key = "kubernetes.io/hostname"; operator = "In"; values = ["nexus" "sentry"]; }]; }
              ];
              nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
                { weight = 100; preference.matchExpressions = [{ key = "kubernetes.io/hostname"; operator = "In"; values = ["nexus"]; }]; }
              ];
              podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution = [
                { labelSelector.matchLabels.app = "ai-inference-gateway"; topologyKey = "kubernetes.io/hostname"; }
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
                  JWT_AUTH_ENABLED.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "JWT_AUTH_ENABLED";
                  };
                  JWT_AUTH_JWKS_URL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "JWT_AUTH_JWKS_URL";
                  };
                  JWT_AUTH_ISSUER.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "JWT_AUTH_ISSUER";
                  };
                  JWT_AUTH_AUDIENCE.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "JWT_AUTH_AUDIENCE";
                  };
                  JWT_AUTH_REFRESH_INTERVAL.valueFrom.configMapKeyRef = {
                    name = "ai-inference-gateway-config";
                    key = "JWT_AUTH_REFRESH_INTERVAL";
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
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  timeoutSeconds = 10;
                  failureThreshold = 5;
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
                image = "docker.io/qdrant/qdrant:v1.17.1";
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

    # ── Embed Server removed: gateway handles embeddings via BidirLM ──
    # Previously: HuggingFace TEI (nomic-embed-text-v2-moe) with CUDA driver
    # mismatch (compat layer 575.x vs host 595.x). Replaced by built-in
    # BidirLM-Omni-2.5B-Embedding endpoint at /v1/embeddings.
    # Knowledge Fabric API stub removed — RRF middleware runs in gateway.

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
            to = [{podSelector.matchLabels.app = "llama-qwen-vllm-zephyr-3060ti";}];
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
    # STUB: Image not built (localhost/kb-mcp:latest doesn't exist).
    # 0 replicas, no pods running. Disabled until image is built.
    # Replaces: kubernetes-manifests/kb-mcp/deployment.yaml, service.yaml
    # Provides vector search over technical eBooks via FastMCP protocol
    Deployment.kb-mcp = {
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
                { matchExpressions = [{ key = "kubernetes.io/hostname"; operator = "In"; values = ["nexus" "sentry"]; }]; }
              ];
              nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
                { weight = 100; preference.matchExpressions = [{ key = "kubernetes.io/hostname"; operator = "In"; values = ["nexus"]; }]; }
              ];
              podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution = [
                { labelSelector.matchLabels.app = "ai-inference-gateway"; topologyKey = "kubernetes.io/hostname"; }
              ];
            }; # HA: nexus+sentry, anti-affinity
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
API_KEY = os.environ.get("ZAI_API_KEY", "")

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
glm-5.1|primary|GLM-5.1 744B MoE orchestrator
glm-5-turbo|primary|GLM-5 Turbo fast agentic
glm-4.7|primary|GLM-4.7 358B MoE coding
glm-4.5-air|fast|GLM-4.5 Air ultra-fast
glm-4.7-flash|fast|GLM-4.7 Flash fast vision
z-ai/glm-5v-turbo|vision|GLM-5V Turbo vision
nvidia/nemotron-3-nano-30b-a3b|fast|Nemotron Nano 30B reasoning
nvidia/nemotron-nano-9b-v2|fast|Nemotron Nano 9B
nvidia/llama-3.3-nemotron-super-49b-v1|code|Nemotron Super 49B coding
qwen/qwen3-coder|code|Qwen3 Coder 262K context
qwen/qwen3-coder-480b-a35b-instruct|code|Qwen3 Coder 480B
qwen/qwen3.5-flash-02-23|context|Qwen3.5 Flash 1M context
qwen/qwen3.5-plus-02-15|context|Qwen3.5 Plus 1M context
qwen/qwen3.5-35b-a3b|reasoning|Qwen3.5 35B MoE
qwen/qwen3-next-80b-a3b-instruct|reasoning|Qwen3 Next 80B
mistralai/mistral-large-3-675b-instruct-2512|reasoning|Mistral Large 3 675B
mistralai/mistral-small-4-119b-2603|code|Mistral Small 4 119B
meta/llama-3.1-405b-instruct|general|LLaMA 3.1 405B
deepseek-ai/deepseek-v4-pro|reasoning|DeepSeek V4 Pro 1M ctx
google/gemma-4-26b-a4b-it:free|free|Gemma 4 26B free
qwen/qwen3-next-80b-a3b-instruct:free|free|Qwen3 Next 80B free
kilo-auto/free|free|Kilo auto free router
openrouter/free|free|OpenRouter free router
nvidia/nemotron-3-super-120b-a12b:free|free|Nemotron 120B free
meta-llama/llama-3.3-70b-instruct:free|free|LLaMA 3.3 70B free
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
    return any(x in mid.lower() for x in ["vl", "vision", "5v"])

def is_reasoning(mid, cat):
    if cat in ("reasoning", "primary"):
        return True
    return any(x in mid.lower() for x in ["reasoning", "large", "675b", "405b", "340b", "deepseek", "next-80"])

def backup(path):
    if os.path.exists(path):
        bak = path + ".bak"
        shutil.copy2(path, bak)
        print(f"  Backup: {bak}")
        return True
    return False

# Build model lists
omp_models = []
pi_lines = [
    "# Pi config - Auto-synced from AI Inference Gateway",
    "# DO NOT EDIT — regenerated by model-sync CronJob every 6h",
    "# Edits will be lost on next sync. Change CURATED list in ai-inference.nix instead.",
    "",
    "model: glm-5.1",
    "smol: glm-4.5-air",
    "plan: glm-4.7",
    "slow: glm-5-turbo",
    "",
    "models:",
]
found = 0
missing = 0
last_cat = ""

for line in CURATED.split("\n"):
    parts = line.strip().split("|", 2)
    if len(parts) != 3 or not parts[0]:
        continue
    mid, cat, desc = parts
    if mid in gw_ids:
        found += 1
        print(f"  OK   {mid}")
        ctx = get_ctx(mid)
        max_tok = min(ctx, 262144)
        omp_models.append({
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

# Generate OmP JSON
omp = {
    "providers": {
        "gateway": {
            "baseUrl": HOST_GATEWAY,
            "api": "openai-completions",
            "compat": {
                "supportsUsageInStreaming": True,
                "maxTokensField": "max_tokens",
            },
            "models": omp_models,
        }
    },
    "modelRoles": {
        "default": "glm-5.1",
        "smol": "glm-4.5-air",
        "slow": "mistralai/mistral-large-3-675b-instruct-2512",
        "plan": "nvidia/llama-3.3-nemotron-super-49b-v1",
        "commit": "qwen/qwen3-coder-480b-a35b-instruct",
        "code": "qwen/qwen3-coder-480b-a35b-instruct",
        "vision": "z-ai/glm-5v-turbo",
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

print(f"Staging: {omp_path} ({len(omp_models)} models)")
print(f"Staging: {pi_path} ({len(omp_models)} models)")

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
                env = {
                  _namedlist = true;
                  GATEWAY_URL = {
                    name = "GATEWAY_URL";
                    value = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1/models";
                  };
                  HOST_GATEWAY_URL = {
                    name = "HOST_GATEWAY_URL";
                    value = cluster.gatewayUrl;
                  };
                  ZAI_API_KEY.valueFrom.secretKeyRef = {
                    name = "ai-inference-gateway-secrets";
                    key = "zai-api-key";
                  };
                };
                resources = {
                  requests = {cpu = "100m"; memory = "128Mi";};
                  limits = {cpu = "200m"; memory = "256Mi";};
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
