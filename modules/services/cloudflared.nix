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
      default = "/run/agenix/cloudflared-token";
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
          # NEW: Zero Trust access policy
          accessPolicy = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "email@example.com";
            description = "Access policy (email, github-team, or cf-access)";
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

    # NEW: QUIC protocol for faster connections
    quicEnabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable QUIC protocol for 30-50% faster connections";
    };

    # NEW: Origin request configuration
    originRequest = lib.mkOption {
      type = lib.types.submodule ({ ... }: {
        options = {
          connectTimeout = lib.mkOption {
            type = lib.types.str;
            default = "30s";
            description = "Timeout for establishing connection to origin";
          };
          tlsTimeout = lib.mkOption {
            type = lib.types.str;
            default = "10s";
            description = "Timeout for TLS handshake";
          };
          tcpKeepAlive = lib.mkOption {
            type = lib.types.int;
            default = 30;
            description = "TCP keep-alive interval in seconds";
          };
          noHappyEyeballs = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Disable Happy Eyeballs for IPv6/IPv4 connection racing";
          };
          keepAliveConnections = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "Maximum number of connections to keep alive";
          };
          keepAliveTimeout = lib.mkOption {
            type = lib.types.int;
            default = 90;
            description = "Timeout for keeping connections alive (seconds)";
          };
        };
      });
      default = {};
      description = "Origin request configuration for connection pooling and timeouts";
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
      # Generate ingress YAML entries with proper quoting
      ingressYaml = lib.concatMapStrings (rule: ''
        - hostname: "${rule.hostname}"
          service: ${rule.service}
          ${lib.optionalString (rule.accessPolicy != null) "# Access policy configured via Cloudflare Dashboard\n          # Policy: ${rule.accessPolicy}"}
      '') cfg.ingressRules;
    in ''
      tunnel: ${cfg.tunnelId}
      credentials-file: ${cfg.credentialsFile}

      metrics: 0.0.0.0:${toString cfg.metricsPort}

      # QUIC protocol for faster connections (30-50% improvement)
      ${lib.optionalString cfg.quicEnabled "quic: true"}

      # Origin request configuration for connection pooling
      originRequest:
        connectTimeout: ${cfg.originRequest.connectTimeout}
        tlsTimeout: ${cfg.originRequest.tlsTimeout}
        tcpKeepAlive: ${toString cfg.originRequest.tcpKeepAlive}s
        noHappyEyeballs: ${lib.boolToString cfg.originRequest.noHappyEyeballs}
        keepAliveConnections: ${toString cfg.originRequest.keepAliveConnections}
        keepAliveTimeout: ${toString cfg.originRequest.keepAliveTimeout}s

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
        # Run as root to read agenix-decrypted credentials
        User = "root";
        Group = "root";
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
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
