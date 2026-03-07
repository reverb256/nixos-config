# Example Service Gateway Configuration (Caddy)
# Add this to your /etc/nixos/configuration.nix

{ config, ... }: {
  # ============================================================================
  # SERVICE GATEWAY - Auto-generated subdomains for all services
  # ============================================================================
  services.service-gateway = {
    enable = true;

    # Public access (set to true to expose to LAN)
    publicAccess = false;

    services = {
      # ============================================================
      # AI / INFERENCE
      # ============================================================
      ai-gateway = {
        description = "AI Inference Gateway - OpenAI-compatible API";
        port = 8080;
        websocket = true;
      };

      vllm = {
        description = "vLLM - Local LLM inference backend";
        port = 8000;
        websocket = true;
      };

      lm-studio = {
        description = "LM Studio - LLM API server";
        port = 1234;
        websocket = true;
      };

      # ============================================================
      # AI COMMAND CENTER
      # ============================================================
      synapse = {
        description = "Synapse - AI Command Center";
        port = 3000;
        websocket = true;
      };

      # ============================================================
      # MONITORING & OBSERVABILITY
      # ============================================================
      grafana = {
        description = "Grafana - Metrics dashboard";
        port = 3001;
        https = false;
      };

      prometheus = {
        description = "Prometheus - Metrics collector";
        port = 9090;
        https = false;
      };

      loki = {
        description = "Loki - Log aggregation";
        port = 3100;
        https = false;
      };

      # ============================================================
      # ERROR TRACKING
      # ============================================================
      glitchtip = {
        description = "GlitchTip - Error tracking web UI";
        port = 8000;
        https = false;
      };

      glitchtip-api = {
        description = "GlitchTip API";
        port = 8081;
        https = false;
      };

      # ============================================================
      # DEVELOPMENT
      # ============================================================
      opencode = {
        description = "OpenCode - Development environment";
        port = 5173;
        https = false;
      };
    };
  };

  # ============================================================================
  # DNS CONFIGURATION (via Unbound)
  # ============================================================================
  # The gateway automatically adds DNS entries to Unbound.
  # Make sure unbound-cluster is enabled:
  #
  # services.unbound-cluster.enable = true;
  #
  # Services will be accessible at:
  # - ai-gateway.zephyr.cluster.local → http://127.0.0.1:8080
  # - vllm.zephyr.cluster.local → http://127.0.0.1:8000
  # - synapse.zephyr.cluster.local → http://127.0.0.1:3000
  # - grafana.zephyr.cluster.local → http://127.0.0.1:3001
  # - etc.

  # ============================================================================
  # QUICK START
  # ============================================================================
  # After rebuild, list all registered services:
  #   $ svc-gateway
  #
  # Test a service:
  #   $ curl http://ai-gateway.zephyr.cluster.local/health
  #
  # View the gateway readme:
  #   $ cat /etc/service-gateway-readme.md
  #
  # Caddy management:
  #   $ systemctl reload caddy  # Apply config changes
  #   $ journalctl -u caddy -f   # View logs
}
