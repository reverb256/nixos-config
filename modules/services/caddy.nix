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
      # Global configuration
      config = lib.concatStringsSep "\n" (lib.mapAttrsToList (domain: cfg:
        if cfg ? reverseProxy then ''
          ${domain}:${toString (cfg.port or 443)} {
            reverse_proxy ${cfg.reverseProxy} ${lib.optionalString (cfg ? reverseProxyPort) ":${toString cfg.reverseProxyPort}"}
            ${lib.optionalString (cfg ? basicAuth) "basicauth ${cfg.basicAuth.user} ${cfg.basicAuth.password}"}
            ${lib.optionalString (cfg ? tls) "tls ${cfg.tls.email}"}
          }
        '' else if cfg ? respond then ''
          ${domain}:${toString (cfg.port or 443)} {
            respond ${cfg.respond}
          }
        '' else if cfg ? fileServer then ''
          ${domain}:${toString (cfg.port or 443)} {
            root * ${cfg.fileServer}
            file_server browse
          }
        '' else ""
      ) config.services.caddy-module);
    };

    # Open firewall ports for Caddy
    networking.firewall.allowedTCPPorts = [80 443];
    networking.firewall.allowedUDPPorts = [443]; # HTTP/3
  };
}
