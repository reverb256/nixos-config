# Example Service Gateway Configuration - Simple Human URLs
# Add this to your /etc/nixos/configuration.nix

{ config, ... }: {
  # ============================================================================
  # SERVICE GATEWAY - Simple URLs like ai.zephyr, cloud.zephyr
  # ============================================================================
  services.service-gateway = {
    enable = true;

    # Public access (set to true to expose to LAN)
    publicAccess = false;

    services = {
      # ============================================================
      # AI & INFERENCE
      # ============================================================
      ai = {
        description = "AI Inference Gateway - OpenAI-compatible API";
        port = 8080;
        websocket = true;
      };

      vllm = {
        description = "vLLM - Local LLM inference backend";
        port = 8000;
        websocket = true;
      };

      lm = {
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
      # FILE & COLLABORATION
      # ============================================================
      cloud = {
        description = "Nextcloud - File sync & collaboration";
        port = 8080;
      };

      # ============================================================
      # MONITORING
      # ============================================================
      grafana = {
        description = "Grafana - Metrics dashboard";
        port = 3001;
      };

      prom = {
        description = "Prometheus - Metrics collector";
        port = 9090;
      };

      logs = {
        description = "Loki - Log aggregation";
        port = 3100;
      };

      # ============================================================
      # ERROR TRACKING
      # ============================================================
      errors = {
        description = "GlitchTip - Error tracking web UI";
        port = 8000;
      };

      # ============================================================
      # DEVELOPMENT
      # ============================================================
      dev = {
        description = "OpenCode - Development environment";
        port = 5173;
      };
    };
  };

  # ============================================================================
  # WHAT YOU GET
  # ============================================================================
  # Services accessible at short, memorable URLs:
  #
  #   http://ai.zephyr       → AI Inference Gateway (port 8080)
  #   http://vllm.zephyr     → vLLM backend (port 8000)
  #   http://lm.zephyr       → LM Studio (port 1234)
  #   http://synapse.zephyr  → AI Command Center (port 3000)
  #   http://cloud.zephyr    → Nextcloud (port 8080)
  #   http://grafana.zephyr  → Metrics dashboard (port 3001)
  #   http://prom.zephyr     → Prometheus (port 9090)
  #   http://logs.zephyr     → Loki logs (port 3100)
  #   http://errors.zephyr   → GlitchTip (port 8000)
  #   http://dev.zephyr      → OpenCode (port 5173)
  #
  # With DNS search domain configured, you can type even less:
  #   http://ai      (works from zephyr)
  #   http://cloud   (works from zephyr)
  #
  # ============================================================================
  # QUICK START
  # ============================================================================
  # After rebuild:
  #   $ sudo nixos-rebuild switch
  #
  # List all services:
  #   $ svc
  #
  # Test a service:
  #   $ curl http://ai.zephyr/health
  #   $ curl http://ai.zephyr/v1/models
  #
  # View the readme:
  #   $ cat /etc/service-gateway-readme.md
}
