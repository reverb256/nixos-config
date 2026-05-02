{
  config,
  pkgs,
  lib,
  ...
}: {
  services.ai-inference = {
    enable = true;

    backend = {
      url = "http://zephyr.lan:1237"; # zephyr 3090 llama-server (Qwen3.6-35B-A3B, primary local model)
      type = "llama-cpp";
      local = {
        url = "http://sentry.lan:1235"; # sentry ROCm Qwen3.5-4B (K8s pod)
        model = "Qwen3.5-4B.Q4_K_M.gguf";
      };
        secondary = {
         url = "http://zephyr.lan:8040"; # zephyr 3060Ti Qwen3.5-2B-AWQ (vLLM, no thinking)
         model = "qwen3.5-2b-awq";
        };
      nvidia-nim = {
        enable = true;
        apiKeyFile = "/run/agenix/nvidia-api-key";
      };
      zai = {
        enable = true;
        apiKeyFile = "/run/agenix/zai-api-key";
        baseUrl = "https://api.z.ai/api/coding/paas/v4";
        enableRetry = true;
        maxRetries = 3;
        retryDelay = 1.0;
        timeout = 300.0;
      };
      pollinations = {
        enable = true;
        apiKeyFile = "/run/agenix/pollinations-api-key";
        baseUrl = "https://text.pollinations.ai";
      };
    };

    gateway = {
      enable = false; # disabled — K8s deployment handles gateway
      host = "0.0.0.0";
      port = 8080;
      workers = 1;
      middleware.redis = {
        enable = true;
        host = "valkey.search.svc.cluster.local"; # K8s service DNS (search namespace)
        port = 6379;
      };
      middleware.knowledgeFabric = {
        enable = true;
        rrf_k = 60;
        rag_enabled = true;
        searxng_enabled = true;
        searxng_url = "http://10.1.1.120:30888"; # NodePort — ClusterIP unreachable from host systemd
        searxng_max_results = 10;
        code_search_enabled = false;
        brain_wiki_enabled = true;
        brain_wiki_path = "/home/j_kro/brain/wiki";
        web_search_enabled = false;
        rag_top_k = 10;
      };
    };

    routing = {
      enable = true;
      defaultModel = "qwen3.6-35b"; # local-first (Qwen3.6-35B on zephyr 3090)
      fallbackChain = [
        "nvidia-nim"
        "nvidia-nim"
        "pollinations"
      ];
    };

    auth.mode = "none";

    monitoring = {
      enable = true;
    };

    rateLimit.enable = true;
    rateLimit.requestsPerMinute = 120;

    systemPrompts = {
      enable = true;
      default = "You are a helpful AI assistant with access to comprehensive knowledge sources.";
      coding = "You are an expert coding assistant. Write clean, efficient, and well-documented code.";
      reasoning = "You are an expert reasoning assistant. Think step-by-step and provide clear explanations.";
      custom = {
        nixos = "You are a NixOS configuration expert. Always use lib.mkOptionDefault for shared modules.";
        kubernetes = "You are a Kubernetes expert. Use best practices for manifests and troubleshooting.";
      };
    };

    rag = {
      enable = true;
      qdrantUrl = "http://10.5.93.32:6333"; # K8s service DNS
      embeddingModel = "BidirLM/BidirLM-Omni-2.5B-Embedding"; # 2048d, multimodal (text/image/audio)
      embeddingDevice = "cpu"; # nexus GPU occupied by lolMiner
      embeddingTrustRemoteCode = true; # BidirLM requires custom code
      embeddingDimensions = 2048;
      chunkSize = 512;
      chunkOverlap = 50;
      topK = 10;
      hybridSearch = {
        enable = true;
        vectorWeight = 0.7;
        bm25Weight = 0.3;
      };
      autoRag = {
        enable = true;
        threshold = 0.3;
      };
      tokenScopedCollections = true;
      reranker = {
        enable = true; # cross-encoder BGE-reranker-base on CPU
        model = "BAAI/bge-reranker-base";
      };
      qdrant = {
        enable = false; # Qdrant runs as K8s StatefulSet, not local systemd
        host = "0.0.0.0";
        port = 6333;
        grpcPort = 6334;
        storagePath = "/var/lib/qdrant";
        memoryLimit = "4G";
      };
    };

    # Phase 2 hybrid search features
    queryExpansion = {
      enable = true;
      model = "Qwen3.5-9B.Q4_K_M.gguf";
    };

    semanticCache = {
      enable = true;
      ttlSeconds = 86400; # 24h
      similarityThreshold = 0.95;
    };

    security = {
      maxRequestSize = 10485760;
      enableProxy = false;
    };
  };
}
