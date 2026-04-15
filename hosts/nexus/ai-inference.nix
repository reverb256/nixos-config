{ config, pkgs, lib, ... }: {
  services.ai-inference = {
    enable = true;

    backend = {
      url = "http://10.1.1.110:1235"; # zephyr llama-server
      type = "llama-cpp";
      local = {
        url = "http://10.1.1.110:1235";
        model = "gemma-4-e4b-it";
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
      enable = true;
      host = "0.0.0.0";
      port = 8080;
      workers = 1;
      middleware.redis.enable = true;
      middleware.knowledgeFabric = {
        enable = true;
        rrf_k = 60;
        rag_enabled = true;
        searxng_enabled = true;
        searxng_url = "http://10.1.1.120:30888"; # SearXNG NodePort on this host
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
      defaultModel = "gemma-4-e4b-it";
      fallbackChain = ["zai" "pollinations"];
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
      qdrantUrl = "http://127.0.0.1:6333";
      embeddingModel = "sentence-transformers/all-MiniLM-L6-v2";
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
        enable = false;  # nexus has no GPU, skip ~1.1GB reranker model
        model = "BAAI/bge-reranker-v2-base";
      };
      qdrant = {
        enable = true;
        host = "0.0.0.0";
        port = 6333;
        grpcPort = 6334;
        storagePath = "/var/lib/qdrant";
        memoryLimit = "4G";
      };
    };

    security = {
      maxRequestSize = 10485760;
      enableProxy = false;
    };
  };
}
