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
      extraConfig = lib.concatStringsSep "\n" (lib.mapAttrsToList (
          domain: cfg:
            if cfg ? reverseProxy
            then ''
              ${domain}:${toString (cfg.port or 443)} {
                reverse_proxy ${cfg.reverseProxy} ${lib.optionalString (cfg ? reverseProxyPort) ":${toString cfg.reverseProxyPort}"}
                ${lib.optionalString (cfg ? basicAuth) "basicauth ${cfg.basicAuth.user} ${cfg.basicAuth.password}"}
                ${lib.optionalString (cfg ? tls) "tls ${cfg.tls.email}"}

                header {
                  X-Frame-Options "DENY"
                  X-Content-Type-Options "nosniff"
                  X-XSS-Protection "1; mode=block"
                  Referrer-Policy "no-referrer"
                  Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
                }
              }
            ''
            else if cfg ? respond
            then ''
              ${domain}:${toString (cfg.port or 443)} {
                respond ${cfg.respond}

                header {
                  X-Frame-Options "DENY"
                  X-Content-Type-Options "nosniff"
                  X-XSS-Protection "1; mode=block"
                  Referrer-Policy "no-referrer"
                  Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
                }
              }
            ''
            else if cfg ? fileServer
            then ''
              ${domain}:${toString (cfg.port or 443)} {
                root * ${cfg.fileServer}
                file_server browse

                header {
                  X-Frame-Options "DENY"
                  X-Content-Type-Options "nosniff"
                  X-XSS-Protection "1; mode=block"
                  Referrer-Policy "no-referrer"
                  Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
                }
              }
            ''
            else ""
        )
        config.services.caddy-module);
    };

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [80 443];
    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [443];

    systemd.services.caddy = {
      after = [ "cluster-ca-init.service" ];
      wants = [ "cluster-ca-init.service" ];
      serviceConfig = {
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        BindReadOnlyPaths = ["/etc/ssl/cluster-ca"];
      };
    };
  };
}
