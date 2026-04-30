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
      type = lib.types.listOf (lib.types.submodule (_: {
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

    quicEnabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable QUIC protocol for 30-50% faster connections";
    };

    originRequest = lib.mkOption {
      type = lib.types.submodule (_: {
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
      environment.systemPackages = with pkgs; [cloudflared];

      environment.etc."cloudflared/config.yml".text = let
        ingressYaml =
          lib.concatMapStrings (rule: ''
            - hostname: "${rule.hostname}"
              service: ${rule.service}
              ${lib.optionalString (rule.accessPolicy != null) "# Access policy configured via Cloudflare Dashboard\n          # Policy: ${rule.accessPolicy}"}
          '')
          cfg.ingressRules;
      in ''
        tunnel: ${cfg.tunnelId}
        credentials-file: ${cfg.credentialsFile}

        metrics: 127.0.0.1:${toString cfg.metricsPort}

        ${lib.optionalString cfg.quicEnabled "quic: true"}

        no-remote-ipv6: true

        originRequest:
          connectTimeout: ${cfg.originRequest.connectTimeout}
          tlsTimeout: ${cfg.originRequest.tlsTimeout}
          tcpKeepAlive: ${toString cfg.originRequest.tcpKeepAlive}s
          noHappyEyeballs: ${lib.boolToString cfg.originRequest.noHappyEyeballs}
          keepAliveConnections: ${toString cfg.originRequest.keepAliveConnections}
          keepAliveTimeout: ${toString cfg.originRequest.keepAliveTimeout}s

        ingress:
        ${lib.optionalString (cfg.ingressRules != []) ingressYaml}
        - service: http_status:404
      '';

      systemd.services.cloudflared-tunnel = {
        description = "Cloudflare Tunnel - secure ingress";
        wantedBy = ["multi-user.target"];
        requires = ["network-online.target"];
        after = ["network-online.target" "agenix-rekey.service"];

        serviceConfig = {
          ExecStart = lib.getExe pkgs.cloudflared + " tunnel --config /etc/cloudflared/config.yml run";
          Restart = "on-failure";
          RestartSec = "5s";
          User = "root";
          Group = "root";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        };

        preStart = ''
          if [ ! -f ${cfg.credentialsFile} ]; then
            echo "ERROR: cloudflared credentials not found at ${cfg.credentialsFile}"
            echo "Please ensure the secret is properly configured in agenix."
            exit 1
          fi
        '';
      };
    };
}
