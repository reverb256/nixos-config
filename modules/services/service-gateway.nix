# Service Gateway - Simple human-friendly URLs for self-hosted services (Caddy)
# Maps services like: ai.zephyr, cloud.zephyr → localhost:PORT
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

  # Get the current hostname for generating short service URLs
  hostname = config.networking.hostName or "localhost";

  # Build Caddyfile entries for each service
  buildCaddyConfig = services:
    concatMapStringsSep "\n" (name: service:
      let
        fqdn = "${name}.${hostname}";
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

  # Build DNS local-data entries for all services (short format: name.hostname)
  buildDnsEntries = services:
    concatStringsSep "\n"
    (mapAttrsToList (name: service:
      # Short format: ai.zephyr, cloud.zephyr, etc.
      ''
        "${name}.${hostname}. IN A ${cfg.listenAddress}"
      ''
    ) services);
in {
  options.services.service-gateway = {
    enable = mkEnableOption "Service Gateway - simple URLs for self-hosted services (e.g., ai.zephyr)";

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
          ai = {
            description = "AI Inference Gateway";
            port = 8080;
          };
          cloud = {
            description = "Nextcloud file sharing";
            port = 8080;
          };
        }
      '';
      description = "Services to register with the gateway (use short names like 'ai', 'cloud')";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # DNS SEARCH DOMAIN - enables short URLs like "ai" instead of "ai.zephyr"
    # ============================================================================
    # networking.searchDomains = [hostname];  # Deprecated option - removed

    # ============================================================================
    # CADDY REVERSE PROXY
    # ============================================================================
    services.caddy = {
      enable = true;

      # Global options
      globalConfig = ''
        # Auto-HTTPS will be off for internal domains
        auto_https off

        # Default SNI
        default_sni ${hostname}

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
      local-zone = [ "${hostname} static" ];

      # Add DNS records for each service (short format)
      local-data = mapAttrsToList (name: service:
        "${name}.${hostname}. IN A ${cfg.listenAddress}"
      ) cfg.services;
    };

    # Add to /etc/hosts for local resolution (fallback if DNS isn't running)
    networking.extraHosts = concatStringsSep "\n" (mapAttrsToList (name: service:
      "${cfg.listenAddress} ${name}.${hostname}"
    ) cfg.services);

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
      (pkgs.writeShellScriptBin "svc" ''
        # Service Gateway CLI - short command
        set -euo pipefail

        echo "=== Services (${hostname}) ==="
        echo ""
        ${concatStringsSep "\n" (mapAttrsToList (name: service: ''
          echo "• ${name}.${hostname}"
          echo "  → ${service.backend}:${toString service.port}"
          echo "  ${service.description}"
          echo ""
        '') cfg.services)}
        echo "Total: ${toString (builtins.attrNames cfg.services)}"
        echo ""
        echo "Type just '${hostname}' is your search domain, so you can use:"
        echo "  http://${hostname}     (this machine)"
        ${concatStringsSep "\n" (mapAttrsToList (name: service: ''
        echo "  http://${name}.${hostname}    (${service.description})"
        '') cfg.services)}
      '')
    ];

    # ============================================================================
    # DOCUMENTATION
    # ============================================================================
    environment.etc."service-gateway-readme.md".text = ''
      # Service Gateway - Simple URLs

      Your services are accessible at short, memorable URLs:

      | Service | URL | Backend |
      |---------|-----|---------|
      ${concatStringsSep "\n" (mapAttrsToList (name: service: ''
      | ${service.description} | http://${name}.${hostname} | ${service.backend}:${toString service.port} |
      '') cfg.services)}

      ## Even Shorter URLs

      Because `${hostname}` is configured as your DNS search domain,
      you can often omit it entirely on your local machine:

      ```bash
      # Instead of:
      curl http://ai.${hostname}

      # You can type:
      ping ai
      curl http://ai
      ```

      ## Adding a New Service

      ```nix
      services.service-gateway.services.my-service = {
        description = "My awesome service";
        port = 1234;
      };
      ```

      This makes it available at: `http://my-service.${hostname}`

      ## Caddy Management

      ```bash
      systemctl reload caddy      # Apply config changes
      journalctl -u caddy -f      # View logs
      ```
    '';
  };
}
