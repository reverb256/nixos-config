# AI Inference Service - Backend Integration Config
#
# System packages, service integrations (Prometheus, Redis), and
# the ai-inference-status helper CLI.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.ai-inference;
in
{
  config = lib.mkIf cfg.enable {
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
      prometheus.scrapeConfigs = lib.mkIf cfg.monitoring.enable [
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
  };
}
