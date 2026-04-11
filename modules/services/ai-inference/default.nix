# AI Inference Service - Config Implementation
#
# This module provides the config implementation for services.ai-inference.
# Option declarations live in options.nix for easy review of the module interface.
#
# Imported submodules: gateway.nix, router.nix, monitor.nix, health-monitor.nix,
# auth/, qdrant.nix — these are imported via options.nix.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.ai-inference;
  inherit (lib) mkIf;
in
{
  imports = [
    ./options.nix
  ];

  config = mkIf cfg.enable {
    # ============================================================================
    # ASSERTIONS
    # ============================================================================
    assertions = [
      {
        assertion = cfg.backend.url != "";
        message = ''
          AI Inference Service requires a backend URL to be configured.

          Current configuration:
            services.ai-inference.backend.url = "${cfg.backend.url}"

          Configure a backend URL in one of these ways:
            services.ai-inference.backend.url = "http://127.0.0.1:1234";  # LM Studio
            services.ai-inference.backend.url = "http://127.0.0.1:8080";  # Gateway
        '';
      }
      {
        assertion =
          cfg.backend.zai.enable -> (cfg.backend.zai.apiKey != "" || cfg.backend.zai.apiKeyFile != null);
        message = ''
          ZAI backend is enabled but no API key is configured.

          When services.ai-inference.backend.zai.enable is true, you must configure:
            services.ai-inference.backend.zai.apiKey = "your-api-key";
            # OR
            services.ai-inference.backend.zai.apiKeyFile = /run/agenix/zai-api-key;

          Current configuration:
            zai.enable = ${toString cfg.backend.zai.enable}
            zai.apiKey = ${if cfg.backend.zai.apiKey != "" then "***" else "(not set)"}
            zai.apiKeyFile = ${
              if cfg.backend.zai.apiKeyFile != null then toString cfg.backend.zai.apiKeyFile else "(not set)"
            }
        '';
      }
      {
        assertion =
          cfg.backend.type == "zai" -> (cfg.backend.zai.apiKey != "" || cfg.backend.zai.apiKeyFile != null);
        message = ''
          Backend type is "zai" but no ZAI API key is configured.

          When using ZAI backend, configure an API key:
            services.ai-inference.backend.zai.apiKey = "your-zai-api-key";
            # OR
            services.ai-inference.backend.zai.apiKeyFile = /run/agenix/zai-api-key;

          Current configuration:
            backend.type = "${cfg.backend.type}"
            zai.apiKey = ${if cfg.backend.zai.apiKey != "" then "***" else "(not set)"}
            zai.apiKeyFile = ${
              if cfg.backend.zai.apiKeyFile != null then toString cfg.backend.zai.apiKeyFile else "(not set)"
            }

          Or change backend type to: vllm, llama-cpp, sglang, pollinations
        '';
      }
      {
        assertion = cfg.rag.enable -> cfg.rag.qdrant.enable;
        message = ''
          RAG is enabled but Qdrant vector database is not enabled.

          When services.ai-inference.rag.enable is true, you must also enable Qdrant:
            services.ai-inference.rag.qdrant.enable = true;

          Current configuration:
            rag.enable = ${toString cfg.rag.enable}
            rag.qdrant.enable = ${toString cfg.rag.qdrant.enable}
        '';
      }
      {
        assertion = cfg.mcp.enable -> (builtins.length (lib.attrValues cfg.mcp.servers)) > 0;
        message = ''
          MCP broker is enabled but no MCP servers are configured.

          Add MCP servers to:
            services.ai-inference.mcp.servers.<name> = { ... };

          Example:
            services.ai-inference.mcp.servers.searxng = {
              type = "local";
              command = [ "${pkgs.python3}/bin/python3" "-m" "searxng_server" ];
            };

          Current configuration:
            mcp.enable = ${toString cfg.mcp.enable}
            mcp.servers (count) = ${toString (builtins.length (lib.attrValues cfg.mcp.servers))}
        '';
      }
      {
        assertion = cfg.security.maxRequestSize > 0;
        message = ''
          Invalid security.maxRequestSize: must be greater than 0.

          Current value: ${toString cfg.security.maxRequestSize}

          Recommended minimum: 1048576 (1MB)
          Current default: 10485760 (10MB)
        '';
      }
    ];
    # System packages
    environment.systemPackages = with pkgs; [
      config.services.ai-inference.package
      inputs.claude-native.packages.x86_64-linux.claude
      ffmpeg # Required for pydub MP3 conversion in TTS
      (pkgs.writeShellScriptBin "ai-inference-status" ''
        #!/bin/bash
        echo "=== AI Inference Service Status ==="
        echo "Backend: ${cfg.backend.type}"
        echo "Backend URL: ${cfg.backend.url}"
        echo ""
        echo "=== Backend Models ==="
        ${pkgs.curl}/bin/curl -s ${cfg.backend.url}/v1/models | ${pkgs.jq}/bin/jq -r '.data[].id' || echo "Backend unavailable"
        echo ""
        echo "=== K8s Gateway Health ==="
        ${pkgs.curl}/bin/curl -s http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/health || echo "K8s gateway unavailable"
      '')
    ];

    # Services configuration
    services = {
      # Prometheus scrape configuration — targets the K8s service
      prometheus.scrapeConfigs = mkIf cfg.monitoring.enable [
        {
          job_name = "ai-inference-gateway";
          static_configs = [
            {
              targets = [ "ai-inference-gateway.ai-inference.svc.cluster.local:${toString cfg.monitoring.port}" ];
              labels = {
                instance = "ai-inference-gateway";
                backend = cfg.backend.type;
              };
            }
          ];
        }
      ];

      # Redis for gateway middleware (caching, rate limiting, circuit breaker)
      # Using port 6380 to avoid conflict with fwupd-redis on 6379
      redis.servers.ai-gateway = {
        inherit (cfg.gateway.middleware.redis) enable;
        bind = "127.0.0.1";
        port = 6380;
      };
    };

    # Firewall ports — gateway runs in K8s, no host port needed
    # Only open Qdrant port if RAG is enabled with non-localhost bind
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault (
      lib.optional (
        cfg.rag.enable && cfg.rag.qdrant.enable && cfg.rag.qdrant.host != "127.0.0.1"
      ) cfg.rag.qdrant.port
    );
  };
}
