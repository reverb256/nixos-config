{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.casdoor;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.services.casdoor = {
    enable = mkEnableOption "Casdoor - Self-hosted SSO, OAuth 2.0, OIDC, SAML and LDAP";

    hostName = mkOption {
      type = types.str;
      default = "auth.lan";
      description = "The hostname for Casdoor (use cluster DNS or Tailscale Magic DNS)";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/casdoor";
      description = "Casdoor data directory (embedded DB, session data)";
    };

    port = mkOption {
      type = types.int;
      default = 8000;
      description = "Host port for Casdoor HTTP interface";
    };

    # Admin user is fixed, password comes from agenix secret
    organizationName = mkOption {
      type = types.str;
      default = "Casdoor";
      description = "Default organization name";
    };

    # Optional: connection to existing PostgreSQL
    # Defaults to embedded DB (BoltDB) if not specified
    postgresql = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Use external PostgreSQL instead of embedded DB";
      };
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "PostgreSQL host";
      };
      port = mkOption {
        type = types.int;
        default = 5432;
        description = "PostgreSQL port";
      };
      user = mkOption {
        type = types.str;
        default = "casdoor";
        description = "PostgreSQL user";
      };
      database = mkOption {
        type = types.str;
        default = "casdoor";
        description = "PostgreSQL database name";
      };
      # Password via secrets.casdoor-postgres-password.path
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;

    # State directory
    systemd.tmpfiles.settings."casdoor" = {
      "${cfg.dataDir}" = {
        d = {
          mode = "700";
          user = "root";
          group = "root";
        };
      };
    };

    # Main service
    systemd.services.casdoor = {
      description = "Casdoor SSO Service";
      after = [
        "network-online.target"
        "podman.service"
      ];
      wants = [
        "podman.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        ExecStart = ''
          ${pkgs.podman}/bin/podman run --name casdoor \
            -p ${toString cfg.port}:8000 \
            -v ${cfg.dataDir}:/data:Z \
            -e GIN_MODE=release \
            -e CASDOOR_NAME="${cfg.organizationName}" \
            -e CASDOOR_ORGANIZATION_NAME="${cfg.organizationName}" \
            -e CASDOOR_PORT=${toString cfg.port} \
            -e CASDOOR_INIT_ADMIN_EMAIL=admin@localhost \
            -e CASDOOR_INIT_ADMIN_PASSWORD='${cfg.initAdminPassword}' \
            ${lib.optionalString cfg.postgresql.enable ''
              -e CASDOOR_DATABASE_TYPE=postgres \
              -e CASDOOR_DATABASE_HOST=${cfg.postgresql.host} \
              -e CASDOOR_DATABASE_PORT=${toString cfg.postgresql.port} \
              -e CASDOOR_DATABASE_USER=${cfg.postgresql.user} \
              -e CASDOOR_DATABASE_NAME=${cfg.postgresql.database} \
              -v ${config.age.secrets.casdoor-postgres-password.path}:/run/secrets/db-password:ro,Z \
              -e CASDOOR_DATABASE_PASSWORD_FILE=/run/secrets/db-password \
            ''} \
            --replace \
            ghcr.io/casdoor/casdoor:v1.750.0
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop --ignore casdoor";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f casdoor || true";

        # Resource limits
        MemoryMax = "1G";
        CPUQuota = "50%";

        # Security
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = lib.mkForce "full";

        ReadWritePaths = [
          cfg.dataDir
          "/var/lib/containers/storage"
          "/run/podman"
          "/var/lib/containers"
        ];
      };
    };

    # Caddy reverse proxy (matches vaultwarden.nix pattern)
    services.caddy-module.${cfg.hostName} = {
      reverseProxy = "localhost:${toString cfg.port}";
    };

    # Firewall: allow on tailscale only (like vaultwarden)
    networking.firewall.interfaces."lo".allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];

    environment.systemPackages = with pkgs; [ casdoor ];
  };
}