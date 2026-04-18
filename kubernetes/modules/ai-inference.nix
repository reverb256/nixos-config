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

    Service.qdrant = {
      metadata.labels.app = "qdrant";
      spec = {
        type = "ClusterIP";
        selector.app = "qdrant";
        ports = [
          { name = "http"; port = 6333; protocol = "TCP"; targetPort = 6333; }
          { name = "grpc"; port = 6334; protocol = "TCP"; targetPort = 6334; }
        ];
      };
    };
  };
}
