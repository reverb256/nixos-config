# Service Gateway - Auto-generated subdomains for self-hosted services
# Maps services like: nextcloud.zephyr.cluster.local -> localhost:8080
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.service-gateway;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    literalExpression
    mapAttrsToList
    concatStringsSep
    ;

  # Get the current hostname for generating full service FQDNs
  hostname = config.networking.hostName or "localhost";

  # Build DNS local-data entries for all services
  buildDnsEntries = services:
    concatStringsSep "\n"
    (mapAttrsToList (name: service:
      # Create both short and full hostname records
      ''
        "${name}.${hostname}.cluster.local. IN A ${cfg.listenAddress}"
        "${name}.${hostname} IN A ${cfg.listenAddress}"
      ''
    ) services);

  # Build nginx upstream entries for backend services
  buildUpstreams = services:
    concatStringsSep "\n"
    (mapAttrsToList (name: service:
      ''
        upstream ${name} {
          server ${service.backend}:${toString service.port};
          ${lib.optionalString (service.healthCheck != null) "check interval=${service.healthCheck.interval or "30s"} rise=2 fall=3 timeout=2s;"}
        }
      ''
    ) services);

  # Build nginx server blocks for each service
  buildServerBlocks = services:
    mapAttrsToList (name: service: {
      forceSSL = service.https;
      enableACME = service.https;
      serverName = "${name}.${hostname}.cluster.local";

      locations = {
        "/" = {
          proxyPass = "http://${service.backend}:${toString service.port}${service.path or "/"}";
          proxyWebsockets = service.websocket or false;

          extraConfig = ''
            # Standard proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Timeouts for long-lived connections
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;

            # Buffer settings
            proxy_buffering off;
            proxy_request_buffering off;

            # WebSocket support
            ${lib.optionalString (service.websocket or false) ''
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
            ''}
          '' + (service.extraConfig or "");
        };
      };

      extraConfig = ''
        # Security headers
        ${lib.optionalString (service.https or false) ''
          add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        ''}
        add_header X-Frame-Options "${service.frameOptions or "SAMEORIGIN"}" always;
        add_header X-Content-Type-Options "nosniff" always;

        # Logging
        access_log /var/log/nginx/${name}-access.log;
        error_log /var/log/nginx/${name}-error.log;
      '';
    }) services;
in {
  options.services.service-gateway = {
    enable = mkEnableOption "Service Gateway - auto subdomain routing for self-hosted services";

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "IP address to bind DNS entries to (typically 127.0.0.1 or cluster IP)";
    };

    publicAccess = mkOption {
      type = types.bool;
      default = false;
      description = "Allow access from outside the local machine";
    };

    # ============================================================================
    # SERVICE REGISTRY
    # ============================================================================
    services = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            description = "Human-readable description of the service";
          };

          port = mkOption {
            type = types.port;
            description = "Backend service port";
          };

          backend = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Backend service address";
          };

          path = mkOption {
            type = types.str;
            default = "/";
            description = "Path to proxy to on the backend";
          };

          https = mkOption {
            type = types.bool;
            default = true;
            description = "Enable HTTPS with ACME certificate";
          };

          websocket = mkOption {
            type = types.bool;
            default = false;
            description = "Enable WebSocket proxy support";
          };

          healthCheck = mkOption {
            type = types.nullOr (types.submodule {
              options = {
                interval = mkOption {
                  type = types.str;
                  default = "30s";
                  description = "Health check interval";
                };
              };
            });
            default = null;
            description = "Health check configuration";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Extra nginx location configuration";
          };

          frameOptions = mkOption {
            type = types.str;
            default = "SAMEORIGIN";
            description = "X-Frame-Options header value";
          };
        };
      });
      default = {};
      example = literalExpression ''
        {
          nextcloud = {
            description = "Nextcloud file sharing";
            port = 8080;
          };
          synapse = {
            description = "AI Command Center";
            port = 3000;
            websocket = true;
          };
        }
      '';
      description = "Services to register with the gateway";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # NGINX REVERSE PROXY
    # ============================================================================
    services.nginx = {
      enable = true;

      # Main nginx configuration
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      # Add upstream configurations
      appendHttpConfig = mkIf (cfg.services != {}) ''
        # Service Gateway Upstreams
        ${buildUpstreams cfg.services}
      '';

      # Virtual hosts for each service
      virtualHosts = builtins.listToAttrs (map (vhost: {
        name = vhost.serverName;
        value = lib.removeAttrs vhost.extraConfig vhost;
      }) (buildServerBlocks cfg.services));
    };

    # ============================================================================
    # UNBOUND DNS INTEGRATION
    # ============================================================================
    services.unbound.settings.server = mkIf config.services.unbound-cluster.enable {
      # Add service hostnames to local zone
      local-zone = [ "services.cluster.local static" ];

      # Add DNS records for each service
      local-data = mapAttrsToList (name: service:
        "${name}.${hostname}.cluster.local. IN A ${cfg.listenAddress}"
      ) cfg.services;
    };

    # ============================================================================
    # FIREWALL
    # ============================================================================
    networking.firewall = mkIf cfg.publicAccess {
      allowedTCPPorts = [80 443];
    };

    # ============================================================================
    # CLI TOOLS
    # ============================================================================
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "svc-gateway" ''
        # Service Gateway CLI
        set -euo pipefail

        ${concatStringsSep "\n" (mapAttrsToList (name: service: ''
          echo "• ${name}.${hostname}.cluster.local -> ${service.backend}:${toString service.port}"
          echo "  ${service.description}"
        '') cfg.services)}

        echo ""
        echo "Total services: ${toString (builtins.attrNames cfg.services)}"
      '')
    ];

    # ============================================================================
    # DOCUMENTATION
    # ============================================================================
    environment.etc."service-gateway-readme.md".text = ''
      # Service Gateway

      Your self-hosted services are accessible via subdomains:

      ${concatStringsSep "\n" (mapAttrsToList (name: service: ''
      ## ${service.description}

      **URL:** http${lib.optionalString service.https "s"}://${name}.${hostname}.cluster.local

      **Backend:** ${service.backend}:${toString service.port}
      '') cfg.services)}

      ## Adding a New Service

      Add to your NixOS configuration:

      ```nix
      services.service-gateway.services.my-service = {
        description = "My awesome service";
        port = 1234;
        backend = "127.0.0.1";
        websocket = true;  # if using WebSockets
        https = true;      # enable SSL
      };
      ```
    '';
  };
}
