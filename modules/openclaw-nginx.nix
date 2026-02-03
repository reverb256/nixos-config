# OpenClaw Nginx Reverse Proxy Configuration
# Provides SSL/TLS termination and reverse proxy for OpenClaw services
{
  config,
  lib,
  ...
}: let
  cfg = config.services.openclaw.nginx;
in {
  options.services.openclaw.nginx = {
    enable = lib.mkEnableOption "nginx reverse proxy for OpenClaw services";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "openclaw.local";
      description = "Domain name for OpenClaw services";
    };

    enableSSL = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SSL/TLS with Let's Encrypt (requires valid domain)";
    };

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "OpenClaw gateway port (internal)";
    };

    storagePort = lib.mkOption {
      type = lib.types.port;
      default = 18800;
      description = "OpenClaw storage MCP port (internal)";
    };

    allowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["127.0.0.1" "::1" "10.0.0.0/8" "192.168.0.0/16"];
      description = "Allowed IP ranges for access (CIDR notation)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable nginx
    services.nginx = {
      enable = true;

      # Use recommended settings
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      # Common configuration
      appendConfig = ''
        # Rate limiting zones
        limit_req_zone $binary_remote_addr zone=openclaw_limit:10m rate=10r/s;
        limit_conn_zone $binary_remote_addr zone=openclaw_conn:10m;
      '';

      virtualHosts = {
        # Main OpenClaw gateway virtual host
        "${cfg.domain}" = {
          enableACME = cfg.enableSSL;
          forceSSL = cfg.enableSSL;

          # IP allowlist for security
          extraConfig =
            lib.concatStringsSep "\n" (
              map (ip: "allow ${ip};") cfg.allowedIPs
            )
            + ''
              deny all;

              # Rate limiting
              limit_req zone=openclaw_limit burst=20 nodelay;
              limit_conn openclaw_conn 10;

              # Security headers
              add_header X-Frame-Options "SAMEORIGIN" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header X-XSS-Protection "1; mode=block" always;
              add_header Referrer-Policy "strict-origin-when-cross-origin" always;

              # WebSocket support for OpenClaw gateway
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
            '';

          locations = {
            # OpenClaw Gateway WebSocket endpoint
            "/gateway" = {
              proxyPass = "http://127.0.0.1:${toString cfg.gatewayPort}";
              extraConfig = ''
                proxy_read_timeout 86400s;
                proxy_send_timeout 86400s;
              '';
            };

            # Storage MCP API
            "/storage" = {
              proxyPass = "http://127.0.0.1:${toString cfg.storagePort}";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              '';
            };

            # Health check endpoint
            "/health" = {
              proxyPass = "http://127.0.0.1:${toString cfg.gatewayPort}/health";
              extraConfig = ''
                access_log off;
                return 200 "healthy\n";
                add_header Content-Type text/plain;
              '';
            };

            # Root - simple status page
            "/" = {
              return = ''200 "OpenClaw Gateway\n\nAvailable endpoints:\n  /gateway - WebSocket gateway\n  /storage - Storage MCP API\n  /health  - Health check\n"'';
              extraConfig = ''
                add_header Content-Type text/plain;
              '';
            };
          };
        };

        # Separate virtual host for storage MCP (optional, for direct access)
        "storage.${cfg.domain}" = lib.mkIf (cfg.domain != "localhost") {
          enableACME = cfg.enableSSL;
          forceSSL = cfg.enableSSL;

          extraConfig =
            lib.concatStringsSep "\n" (
              map (ip: "allow ${ip};") cfg.allowedIPs
            )
            + ''
              deny all;
            '';

          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.storagePort}";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
          };
        };
      };
    };

    # Firewall - only expose nginx ports
    networking.firewall = {
      allowedTCPPorts = [80 443];
      # Internal ports are not exposed (bound to localhost only)
    };

    # Create acme challenge directory if using SSL
    systemd.tmpfiles.rules = lib.mkIf cfg.enableSSL [
      "d /var/lib/acme/.challenges 0755 nginx nginx -"
    ];

    # Ensure nginx can read acme certificates
    users.users.nginx.extraGroups = lib.mkIf cfg.enableSSL ["acme"];
  };
}
