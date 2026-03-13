# Caddy Web Server Configuration
# Modern reverse proxy with automatic HTTPS
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.caddy-module = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "Caddy virtual host configurations";
  };

  config = lib.mkIf (config.services.caddy-module != {}) {
    services.caddy = {
      enable = true;
      package = pkgs.caddy;
      # Global configuration (renamed from 'config' to 'extraConfig' in NixOS 24.11+)
      extraConfig = lib.concatStringsSep "\n" (lib.mapAttrsToList (
          domain: cfg:
            if cfg ? reverseProxy
            then ''
              ${domain}:${toString (cfg.port or 443)} {
                reverse_proxy ${cfg.reverseProxy} ${lib.optionalString (cfg ? reverseProxyPort) ":${toString cfg.reverseProxyPort}"}
                ${lib.optionalString (cfg ? basicAuth) "basicauth ${cfg.basicAuth.user} ${cfg.basicAuth.password}"}
                ${lib.optionalString (cfg ? tls) "tls ${cfg.tls.email}"}

                # Security Headers (OWASP A05:2021)
                header {
                  # Prevent clickjacking
                  X-Frame-Options "DENY"
                  # Prevent MIME type sniffing
                  X-Content-Type-Options "nosniff"
                  # Enable XSS protection (legacy browsers)
                  X-XSS-Protection "1; mode=block"
                  # Referrer policy
                  Referrer-Policy "no-referrer"
                  # Content Security Policy
                  Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
                  # HSTS (only enable after testing)
                  # Strict-Transport-Security "max-age=31536000; includeSubDomains"
                }
              }
            ''
            else if cfg ? respond
            then ''
              ${domain}:${toString (cfg.port or 443)} {
                respond ${cfg.respond}

                # Security Headers (OWASP A05:2021)
                header {
                  # Prevent clickjacking
                  X-Frame-Options "DENY"
                  # Prevent MIME type sniffing
                  X-Content-Type-Options "nosniff"
                  # Enable XSS protection (legacy browsers)
                  X-XSS-Protection "1; mode=block"
                  # Referrer policy
                  Referrer-Policy "no-referrer"
                  # Content Security Policy
                  Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
                  # HSTS (only enable after testing)
                  # Strict-Transport-Security "max-age=31536000; includeSubDomains"
                }
              }
            ''
            else if cfg ? fileServer
            then ''
              ${domain}:${toString (cfg.port or 443)} {
                root * ${cfg.fileServer}
                file_server browse

                # Security Headers (OWASP A05:2021)
                header {
                  # Prevent clickjacking
                  X-Frame-Options "DENY"
                  # Prevent MIME type sniffing
                  X-Content-Type-Options "nosniff"
                  # Enable XSS protection (legacy browsers)
                  X-XSS-Protection "1; mode=block"
                  # Referrer policy
                  Referrer-Policy "no-referrer"
                  # Content Security Policy
                  Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
                  # HSTS (only enable after testing)
                  # Strict-Transport-Security "max-age=31536000; includeSubDomains"
                }
              }
            ''
            else ""
        )
        config.services.caddy-module);
    };

    # Open firewall ports for Caddy
    networking.firewall.allowedTCPPorts = [80 443];
    networking.firewall.allowedUDPPorts = [443]; # HTTP/3

    # Systemd service security hardening
    systemd.services.caddy = {
      serviceConfig = {
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
        # Caddy needs network access
        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
      };
    };
  };
}
