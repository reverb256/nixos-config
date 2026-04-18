{
  pkgs, lib, ...
}:
{
  config.kubernetes.objects.ai-inference = {
    ServiceAccount.default = {};
    ServiceAccount.ai-inference-gateway = {};
    ServiceAccount.open-webui = {};
    ServiceAccount.prometheus = {};
    ServiceAccount.searxng-mcp = {};
    ServiceAccount.n8n-sa.automountServiceAccountToken = false;

    ConfigMap.ai-gateway-config.data = {
      AUTH_MODE = "none"; BACKEND_TYPE = "llama-cpp";
      BACKEND_URL = "http://llama-cpp-qwen.ai-inference.svc.cluster.local:8080";
      DEFAULT_MODEL = "qwen3.5-4b"; RAG_ENABLED = "true"; RAG_TOP_K = "5";
      QDRANT_URL = "http://qdrant:6333"; HYBRID_SEARCH_ENABLED = "true";
      MCP_ENABLED = "false"; AUTO_RAG_ENABLED = "true";
      EMBEDDING_MODEL = "sentence-transformers/all-MiniLM-L6-v2";
      BM25_WEIGHT = "0.300000"; CHUNK_OVERLAP = "50"; CHUNK_SIZE = "512";
    };

    ConfigMap.ai-inference-gateway-config.data = {
      AUTH_MODE = "api-key";
      BACKEND_TYPE = "llama-cpp";
      # Primary: Qwen 35B MoE on zephyr 3090 (K8s service)
      BACKEND_URL = "http://llama-server-zephyr.ai-inference.svc.cluster.local:1235";
      # Fallback chain: 3060Ti → Sentry → Z.AI cloud API
      BACKEND_FALLBACK_URLS = "http://llama-server-zephyr-3060ti.ai-inference.svc.cluster.local:1236,http://llama-server-sentry.ai-inference.svc.cluster.local:1235,https://api.z.ai/api/coding/paas/v4";
      DEFAULT_MODEL = "qwen3.6-35b-a3b";
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
      EMBEDDING_MODEL = "sentence-transformers/all-MiniLM-L6-v2";
      BM25_WEIGHT = "0.3";
      CHUNK_OVERLAP = "50";
      CHUNK_SIZE = "512";
      MCP_ENABLED = "true";
      SYSTEM_PROMPTS_ENABLED = "true";
      TOKEN_SCOPED_COLLECTIONS = "true";
      VECTOR_WEIGHT = "0.7";
      HF_HOME = "/var/cache/ai-inference";
      TRANSFORMERS_CACHE = "/var/cache/ai-inference";
      MAX_REQUEST_SIZE = "10485760";
      CIRCUIT_BREAKER_ENABLED = "true";
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

  ConfigMap.searxng-mcp-config.data = { SEARXNG_CACHE_TTL = "300"; SEARXNG_URL = "http://searxng-refactored.search.svc.cluster.local:8080"; };

    Deployment.open-webui = {
      metadata.labels.app = "open-webui";
      spec = {
        replicas = 1; revisionHistoryLimit = 2; selector.matchLabels.app = "open-webui";
        strategy = { type = "RollingUpdate"; rollingUpdate = { maxSurge = 0; maxUnavailable = 1; }; };
        template = {
          metadata.labels.app = "open-webui";
          spec = {
            serviceAccountName = "open-webui";
            nodeSelector."kubernetes.io/hostname" = "nexus";
            containers = {
              _namedlist = true;
              open-webui = {
                image = "ghcr.io/open-webui/open-webui:0.6.5"; imagePullPolicy = "IfNotPresent";
                env = {
                  _namedlist = true;
                  OLLAMA_BASE_URLS = { name = "OLLAMA_BASE_URLS"; value = "http://10.1.1.110:8080/v1"; };
                  ENABLE_OLLAMA = { name = "ENABLE_OLLAMA"; value = "true"; };
                  ENABLE_OPENAI_API = { name = "ENABLE_OPENAI_API"; value = "false"; };
                  ENABLE_LLM = { name = "ENABLE_LLM"; value = "true"; };
                  ENABLE_SIGNUP = { name = "ENABLE_SIGNUP"; value = "true"; };
                  ENABLE_LDAP_LOGIN = { name = "ENABLE_LDAP_LOGIN"; value = "false"; };
                };
                ports = [{ containerPort = 8080; name = "http"; protocol = "TCP"; }];
                livenessProbe = { httpGet = { path = "/"; port = 8080; }; initialDelaySeconds = 60; periodSeconds = 30; failureThreshold = 3; };
                readinessProbe = { httpGet = { path = "/"; port = 8080; }; initialDelaySeconds = 30; periodSeconds = 10; failureThreshold = 3; };
                volumeMounts = { _namedlist = true; webui-data = { mountPath = "/app/backend/data"; }; };
                resources = { requests = { cpu = "500m"; memory = "1Gi"; }; limits = { cpu = "2"; memory = "4Gi"; }; };
              };
            };
            volumes = { _namedlist = true; webui-data = { hostPath = { path = "/mnt/open-webui-data"; type = "DirectoryOrCreate"; }; }; };
          };
        };
      };
    };

    Service.open-webui = {
      metadata.labels.app = "open-webui";
      spec = { type = "NodePort"; ports = [{ name = "http"; port = 8080; protocol = "TCP"; targetPort = 8080; nodePort = 32080; }]; selector.app = "open-webui"; };
    };

    Ingress.llama-server = {
      metadata = { labels."app.kubernetes.io/name" = "llama-server"; annotations."caddy.ingress.kubernetes.io/disable-ssl-redirect" = "true"; };
      spec = { ingressClassName = "caddy"; rules = [
        { host = "ai.lan"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "llama-server-zephyr"; port.number = 1235; }; }]; }
        { host = "ai.cluster.local"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "llama-server-zephyr"; port.number = 1235; }; }]; }
      ]; };
    };

    Ingress.openwebui = {
      metadata = { labels."app.kubernetes.io/name" = "openwebui"; annotations."caddy.ingress.kubernetes.io/disable-ssl-redirect" = "true"; };
      spec = { ingressClassName = "caddy"; rules = [
        { host = "openwebui.lan"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "open-webui"; port.number = 8080; }; }]; }
        { host = "openwebui.cluster.local"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "open-webui"; port.number = 8080; }; }]; }
      ]; };
    };

    Role.n8n-role.rules = [{ apiGroups = [""]; resources = ["configmaps" "secrets" "persistentvolumeclaims"]; verbs = ["get" "list" "watch" "create" "update"]; }];

    RoleBinding.n8n-rolebinding = {
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "Role"; name = "n8n-role"; };
      subjects = [{ kind = "ServiceAccount"; name = "n8n-sa"; }];
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
      metadata.labels.app = "ai-inference-gateway";
      spec = {
        type = "ClusterIP";
        clusterIP = "None";  # Headless, backed by Endpoints below
        ports = [{ name = "http"; port = 8080; protocol = "TCP"; }];
      };
    };

    # Static endpoint pointing to systemd gateway on nexus
    Endpoints.ai-inference-gateway = {
      metadata.labels.app = "ai-inference-gateway";
      subsets = [{
        addresses = [{ ip = "10.1.1.120"; }];
        ports = [{ name = "http"; port = 8080; protocol = "TCP"; }];
      }];
    };

    # ── NetworkPolicies ────────────────────────────────────────
    NetworkPolicy.default-deny = {
      spec = {
        podSelector = { };
        policyTypes = [ "Ingress" "Egress" ];
      };
    };
    NetworkPolicy.allow-internal = {
      spec = {
        podSelector = { };
        policyTypes = [ "Ingress" "Egress" ];
        ingress = [{ from = [{ namespaceSelector.matchLabels.name = "ai-inference"; }]; }];
        egress = [
          { to = [{ namespaceSelector.matchLabels.name = "ai-inference"; }]; }
          { to = [{ namespaceSelector = { }; podSelector.matchLabels."k8s-app" = "kube-dns"; }]; ports = [{ protocol = "UDP"; port = 53; } { protocol = "TCP"; port = 53; }]; }
        ];
      };
    };

    # Qdrant vector database — migrated from systemd to K8s StatefulSet
    StatefulSet.qdrant = {
      metadata.labels.app = "qdrant";
      spec = {
        serviceName = "qdrant";
        replicas = 1;
        selector.matchLabels.app = "qdrant";
        template = {
          metadata.labels.app = "qdrant";
          spec = {
            nodeName = "nexus";
            containers = [{
              name = "qdrant";
              image = "docker.io/qdrant/qdrant:v1.13.4";
              ports = [
                { containerPort = 6333; name = "http"; }
                { containerPort = 6334; name = "grpc"; }
              ];
              volumeMounts = [{
                name = "qdrant-data";
                mountPath = "/qdrant/storage";
              }];
              resources = {
                requests.memory = "256Mi";
                limits.memory = "4Gi";
              };
              readinessProbe = {
                httpGet = { path = "/healthz"; port = 6333; };
                initialDelaySeconds = 5;
                periodSeconds = 10;
              };
              livenessProbe = {
                httpGet = { path = "/healthz"; port = 6333; };
                initialDelaySeconds = 15;
                periodSeconds = 20;
              };
            }];
          };
        };
        volumeClaimTemplates = [{
          metadata.name = "qdrant-data";
          spec = {
            accessModes = ["ReadWriteOnce"];
            resources.requests.storage = "10Gi";
          };
        }];
      };
    };


    # ── LimitRange ───────────────────────────────────────────────
    # Fixed version: does NOT auto-assign GPUs to all pods
    # GPU workloads must explicitly request GPUs in their deployment specs
    LimitRange.ai-inference-limits = {
      metadata.labels.app = "gpu-scheduler";
      spec.limits = [{
        type = "Container";
        default = { cpu = "2"; memory = "4Gi"; };
        defaultRequest = { cpu = "500m"; memory = "1Gi"; };
        max = { cpu = "8"; memory = "16Gi"; "nvidia.com/gpu" = "1"; };
        min = { cpu = "100m"; memory = "128Mi"; };
        maxLimitRequestRatio = { cpu = "10"; memory = "4"; };
      }];
    };

    # ── Knowledge Fabric API ─────────────────────────────────────
    Deployment.knowledge-fabric-api = {
      metadata.labels = { app = "knowledge-fabric-api"; component = "brain"; };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "knowledge-fabric-api";
        strategy.type = "Recreate";
        template = {
          metadata.labels = { app = "knowledge-fabric-api"; component = "brain"; };
          spec = {
            nodeName = "nexus";
            automountServiceAccountToken = false;
            securityContext = { runAsNonRoot = true; runAsUser = 1000; runAsGroup = 1000; fsGroup = 1000; seccompProfile.type = "RuntimeDefault"; };
            containers = [{
              name = "knowledge-fabric-api";
              image = "nginx:alpine";
              imagePullPolicy = "IfNotPresent";
              securityContext = { allowPrivilegeEscalation = false; capabilities.drop = ["ALL"]; };
              ports = [{ name = "http"; containerPort = 3000; protocol = "TCP"; }];
              resources = { requests = { cpu = "100m"; memory = "128Mi"; }; limits = { cpu = "500m"; memory = "256Mi"; }; };
              readinessProbe = { httpGet = { path = "/"; port = "http"; }; initialDelaySeconds = 5; periodSeconds = 10; timeoutSeconds = 5; failureThreshold = 6; };
              livenessProbe = { httpGet = { path = "/"; port = "http"; }; initialDelaySeconds = 15; periodSeconds = 30; timeoutSeconds = 10; failureThreshold = 3; };
            }];
            tolerations = [
              { key = "workstation"; operator = "Equal"; value = "true"; effect = "NoSchedule"; }
              { key = "interactive"; operator = "Equal"; value = "true"; effect = "NoExecute"; }
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
        ports = [{ name = "http"; port = 3000; targetPort = 3000; protocol = "TCP"; }];
      };
    };

    Ingress.knowledge-fabric-api = {
      metadata = { labels."app.kubernetes.io/name" = "knowledge-fabric-api"; annotations."caddy.ingress.kubernetes.io/disable-ssl-redirect" = "true"; };
      spec = { ingressClassName = "caddy"; rules = [
        { host = "brain.lan"; http.paths = [{ path = "/"; pathType = "Prefix"; backend.service = { name = "knowledge-fabric-api"; port.number = 3000; }; }]; }
      ]; };
    };

    # ── Embed Server (HuggingFace TEI) ───────────────────────────
    Deployment.embed-server = {
      metadata.labels = { app = "embed-server"; component = "embeddings"; };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "embed-server";
        strategy.type = "Recreate";
        template = {
          metadata.labels = { app = "embed-server"; component = "embeddings"; };
          spec = {
            nodeName = "nexus";
            automountServiceAccountToken = false;
            securityContext = { runAsNonRoot = true; runAsUser = 1000; runAsGroup = 1000; fsGroup = 1000; seccompProfile.type = "RuntimeDefault"; };
            containers = [{
              name = "embed-server";
              image = "ghcr.io/huggingface/text-embeddings-inference:cpu-1.5";
              imagePullPolicy = "IfNotPresent";
              args = ["--model-id" "nomic-ai/nomic-embed-text-v2-moe"];
              securityContext = { allowPrivilegeEscalation = false; readOnlyRootFilesystem = true; capabilities.drop = ["ALL"]; };
              ports = [{ name = "http"; containerPort = 80; protocol = "TCP"; }];
              env = [{ name = "HF_HOME"; value = "/tmp/.cache/huggingface"; }];
              resources = { requests = { cpu = "1"; memory = "1Gi"; }; limits = { cpu = "2"; memory = "2Gi"; }; };
              readinessProbe = { httpGet = { path = "/health"; port = "http"; }; initialDelaySeconds = 30; periodSeconds = 10; timeoutSeconds = 5; failureThreshold = 6; };
              livenessProbe = { httpGet = { path = "/health"; port = "http"; }; initialDelaySeconds = 60; periodSeconds = 30; timeoutSeconds = 10; failureThreshold = 3; };
              volumeMounts = [{ name = "tmp"; mountPath = "/tmp"; } { name = "cache"; mountPath = "/.cache"; }];
            }];
            volumes = [
              { name = "tmp"; emptyDir.sizeLimit = "1Gi"; }
              { name = "cache"; emptyDir.sizeLimit = "2Gi"; }
            ];
            tolerations = [
              { key = "workstation"; operator = "Equal"; value = "true"; effect = "NoSchedule"; }
              { key = "interactive"; operator = "Equal"; value = "true"; effect = "NoExecute"; }
            ];
          };
        };
      };
    };

    Service.embed-server = {
      metadata.labels.app = "embed-server";
      spec = {
        type = "NodePort";
        selector.app = "embed-server";
        ports = [{ name = "http"; port = 80; targetPort = 80; nodePort = 30880; protocol = "TCP"; }];
      };
    };

    # ── llama-server (Qwen on Nexus) ─────────────────────────────
    Deployment.llama-server = {
      metadata.labels = { app = "llama-cpp"; purpose = "llm-inference"; };
      spec = {
        replicas = 1; revisionHistoryLimit = 2;
        selector.matchLabels.app = "llama-cpp";
        strategy = { type = "RollingUpdate"; rollingUpdate = { maxSurge = 0; maxUnavailable = 1; }; };
        template = {
          metadata.labels.app = "llama-cpp";
          spec = {
            nodeName = "nexus";
            hostNetwork = true;
            containers = [{
              name = "llama-server";
              image = "alpine:latest";
              command = ["/run/current-system/sw/bin/llama-server"];
              args = ["--model=/models/Qwen3.5-0.8B.Q8_0.gguf" "--host=0.0.0.0" "--port=8080" "--ctx-size=16384" "--threads=16" "--metrics"];
              env = [{ name = "CUDA_VISIBLE_DEVICES"; value = ""; }];
              ports = [{ name = "http"; containerPort = 8080; hostPort = 8080; protocol = "TCP"; }];
              resources = { requests = { cpu = "2"; memory = "2Gi"; }; limits = { cpu = "8"; memory = "4Gi"; }; };
              volumeMounts = [
                { name = "models"; mountPath = "/models"; readOnly = true; }
                { name = "nixos-bin"; mountPath = "/run/current-system/sw/bin"; readOnly = true; }
                { name = "nixos-lib"; mountPath = "/run/current-system/sw/lib"; readOnly = true; }
              ];
              livenessProbe = { httpGet = { path = "/health"; port = 8080; }; initialDelaySeconds = 30; periodSeconds = 30; };
              readinessProbe = { httpGet = { path = "/health"; port = 8080; }; initialDelaySeconds = 10; periodSeconds = 10; };
            }];
            volumes = [
              { name = "models"; hostPath = { path = "/home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"; type = "Directory"; }; }
              { name = "nixos-bin"; hostPath = { path = "/run/current-system/sw/bin"; type = "Directory"; }; }
              { name = "nixos-lib"; hostPath = { path = "/run/current-system/sw/lib"; type = "Directory"; }; }
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
        ports = [{ port = 8080; targetPort = 8080; protocol = "TCP"; name = "http"; }];
      };
    };

    # ── llama-cpp-qwen Service+Endpoints (Nexus hostNetwork) ─────
    Service.llama-cpp-qwen = {
      metadata.labels.app = "llama-cpp";
      spec = {
        type = "ClusterIP";
        ports = [
          { port = 8080; targetPort = 8080; protocol = "TCP"; name = "http"; }
          { port = 9090; targetPort = 9090; protocol = "TCP"; name = "metrics"; }
        ];
      };
    };

    Endpoints.llama-cpp-qwen = {
      metadata.labels.app = "llama-cpp";
      subsets = [{
        addresses = [{ ip = "10.1.1.120"; }];
        ports = [
          { port = 8080; name = "http"; protocol = "TCP"; }
          { port = 9090; name = "metrics"; protocol = "TCP"; }
        ];
      }];
    };

    # ── MCP Gateway Proxy DaemonSet ──────────────────────────────
    # Forwards localhost:8080 to AI Inference Gateway NodePort on each node
    DaemonSet.mcp-gateway-proxy = {
      metadata.labels.app = "mcp-gateway-proxy";
      spec = {
        selector.matchLabels.app = "mcp-gateway-proxy";
        template = {
          metadata.labels.app = "mcp-gateway-proxy";
          spec = {
            hostNetwork = true;
            tolerations = [{ key = "CriticalAddonsOnly"; operator = "Exists"; }];
            containers = [{
              name = "socat";
              image = "alpine/socat:latest";
              command = ["socat" "TCP-LISTEN:8080,fork,reuseaddr,bind=127.0.0.1" "TCP:localhost:30880"];
              resources = { limits = { memory = "128Mi"; cpu = "100m"; }; requests = { memory = "64Mi"; cpu = "50m"; }; };
              securityContext = { allowPrivilegeEscalation = false; capabilities = { drop = ["ALL"]; add = ["NET_BIND_SERVICE" "NET_ADMIN"]; }; };
            }];
          };
        };
      };
    };

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
            containers = [{
              name = "redis";
              image = "redis:7-alpine";
              command = ["redis-server" "--save" "" "--appendonly" "no"];
              args = ["--maxmemory" "256mb" "--maxmemory-policy" "allkeys-lru"];
              ports = [{ containerPort = 6379; name = "redis"; }];
              resources = { requests = { cpu = "100m"; memory = "128Mi"; }; limits = { cpu = "500m"; memory = "512Mi"; }; };
              volumeMounts = [{ name = "redis-data"; mountPath = "/data"; }];
            }];
            volumes = [{ name = "redis-data"; emptyDir.sizeLimit = "512Mi"; }];
          };
        };
      };
    };

    Service.redis-service = {
      metadata.labels.app = "redis";
      spec = {
        type = "ClusterIP";
        selector.app = "redis";
        ports = [{ port = 6379; targetPort = 6379; name = "redis"; }];
      };
    };

    # ── SearXNG MCP Server ───────────────────────────────────────
    Deployment.searxng-mcp = {
      metadata.labels.app = "searxng-mcp";
      spec = {
        replicas = 1;
        selector.matchLabels.app = "searxng-mcp";
        template = {
          metadata.labels.app = "searxng-mcp";
          spec = {
            serviceAccountName = "searxng-mcp";
            securityContext = { runAsNonRoot = true; runAsUser = 1000; fsGroup = 1000; };
            containers = [{
              name = "searxng-mcp";
              image = "ghcr.io/reverb256/ai-inference-gateway:latest";
              imagePullPolicy = "Always";
              command = ["python" "-m" "ai_inference_gateway.mcp_servers.searxng_server"];
              env = [
                { name = "SEARXNG_URL"; valueFrom.configMapKeyRef = { name = "searxng-mcp-config"; key = "SEARXNG_URL"; }; }
                { name = "SEARXNG_CACHE_TTL"; valueFrom.configMapKeyRef = { name = "searxng-mcp-config"; key = "SEARXNG_CACHE_TTL"; }; }
                { name = "PYTHONPATH"; value = "/app"; }
              ];
              resources = { requests = { cpu = "100m"; memory = "128Mi"; }; limits = { cpu = "500m"; memory = "512Mi"; }; };
              livenessProbe = { httpGet = { path = "/health"; port = 3000; }; initialDelaySeconds = 10; periodSeconds = 30; };
              readinessProbe = { httpGet = { path = "/health"; port = 3000; }; initialDelaySeconds = 5; periodSeconds = 10; };
              securityContext = { allowPrivilegeEscalation = false; capabilities.drop = ["ALL"]; readOnlyRootFilesystem = true; };
            }];
          };
        };
      };
    };

    Service.searxng-mcp = {
      metadata.labels.app = "searxng-mcp";
      spec = {
        type = "ClusterIP";
        selector.app = "searxng-mcp";
        ports = [{ name = "mcp"; protocol = "TCP"; port = 3000; targetPort = 3000; }];
      };
    };

    NetworkPolicy.searxng-mcp-egress = {
      spec = {
        podSelector.matchLabels.app = "searxng-mcp";
        policyTypes = ["Egress"];
        egress = [
          { to = [{ namespaceSelector.matchLabels.name = "kube-system"; }]; ports = [{ protocol = "UDP"; port = 53; }]; }
          { to = [{ namespaceSelector.matchLabels.name = "search"; }]; ports = [{ protocol = "TCP"; port = 8080; }]; }
        ];
      };
    };

    # ── Observability (Prometheus + Grafana) ─────────────────────
    ServiceAccount.grafana-sa.automountServiceAccountToken = false;

    ClusterRole.prometheus.rules = [
      { apiGroups = [""]; resources = ["nodes" "nodes/proxy" "services" "endpoints" "pods"]; verbs = ["get" "list" "watch"]; }
      { nonResourceURLs = ["/metrics"]; verbs = ["get"]; }
    ];

    ClusterRoleBinding.prometheus = {
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "ClusterRole"; name = "prometheus"; };
      subjects = [{ kind = "ServiceAccount"; name = "prometheus"; namespace = "ai-inference"; }];
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
            containers = [{
              name = "prometheus";
              image = "prom/prometheus:v2.53.0";
              args = ["--config.file=/etc/prometheus/prometheus.yml" "--storage.tsdb.path=/prometheus" "--web.console.libraries=/etc/prometheus/console_libraries" "--web.console.templates=/etc/prometheus/consoles" "--storage.tsdb.retention.time=30d" "--web.enable-lifecycle"];
              ports = [{ containerPort = 9090; name = "http"; }];
              env = [{ name = "POD_IP"; valueFrom.fieldRef.fieldPath = "status.podIP"; }];
              volumeMounts = [{ name = "config"; mountPath = "/etc/prometheus"; } { name = "storage"; mountPath = "/prometheus"; }];
              livenessProbe = { httpGet = { path = "/-/healthy"; port = 9090; }; initialDelaySeconds = 30; periodSeconds = 10; };
              readinessProbe = { httpGet = { path = "/-/ready"; port = 9090; }; initialDelaySeconds = 30; periodSeconds = 5; };
              resources = { requests = { cpu = "200m"; memory = "512Mi"; }; limits = { cpu = "1"; memory = "2Gi"; }; };
            }];
            volumes = [
              { name = "config"; configMap.name = "prometheus-config"; }
              { name = "storage"; emptyDir.sizeLimit = "4Gi"; }
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
        ports = [{ port = 9090; targetPort = 9090; name = "http"; }];
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
            containers = [{
              name = "grafana";
              image = "grafana/grafana:11.1.0";
              env = [
                { name = "GF_SECURITY_ADMIN_USER"; value = "admin"; }
                { name = "GF_SECURITY_ADMIN_PASSWORD"; value = "admin"; }
                { name = "GF_USERS_ALLOW_SIGN_UP"; value = "false"; }
                { name = "GF_INSTALL_PLUGINS"; value = ""; }
                { name = "GF_SERVER_ROOT_URL"; value = "http://localhost:3000"; }
              ];
              ports = [{ containerPort = 3000; name = "http"; }];
              resources = { requests = { cpu = "100m"; memory = "128Mi"; }; limits = { cpu = "500m"; memory = "512Mi"; }; };
            }];
          };
        };
      };
    };

    Service.grafana = {
      metadata.labels.app = "grafana";
      spec = {
        type = "ClusterIP";
        selector.app = "grafana";
        ports = [{ port = 3000; targetPort = 3000; name = "http"; }];
      };
    };

    Role.grafana-role.rules = [{ apiGroups = [""]; resources = ["configmaps" "secrets"]; verbs = ["get" "list" "watch"]; }];

    RoleBinding.grafana-rolebinding = {
      roleRef = { apiGroup = "rbac.authorization.k8s.io"; kind = "Role"; name = "grafana-role"; };
      subjects = [{ kind = "ServiceAccount"; name = "grafana-sa"; }];
    };

    # ── Secrets ──────────────────────────────────────────────────
    # Note: Secrets with sensitive data should ideally be managed via agenix
    Secret.open-webui-secrets = {
      type = "Opaque";
      stringData.webui-secret-key = "";
    };

    Secret.ai-inference-gateway-secrets = {
      type = "Opaque";
      stringData = {
        "zai-api-key" = "YOUR_ZAI_API_KEY_HERE";
        "api-keys" = ''
          default=sk-rep...-key
        '';
      };
    };

    # ── Additional NetworkPolicies ───────────────────────────────
    # Allow SearXNG pods to reach AI Inference Gateway
    NetworkPolicy.allow-search-to-gateway = {
      spec = {
        podSelector.matchLabels.app = "ai-inference-gateway";
        policyTypes = ["Ingress"];
        ingress = [{
          from = [{ namespaceSelector.matchLabels.name = "search"; podSelector.matchLabels.app = "searxng"; }];
          ports = [{ protocol = "TCP"; port = 8080; }];
        }];
      };
    };

    # Allow gateway ingress from ingress-system and intra-namespace
    NetworkPolicy.allow-gateway-ingress = {
      spec = {
        podSelector.matchLabels.app = "ai-inference-gateway";
        policyTypes = ["Ingress"];
        ingress = [
          { from = [{ namespaceSelector.matchLabels.name = "ingress-system"; }]; ports = [{ protocol = "TCP"; port = 8080; }]; }
          { from = [{ podSelector = { }; }]; ports = [{ protocol = "TCP"; port = 8080; }]; }
        ];
      };
    };

    # Allow gateway egress to dependencies
    NetworkPolicy.allow-gateway-egress = {
      spec = {
        podSelector.matchLabels.app = "ai-inference-gateway";
        policyTypes = ["Egress"];
        egress = [
          { to = [{ namespaceSelector.matchLabels.name = "kube-system"; }]; ports = [{ protocol = "UDP"; port = 53; }]; }
          { ports = [{ protocol = "TCP"; port = 443; }]; }
          { to = [{ namespaceSelector.matchLabels.name = "search"; }]; ports = [{ protocol = "TCP"; port = 8080; }]; }
          { to = [{ podSelector.matchLabels.app = "qdrant"; }]; ports = [{ protocol = "TCP"; port = 6333; }]; }
          { to = [{ podSelector.matchLabels.app = "llama-cpp"; }]; ports = [{ protocol = "TCP"; port = 8083; }]; }
        ];
      };
    };

    # Open WebUI network policy
    NetworkPolicy.open-webui = {
      spec = {
        podSelector.matchLabels.app = "open-webui";
        policyTypes = ["Ingress" "Egress"];
        ingress = [
          { from = [{ namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "ingress-system"; }]; ports = [{ port = 8080; protocol = "TCP"; }]; }
          { from = [{ podSelector = { }; }]; }
        ];
        egress = [{ }];
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
            containers = [{
              name = "kb-mcp";
              image = "localhost/kb-mcp:latest";
              imagePullPolicy = "Never";
              ports = [{ containerPort = 8080; name = "http"; protocol = "TCP"; }];
              env = [
                { name = "QDRANT_HOST"; value = "qdrant-service.ai-inference.svc.cluster.local"; }
                { name = "QDRANT_PORT"; value = "6333"; }
                { name = "KB_PORT"; value = "8080"; }
                { name = "KB_HOST"; value = "0.0.0.0"; }
                { name = "KB_COLLECTION"; value = "knowledge_base"; }
                { name = "KB_MODEL"; value = "all-MiniLM-L6-v2"; }
                { name = "PYTHONUNBUFFERED"; value = "1"; }
                { name = "HOME"; value = "/tmp"; }
                { name = "USER"; value = "kb-mcp"; }
                { name = "HF_HOME"; value = "/tmp/huggingface"; }
                { name = "TRANSFORMERS_CACHE"; value = "/tmp/huggingface/transformers"; }
              ];
              resources = {
                requests = { cpu = "1"; memory = "2Gi"; };
                limits = { cpu = "2"; memory = "4Gi"; };
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
              volumeMounts = [{ name = "huggingface-cache"; mountPath = "/tmp/huggingface"; }];
            }];
            volumes = [{
              name = "huggingface-cache";
              emptyDir.sizeLimit = "1Gi";
            }];
            tolerations = [
              { key = "workstation"; operator = "Equal"; value = "true"; effect = "NoSchedule"; }
              { key = "interactive"; operator = "Equal"; value = "true"; effect = "NoExecute"; }
            ];
          };
        };
      };
    };

    Service.kb-mcp = {
      metadata.labels = { app = "kb-mcp"; component = "rag"; };
      spec = {
        type = "ClusterIP";
        ports = [{ port = 8080; targetPort = 8080; name = "http"; protocol = "TCP"; }];
        selector.app = "kb-mcp";
      };
    };

    # ── Claude Code (in ai-inference namespace) ───────────────────
    # Replaces: kubernetes-manifests/claude/claude-deployment.yaml,
    #           claude-hpa.yaml, claude-service.yaml, claude-metrics-exporter.yaml
    #           kubernetes-manifests/ai-coding-tools/00-storage.yaml

    PersistentVolume.ai-coding-tools-pv = {
      spec = {
        capacity.storage = "10Gi";
        accessModes = [ "ReadWriteMany" ];
        persistentVolumeReclaimPolicy = "Retain";
        hostPath = { path = "/home/j_kro"; type = "Directory"; };
      };
    };

    PersistentVolumeClaim.ai-coding-tools-config = {
      spec = {
        accessModes = [ "ReadWriteMany" ];
        resources.requests.storage = "10Gi";
        volumeName = "ai-coding-tools-pv";
      };
    };

    Deployment.claude-code = {
      metadata.labels = { app = "claude-code"; version = "v1"; };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "claude-code";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = { maxSurge = 0; maxUnavailable = 1; };
        };
        template = {
          metadata = {
            labels = { app = "claude-code"; version = "v1"; };
            annotations = {
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "9090";
              "prometheus.io/path" = "/metrics";
            };
          };
          spec = {
            tolerations = [{ key = "nvidia.com/gpu"; operator = "Exists"; effect = "NoSchedule"; }];
            priorityClassName = "production-workload-critical";
            affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution = [{
              weight = 100;
              podAffinityTerm = {
                labelSelector.matchExpressions = [{
                  key = "app"; operator = "In"; values = [ "claude-code" ];
                }];
                topologyKey = "kubernetes.io/hostname";
              };
            }];
            containers = [{
              name = "claude-code";
              image = "ghcr.io/anthropics/claude-code:latest";
              imagePullPolicy = "Always";
              ports = [
                { containerPort = 8080; name = "http"; protocol = "TCP"; }
                { containerPort = 9090; name = "metrics"; protocol = "TCP"; }
              ];
              env = [
                { name = "AI_INFERENCE_GATEWAY_URL"; value = "http://10.1.1.110:8083"; }
                { name = "DATABASE_URL"; valueFrom.secretKeyRef = { name = "claude-secrets"; key = "database-url"; }; }
                { name = "ANTHROPIC_API_KEY"; valueFrom.secretKeyRef = { name = "claude-secrets"; key = "anthropic-api-key"; }; }
                { name = "LOG_LEVEL"; value = "info"; }
                { name = "MAX_CONVERSATIONS"; value = "50"; }
              ];
              resources = {
                requests = { cpu = "500m"; memory = "512Mi"; };
                limits = { cpu = "2000m"; memory = "2Gi"; };
              };
              livenessProbe = {
                httpGet = { path = "/health"; port = "http"; };
                initialDelaySeconds = 30; periodSeconds = 10; timeoutSeconds = 5; failureThreshold = 3;
              };
              readinessProbe = {
                httpGet = { path = "/ready"; port = "http"; };
                initialDelaySeconds = 10; periodSeconds = 5; timeoutSeconds = 3; failureThreshold = 2;
              };
              lifecycle.preStop.exec.command = [ "/bin/sh" "-c" "sleep 30" ];
            }];
            terminationGracePeriodSeconds = 60;
            dnsPolicy = "ClusterFirst";
          };
        };
      };
    };

    Service.claude-code = {
      metadata = {
        labels.app = "claude-code";
        annotations = {
          "prometheus.io/scrape" = "true";
          "prometheus.io/port" = "9090";
          "prometheus.io/path" = "/metrics";
        };
      };
      spec = {
        type = "ClusterIP";
        selector.app = "claude-code";
        ports = [
          { name = "http"; port = 8080; targetPort = "http"; protocol = "TCP"; }
          { name = "metrics"; port = 9090; targetPort = "metrics"; protocol = "TCP"; }
        ];
        sessionAffinity = "ClientIP";
        sessionAffinityConfig.clientIP.timeoutSeconds = 3600;
      };
    };

    HorizontalPodAutoscaler.claude-code-hpa = {
      spec = {
        scaleTargetRef = { apiVersion = "apps/v1"; kind = "Deployment"; name = "claude-code"; };
        minReplicas = 1;
        maxReplicas = 10;
        metrics = [
          { type = "Pods"; pods = { metric.name = "active_conversations"; target = { type = "AverageValue"; averageValue = "40"; }; }; }
          { type = "Resource"; resource = { name = "cpu"; target = { type = "Utilization"; averageUtilization = 70; }; }; }
          { type = "Resource"; resource = { name = "memory"; target = { type = "Utilization"; averageUtilization = 80; }; }; }
        ];
        behavior = {
          scaleUp = {
            stabilizationWindowSeconds = 30;
            policies = [
              { type = "Percent"; value = 100; periodSeconds = 30; }
              { type = "Pods"; value = 2; periodSeconds = 30; }
            ];
            selectPolicy = "Max";
          };
          scaleDown = {
            stabilizationWindowSeconds = 300;
            policies = [
              { type = "Percent"; value = 50; periodSeconds = 60; }
              { type = "Pods"; value = 1; periodSeconds = 60; }
            ];
            selectPolicy = "Min";
          };
        };
      };
    };

    # ── Claude Metrics Exporter ──────────────────────────────────
    ConfigMap.claude-metrics-exporter-config.data."config.yaml" = ''
      server:
        port: 9090
        path: /metrics
      database:
        host: postgres-n8n.ai-inference.svc.cluster.local
        port: 5432
        database: claude
        user: claude
        sslmode: disable
      metrics:
        active_conversations:
          query: |
            SELECT COUNT(DISTINCT session_id) FROM conversations WHERE created_at > NOW() - INTERVAL '1 hour' AND status = 'active'
          interval: 10s
        total_conversations:
          query: |
            SELECT COUNT(*) FROM conversations WHERE created_at > NOW() - INTERVAL '24 hours'
          interval: 30s
        avg_response_time:
          query: |
            SELECT AVG(response_time_ms) FROM conversation_metrics WHERE timestamp > NOW() - INTERVAL '5 minutes'
          interval: 15s
    '';

    Deployment.claude-metrics-exporter = {
      metadata.labels.app = "claude-metrics-exporter";
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "claude-metrics-exporter";
        template = {
          metadata = {
            labels.app = "claude-metrics-exporter";
            annotations = {
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "9090";
              "prometheus.io/path" = "/metrics";
            };
          };
          spec = {
            containers = [{
              name = "exporter";
              image = "python:3.11-slim";
              command = [ "/bin/bash" "-c" ''
                cat <<'SCRIPT' > /app/exporter.py
                #!/usr/bin/env python3
                import os, time, psycopg2
                from prometheus_client import Counter, Gauge, start_http_server
                ACTIVE = Gauge('claude_active_conversations', 'Active conversations')
                TOTAL = Gauge('claude_total_conversations_24h', 'Total 24h conversations')
                AVG_RT = Gauge('claude_avg_response_time_ms', 'Avg response time ms')
                def get_db():
                    return psycopg2.connect(
                        host=os.getenv('DB_HOST','postgres-n8n.ai-inference.svc.cluster.local'),
                        port=int(os.getenv('DB_PORT',5432)),
                        database=os.getenv('DB_NAME','claude'),
                        user=os.getenv('DB_USER','claude'),
                        password=os.getenv('DB_PASSWORD'),
                        connect_timeout=5)
                def update():
                    try:
                        conn = get_db(); cur = conn.cursor()
                        cur.execute("SELECT COUNT(DISTINCT session_id) FROM conversations WHERE created_at > NOW() - INTERVAL '1 hour' AND status = 'active'")
                        ACTIVE.set(cur.fetchone()[0] or 0)
                        cur.execute("SELECT COUNT(*) FROM conversations WHERE created_at > NOW() - INTERVAL '24 hours'")
                        TOTAL.set(cur.fetchone()[0] or 0)
                        cur.execute("SELECT AVG(response_time_ms) FROM conversation_metrics WHERE timestamp > NOW() - INTERVAL '5 minutes'")
                        r = cur.fetchone()[0]
                        if r: AVG_RT.set(r)
                        cur.close(); conn.close()
                    except Exception as e: print(f"Error: {e}")
                if __name__ == '__main__':
                    start_http_server(9090)
                    while True: update(); time.sleep(15)
                SCRIPT
                pip install psycopg2-binary prometheus_client
                python3 /app/exporter.py
              ''];
              env = [
                { name = "DB_HOST"; value = "postgres-n8n.ai-inference.svc.cluster.local"; }
                { name = "DB_PORT"; value = "5432"; }
                { name = "DB_NAME"; value = "claude"; }
                { name = "DB_USER"; valueFrom.secretKeyRef = { name = "claude-secrets"; key = "database-user"; }; }
                { name = "DB_PASSWORD"; valueFrom.secretKeyRef = { name = "claude-secrets"; key = "database-password"; }; }
              ];
              ports = [{ containerPort = 9090; name = "metrics"; protocol = "TCP"; }];
              resources = {
                requests = { cpu = "50m"; memory = "64Mi"; };
                limits = { cpu = "100m"; memory = "128Mi"; };
              };
              livenessProbe = {
                httpGet = { path = "/metrics"; port = "metrics"; };
                initialDelaySeconds = 10; periodSeconds = 30;
              };
              readinessProbe = {
                httpGet = { path = "/metrics"; port = "metrics"; };
                initialDelaySeconds = 5; periodSeconds = 10;
              };
            }];
          };
        };
      };
    };
  };
}
