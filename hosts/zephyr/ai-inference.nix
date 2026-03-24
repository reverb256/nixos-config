# AI Inference Service Configuration for Zephyr
# RTX 3090 (24GB) + RTX 3060 Ti (8GB)
# Primary node for large context models
{...}: {
  # Import the AI inference module
  imports = [../../modules/services/ai-inference];

  # Enable AI inference service
  services.ai-inference = {
    enable = true;

    # Backend: Removed LM Studio (not used)
    # To use: Configure zai, vllm, or llama.cpp backend instead

    # Gateway configuration
    gateway = {
      enable = false; # DISABLED: Moved to Nexus due to memory constraints on Zephyr
      host = "127.0.0.1"; # Local only initially
      port = 8080;
      workers = 4;
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

    # Authentication: start with none (local), switch to tailscale for network access
    auth = {
      mode = "none"; # Change to "tailscale" for network access
      # For Tailscale, the gateway will need to be updated to listen on Tailscale IP
    };

    # Monitoring: integrate with existing Prometheus
    monitoring = {
      enable = true;
      port = 9090;
    };
  };

  # Optional: Open port for local network access
  # networking.firewall.allowedTCPPorts = [ 8080 ];
}
