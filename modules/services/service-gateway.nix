# Service Gateway - Auto-generated subdomains for self-hosted services (Caddy)
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
    concatMapStringsSep
    ;

  # Get the current hostname for generating full service FQDNs
  hostname = config.networking.hostName or "localhost";

  # Build Caddyfile entries for each service
  buildCaddyConfig = services:
    concatMapStringsSep "\n" (name: service:
      let
        fqdn = "${name}.${hostname}.cluster.local";
        backendUrl = "http://${service.backend}:${toString service.port}";
      in ''
        # ${service.description}
        ${fqdn}:${toString cfg.port} {
          ${lib.optionalString service.https "tls internal"}

          reverse_proxy ${backendUrl}${service.path or "/"} {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Host {host}
            header_up X-Forwarded-Proto {scheme}

            # WebSocket support
            ${lib.optionalString (service.websocket or false) ''
            header_up Connection {>Connection}
            header_up Upgrade {>Upgrade}
            ''}
          }

          # Security headers
          header {
            X-Frame-Options "${service.frameOptions or "SAMEORIGIN"}"
            X-Content-Type-Options "nosniff"
            -Server
          }

          ${lib.optionalString (service.extraConfig != "") "# Extra config\n${service.extraConfig}"}
        }
      ''
    ) (lib.attrValues services);

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
in {
  options.services.service-gateway = {
    enable = mkEnableOption "Service Gateway - auto subdomain routing for self-hosted services (Caddy)";

    port = mkOption {
      type = types.port;
      default = 80;
      description = "Port for Caddy to listen on";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "HTTPS port";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "IP address to bind DNS entries to";
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
            default = false;
            description = "Enable TLS (uses internal CA by default)";
          };

          websocket = mkOption {
            type = types.bool;
            default = false;
            description = "Enable WebSocket proxy support";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Extra Caddy configuration";
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
    # CADDY REVERSE PROXY
    # ============================================================================
    services.caddy = {
      enable = true;

      # Global options
      globalConfig = ''
        # Auto-HTTPS will be off for internal domains
        auto_https off

        # Admin API for dynamic config (optional)
        # admin localhost:2019

        # Default SNI for HTTP/1.1 without SNI
        default_sni ${hostname}.cluster.local

        # Logging
        {
          output file
          format json
        }
      '';

      # Virtual hosts for each service
      virtualHosts = buildCaddyConfig cfg.services;
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
      allowedTCPPorts = [cfg.port cfg.httpsPort];
    };

    # ============================================================================
    # CLI TOOLS
    # ============================================================================
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "svc-gateway" ''
        # Service Gateway CLI
        set -euo pipefail

        echo "=== Service Gateway (${hostname}.cluster.local) ==="
        echo ""
        ${concatStringsSep "\n" (mapAttrsToList (name: service: ''
          echo "• ${name}"
          echo "  URL:         http${lib.optionalString service.https "s"}://${name}.${hostname}.cluster.local"
          echo "  Backend:     ${service.backend}:${toString service.port}"
          echo "  Description: ${service.description}"
          echo ""
        '') cfg.services)}
        echo "Total services: ${toString (builtins.attrNames cfg.services)}"
      '')
    ];

    # ============================================================================
    # DOCUMENTATION
    # ============================================================================
    environment.etc."service-gateway-readme.md".text = ''
      # Service Gateway (Caddy)

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
        https = true;      # enable TLS
      };
      ```

      ## Caddy Management

      ```bash
      # Reload Caddy (no restart needed)
      systemctl reload caddy

      # Validate Caddyfile syntax
      caddy validate --config /etc/caddy/Caddyfile

      # View Caddy logs
      journalctl -u caddy -f
      ```
    '';
  };
}
