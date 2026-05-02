{ config, lib, pkgs, ... }:

let
  cfg = config.services.central-auth;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.central-auth = {
    enable = mkEnableOption "Central OAuth2 proxy for SSO";

    port = mkOption {
      type = types.port;
      default = 4180;
      description = "Port for oauth2-proxy to listen on";
    };

    clientID = mkOption {
      type = types.str;
      description = "Casdoor OAuth2 client ID";
    };

    clientSecretFile = mkOption {
      type = types.path;
      description = "Path to file containing Casdoor client secret";
    };

    cookieSecretFile = mkOption {
      type = types.path;
      description = "Path to file containing cookie secret";
    };

    oidcIssuerUrl = mkOption {
      type = types.str;
      default = "https://auth.lan";
      description = "OIDC issuer URL";
    };

    cookieDomain = mkOption {
      type = types.str;
      default = ".lan";
      description = "Cookie domain for SSO";
    };

    skipAuthRoutes = mkOption {
      type = types.listOf types.str;
      default = [
        "^/health$"
        "^/healthz$"
        "^/api/health$"
        "^/ready$"
        "^/metrics$"
        "^/favicon"
        "^/assets/"
        "^/public/"
        "^/static/"
      ];
      description = "Routes to skip authentication for (regex)";
    };
  };

  config = mkIf cfg.enable {
    # Open firewall for localhost only
    networking.firewall.interfaces."lo".allowedTCPPorts = [ cfg.port ];

    systemd.services.central-auth = {
      description = "Central OAuth2 Proxy (Casdoor SSO)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe pkgs.oauth2-proxy + " "
          + lib.concatStringsSep " " [
            "--provider=oidc"
            "--oidc-issuer-url=${cfg.oidcIssuerUrl}"
            "--client-id=${cfg.clientID}"
            "--client-secret-file=${cfg.clientSecretFile}"
            "--cookie-secret-file=${cfg.cookieSecretFile}"
            "--cookie-domain=${cfg.cookieDomain}"
            "--http-address=127.0.0.1:${toString cfg.port}"
            "--redirect-url=https://auth.lan/oauth2/callback"
            "--cookie-secure=false"
            "--cookie-samesite=lax"
            "--cookie-httponly=true"
            "--email-domain=*"
            "--scope=openid profile email"
            "--ssl-insecure-skip-verify=true"
            "--set-xauthrequest=true"
            "--pass-access-token=true"
            "--pass-user-headers=true"
            "--skip-auth-route=${lib.concatStringsSep "," cfg.skipAuthRoutes}"
            "--skip-provider-button=false"
            "--reverse-proxy=true"
            "--whitelist-domain=.lan"
            "--standard-logging=true"
            "--request-logging=true"
            "--auth-logging=true"
          ];
        Restart = "on-failure";
        RestartSec = "5s";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ ];
        Environment = [
          "SSL_CERT_FILE=/etc/ssl/cluster-ca/ca.crt"
        ];

        # Resource limits
        MemoryMax = "256M";
        CPUQuota = "25%";
      };
    };
  };
}
