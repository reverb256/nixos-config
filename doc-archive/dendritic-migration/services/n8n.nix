{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.n8n;
  n8nPort = toString cfg.port;
  n8nUser = "n8n";
  n8nGroup = "n8n";
in {
  options.services.n8n = {
    enable = lib.mkEnableOption "n8n workflow automation service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.n8n;
      defaultText = lib.literalExample "pkgs.n8n";
      description = "n8n package to use.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5678;
      description = "Port on which n8n will listen.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host on which n8n will listen.";
    };

    dbType = lib.mkOption {
      type = lib.types.enum ["sqlite" "postgres"];
      default = "sqlite";
      description = "Database type for n8n.";
    };

    postgresql = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable PostgreSQL database for n8n.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port for n8n database.";
      };
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExample "/run/agenix/n8n-env";
      description = "Environment file for n8n configuration (for encrypted credentials).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall for n8n port.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-start the n8n service.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create n8n user and group
    users.users = lib.optionalAttrs (!lib.hasAttr "n8n" config.users.users) {
      ${n8nUser} = {
        description = "n8n workflow automation user";
        isSystemUser = true;
        group = n8nGroup;
      };
    };

    users.groups = lib.optionalAttrs (!lib.hasAttr "n8n" config.users.groups) {
      ${n8nGroup} = {};
    };

    # PostgreSQL database for n8n if enabled
    services.postgresql = lib.mkIf cfg.postgresql.enable {
      enable = true;
      ensureDatabases = ["n8ndb"];
      ensureUsers = [
        {
          name = "n8n";
          ensurePermissions = {"DATABASE n8ndb" = "ALL PRIVILEGES";};
        }
      ];
    };

    # Firewall configuration
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };

    # n8n service
    systemd.services.n8n = {
      description = "n8n workflow automation service";
      after = ["network.target"];
      wantedBy = lib.optionals cfg.autoStart ["multi-user.target"];

      preStart = lib.mkBefore ''
        # Create data directory if it doesn't exist
        mkdir -p /var/lib/n8n
        chown ${n8nUser}:${n8nGroup} /var/lib/n8n
      '';

      serviceConfig = {
        Type = "simple";
        User = n8nUser;
        Group = n8nGroup;
        ExecStart = lib.concatStringsSep " " ([
            "${cfg.package}/bin/n8n"
            "--port ${n8nPort}"
            "--listen_address ${cfg.host}"
          ]
          ++ lib.optional (cfg.dbType == "postgres") "--db-type postgres"
          ++ lib.optional (cfg.dbType == "postgres") "--database-postgresdb-database n8ndb"
          ++ lib.optional (cfg.dbType == "postgres") "--database-postgresdb-host localhost"
          ++ lib.optional (cfg.dbType == "postgres") "--database-postgresdb-port ${toString cfg.postgresql.port}");
        Restart = "always";
        RestartSec = 10;
        Environment = [
          "N8N_DATA_DIR=/var/lib/n8n"
          "N8N_DIAGNOSTICS_ENABLED=false"
          "N8N_PERSONALIZATION_ENABLED=false"
          "N8N_USER_MANAGEMENT_JWT_SECRET="
          "N8N_ENCRYPTION_KEY="
        ];
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) [cfg.environmentFile];
        WorkingDirectory = "/var/lib/n8n";
        StateDirectory = "n8n";
        LogsDirectory = "n8n";
      };
    };

    environment.systemPackages = [cfg.package];
  };
}
