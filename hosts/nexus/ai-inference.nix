# AI Inference Service Configuration for Nexus
# RTX 3060 Ti (8GB)
# Storage and GPU compute node
# Note: ai-inference module is already imported via ../../modules/default.nix
{ lib, ... }: {
  # Enable AI inference service
  services.ai-inference = {
    enable = true;

    # Backend: Use ZAI or other remote service (LM Studio removed)
    backend = {
      type = "zai"; # Using ZAI backend (LM Studio removed)
      zai = {
        enable = true;
        apiKeyFile = "/run/agenix/zai-api-key";
      };
    };

    # Gateway configuration - ENABLED on Nexus
    gateway = {
      enable = true; # ENABLED: Moved from Zephyr
      host = "10.1.1.120"; # Listen on all interfaces for cluster access
      port = 8080;
      workers = 4;

      # Enable Redis middleware for caching
      middleware.redis.enable = true;
    };

    # Intelligent routing
    routing = {
      enable = true;
      defaultModel = "qwen3.5-4b";
      rules = [
        {
          minTokens = 0;
          maxTokens = 4096;
          model = "qwen3.5-2b";
          priority = 10;
        }
        {
          minTokens = 4097;
          maxTokens = 32768;
          model = "qwen3.5-4b";
          priority = 20;
        }
        {
          minTokens = 32769;
          maxTokens = 999999;
          model = "qwen3.5-35b-a3b@q4_k_m";
          priority = 30;
        }
      ];
    };

    # Authentication: tailscale for network access
    auth = {
      mode = "none"; # Change to "tailscale" for network access
    };

    # Monitoring: integrate with existing Prometheus
    monitoring = {
      enable = true;
      port = 9090;
    };
  };

  # Open firewall for gateway and metrics (cluster access)
  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
    8080 # Gateway API
    9090 # Metrics
  ];
}
