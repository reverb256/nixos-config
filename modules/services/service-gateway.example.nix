# Example Service Gateway Configuration
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
      # COLLABORATION
      # ============================================================
      nextcloud = {
        description = "Nextcloud - File sync & collaboration";
        port = 8080;  # Adjust to your Nextcloud port
        https = true;
      };

      # ============================================================
      # AI / INFERENCE
      # ============================================================
      vllm = {
        description = "vLLM - Local LLM inference";
        port = 8000;
        https = false;  # Local only
        websocket = true;
      };

      cc-router = {
        description = "CC Router - LLM API router";
        port = 3456;
        https = false;
        websocket = true;
      };

      # ============================================================
      # AI COMMAND CENTER
      # ============================================================
      synapse = {
        description = "Synapse - AI Command Center";
        port = 3000;
        https = false;
        websocket = true;
      };

      # ============================================================
      # MONITORING
      # ============================================================
      grafana = {
        description = "Grafana - Metrics dashboard";
        port = 3001;
        https = true;
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
      # DEVELOPMENT
      # ============================================================
      opencode = {
        description = "OpenCode - Development environment";
        port = 5173;
        https = false;
      };

      # ============================================================
      # OTHER SERVICES
      # ============================================================
      gltichtip = {
        description = "GlitchTip - Error tracking";
        port = 8000;
        https = true;
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
  # - nextcloud.zephyr.cluster.local
  # - vllm.zephyr.cluster.local
  # - synapse.zephyr.cluster.local
  # - etc.

  # ============================================================================
  # QUICK START
  # ============================================================================
  # After rebuild, list all registered services:
  #   $ svc-gateway
  #
  # Test a service:
  #   $ curl http://vllm.zephyr.cluster.local/v1/models
  #
  # View the gateway readme:
  #   $ cat /etc/service-gateway-readme.md
}
