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
    mkOptionDefault
    ;
in
{
  options.services.casdoor = {
    enable = mkEnableOption "Casdoor - Self-hosted SSO / OIDC / OAuth 2.0 / SAML / LDAP";

    hostName = mkOption {
      type = types.str;
      default = "auth.lan";
      description = "The hostname for Casdoor";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/casdoor";
      description = "Casdoor data directory (logs, config)";
    };

    port = mkOption {
      type = types.int;
      default = 8000;
      description = "Host port for Casdoor HTTP interface";
    };

    adminEmail = mkOption {
      type = types.str;
      default = "admin@localhost";
      description = "Initial admin email address";
    };

    organizationName = mkOption {
      type = types.str;
      default = "Casdoor";
      description = "Default organization name";
    };

    dbUser = mkOption {
      type = types.str;
      default = "casdoor";
      description = "PostgreSQL database user";
    };

    dbName = mkOption {
      type = types.str;
      default = "casdoor";
      description = "PostgreSQL database name";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;

    # Local PostgreSQL for Casdoor (zero-touch, declarative)
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = [ cfg.dbName ];
      ensureUsers = [
        {
          name = cfg.dbUser;
          ensureDBOwnership = true;
        }
      ];
      authentication = ''
        local   all   all                     trust
        host    ${cfg.dbName}  ${cfg.dbUser}  127.0.0.1/32  trust
        host    ${cfg.dbName}  ${cfg.dbUser}  ::1/128       trust
      '';
    };

    # State directory
    systemd.tmpfiles.settings."casdoor" = {
      "${cfg.dataDir}" = {
        d = {
          mode = "755";
          user = "root";
          group = "root";
        };
      };
    };

    # Generate random admin password at first boot
    systemd.services.casdoor-init-password = {
      description = "Generate Casdoor admin password";
      before = [ "casdoor.service" ];
      requiredBy = [ "casdoor.service" ];
      after = [ "systemd-tmpfiles-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        PW_FILE="${cfg.dataDir}/init-password"
        if [ ! -f "$PW_FILE" ]; then
          PW=$(${pkgs.openssl}/bin/openssl rand -base64 24)
          mkdir -p "$(dirname "$PW_FILE")"
          printf '%s' "$PW" > "$PW_FILE"
          chmod 644 "$PW_FILE"
          ln -sf "$PW_FILE" "/home/j_kro/.casdoor-init-password"
          echo "Casdoor admin password generated to $PW_FILE"
        fi
      '';
    };

    # Write app.conf for Casdoor (mounted read-only into container)
    environment.etc."casdoor/app.conf".text = ''
      appname = casdoor
      httpport = 8000
      runmode = prod
      copyrequestbody = true
      driverName = postgres
      dataSourceName = user=${cfg.dbUser} host=127.0.0.1 port=5432 sslmode=disable dbname=${cfg.dbName}
      dbName = ${cfg.dbName}
      tableNamePrefix =
      showSql = false
      redisEndpoint =
      defaultStorageProvider =
      isCloudIntranet = false
      authState = "casdoor"
      verificationCodeTimeout = 10
      initScore = 0
      logPostOnly = true
      isUsernameLowered = false
      origin = https://${cfg.hostName}
      staticBaseUrl = "https://cdn.casbin.org"
      isDemoMode = false
      batchSize = 100
      showGithubCorner = false
      defaultLanguage = "en"
      defaultApplication = "app-built-in"
      maxItemsForFlatMenu = 7
      enableGzip = true
      initDataNewOnly = false
      initDataFile = "./init_data.json"
    '';

    # Main service
    systemd.services.casdoor = {
      description = "Casdoor SSO / OIDC Service";
      after = [
        "network-online.target"
        "podman.service"
        "postgresql.service"
        "casdoor-init-password.service"
      ];
      wants = [
        "podman.service"
        "network-online.target"
      ];
      requires = [
        "postgresql.service"
        "casdoor-init-password.service"
      ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ podman openssl coreutils ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        ExecStart = pkgs.writeShellScript "casdoor-run" ''
          set -euo pipefail

          ${pkgs.podman}/bin/podman run --name casdoor \
            --network host \
            -v /etc/casdoor/app.conf:/conf/app.conf:ro \
            -e RUNNING_IN_DOCKER=true \
            --init \
            --replace \
            docker.io/casbin/casdoor:3.49.0 \
            ./server --createDatabase=true
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop --ignore casdoor";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f casdoor || true";

        MemoryMax = "1G";
        CPUQuota = "50%";

        PrivateTmp = true;
        ProtectSystem = lib.mkForce "full";

        ReadWritePaths = [
          cfg.dataDir
          "/var/lib/containers/storage"
          "/run/podman"
          "/var/lib/containers"
        ];
      };
    };

    # Firewall: allow loopback (for caddy reverse proxy)
    networking.firewall.interfaces."lo".allowedTCPPorts =
      lib.mkOptionDefault [ cfg.port ];
  };
}
