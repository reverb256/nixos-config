# AI Inference Service Configuration for Zephyr
# RTX 3090 (24GB) + RTX 3060 Ti (8GB)
# Primary node for large context models
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Get Tailscale IP dynamically (for reference, actual detection happens at runtime)
  # Check current Tailscale IP with: ip -4 addr show tailscale0
in {
  # Import the AI inference module
  imports = [ ../../modules/services/ai-inference ];

  # Enable AI inference service
  services.ai-inference = {
    enable = true;

    # Backend: LM Studio headless (runs via systemd)
    backend = {
      url = "http://127.0.0.1:1234";  # LM Studio default
      type = "lm-studio";
    };

    # Enable LM Studio headless service
    lm-studio-headless = {
      enable = true;
      port = 1234;
      host = "127.0.0.1";
    };

    # Gateway configuration
    gateway = {
      enable = true;
      host = "127.0.0.1";  # Local only initially
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
      mode = "none";  # Change to "tailscale" for network access
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
