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
      qdrantUrl = "http://qdrant.ai-inference.svc.cluster.local:6333"; # K8s service DNS
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
  
  # Push gateway image to local container registry after k3s loads it.
  # Needed for HA: sentry gateway pod pulls from nexus:5000 instead of needing pre-loaded image.
  systemd.services.push-gateway-to-registry = {
    description = "Push gateway container image to local registry";
    after = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.podman ];
    serviceConfig.Type = "oneshot";
    script = let
      gwImage = "nexus:5000/ai-inference-gateway:2.4.9";
      srcImage = "docker.io/library/ai-inference-gateway:2.4.9";
    in ''
      # Wait for local registry to be ready
      timeout 120 bash -c 'until curl -sf http://nexus:5000/v2/ > /dev/null 2>&1; do sleep 5; done'

      # Export from containerd, load into podman, tag and push
      sudo ctr -n k8s.io images export /tmp/gw-push.tar ${srcImage} 2>/dev/null || {
        echo "Gateway image not found in containerd, skipping push"
        exit 0
      }
      sudo podman load -i /tmp/gw-push.tar
      sudo podman tag ${srcImage} ${gwImage}
      sudo podman push --tls-verify=false ${gwImage}
      sudo rm -f /tmp/gw-push.tar
      echo "Gateway image pushed to local registry"
    '';
  };
};
}
