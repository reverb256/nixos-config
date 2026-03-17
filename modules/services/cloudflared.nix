# Cloudflare Tunnel (cloudflared) Module for NixOS
# Secure ingress for Kubernetes services without public ports
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.cloudflared-tunnel = {
    enable = lib.mkEnableOption "Cloudflare Tunnel - secure ingress without public IPs";

    tunnelId = lib.mkOption {
      type = lib.types.str;
      example = "09cb0ea8-051e-4207-8e7c-3acc43408915";
      description = "Cloudflare Tunnel ID (from token or dashboard)";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/cloudflared-token.json";
      description = "Path to tunnel credentials file (JSON with AccountID, TunnelID, TunnelSecret)";
    };

    ingressRules = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule ({ ... }: {
        options = {
          hostname = lib.mkOption {
            type = lib.types.str;
            example = "provider.example.com";
            description = "Public hostname for this route";
          };
          service = lib.mkOption {
            type = lib.types.str;
            example = "http://localhost:8080";
            description = "Backend service URL (or http_status:404 for catch-all)";
          };
        };
      }));
      default = [];
      description = "Ingress rules for routing traffic through the tunnel";
    };

    metricsPort = lib.mkOption {
      type = lib.types.port;
      default = 54162;
      description = "Port for cloudflared metrics";
    };
  };

  config = let
    cfg = config.services.cloudflared-tunnel;
  in
    lib.mkIf cfg.enable {
      # ============================================================================
      # REQUIRED PACKAGES
      # ============================================================================
      environment.systemPackages = with pkgs; [cloudflared];

      # ============================================================================
      # CLOUDFLARED CONFIGURATION
      # ============================================================================
      environment.etc."cloudflared/config.yml".text = let
      # Generate ingress YAML entries
      ingressYaml = lib.concatMapStrings (rule: ''
        - hostname: ${rule.hostname}
          service: ${rule.service}
      '') cfg.ingressRules;
    in ''
      tunnel: ${cfg.tunnelId}
      credentials-file: ${cfg.credentialsFile}

      metrics: ${toString cfg.metricsPort}

      ingress:
      ${lib.optionalString (cfg.ingressRules != []) ingressYaml}
      # Catch-all: return 404 for unmatched routes
      - service: http_status:404
    '';

    # ============================================================================
    # SYSTEMD SERVICE
    # ============================================================================
    systemd.services.cloudflared-tunnel = {
      description = "Cloudflare Tunnel - secure ingress";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "agenix-rekey.service"];

      serviceConfig = {
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run";
        Restart = "on-failure";
        RestartSec = "5s";
        DynamicUser = true;
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = ["/run/agenix"];
        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
      };

      # Verify token exists before starting
      preStart = ''
        if [ ! -f ${cfg.credentialsFile} ]; then
          echo "ERROR: cloudflared credentials not found at ${cfg.credentialsFile}"
          echo "Please ensure the secret is properly configured in agenix."
          exit 1
        fi
      '';
    };

    # ============================================================================
    # FIREWALL (for metrics)
    # ============================================================================
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      config.services.cloudflared-tunnel.metricsPort
    ];
  };
}
