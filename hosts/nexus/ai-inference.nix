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
        model = "Qwen3.5-4B-Q4_K_M.gguf";
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
      enable = false; # No host currently serving Qwen3.5-9B
      model = "Qwen3.5-4B.Q4_K_M.gguf"; # Fallback to sentry 4B if re-enabled
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

  # Push gateway image to local container registry after k3s loads it.
  # Needed for HA: sentry gateway pod pulls from nexus:5000 instead of needing pre-loaded image.
  systemd.services.push-gateway-to-registry = {
    description = "Push gateway image to local container registry";
    after = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.bash pkgs.podman pkgs.curl pkgs.coreutils ];
    serviceConfig.ExecStart = pkgs.writeShellScript "push-gateway-to-registry-start" ''
      set -euo pipefail

      gwImage="nexus:5000/ai-inference-gateway:2.4.9"
      srcImage="docker.io/library/ai-inference-gateway:2.4.9"
      registry="http://127.0.0.1:5000/v2"
      tmpfile="/tmp/gw-push.tar"

      # Wait for local registry to be ready (with timeout in script)
      elapsed=0
      until curl -sf "$registry/" > /dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge 300 ]; then
          echo "Registry not ready after 300s, skipping push"
          exit 0
        fi
      done

      # Check if image already exists in registry
      if curl -sf "$registry/$gwImage/manifests/latest" > /dev/null 2>&1; then
        echo "Gateway image already exists in registry, skipping push"
        exit 0
      fi

      # Export from containerd, load into podman, tag and push
      if ! sudo ctr -n k8s.io images export "$tmpfile" "$srcImage" 2>/dev/null; then
        echo "Gateway image not found in containerd, skipping push"
        exit 0
      fi

      sudo podman load -i "$tmpfile"
      sudo podman tag "$srcImage" "$gwImage"
      if sudo podman push --tls-verify=false "$gwImage"; then
        echo "Gateway image pushed to local registry"
      else
        echo "Podman push failed (registry or network issue)"
      fi

      sudo rm -f "$tmpfile"
    '';
  };

  # Disable jitterentropy service (CachyOS seccomp incompatibility)
  # Jitterentropy is killed by seccomp (SIGSYS) - CachyOS kernel blocks the syscalls it needs
  systemd.services.jitterentropy.enable = false;
}
      sudo podman load -i /tmp/gw-push.tar
      sudo podman tag ${srcImage} ${gwImage}
      sudo podman push --tls-verify=false ${gwImage}
      sudo rm -f /tmp/gw-push.tar
      echo "Gateway image pushed to local registry"
    '';
  };
}
