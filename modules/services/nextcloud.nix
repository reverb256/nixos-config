{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nextcloud-module;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    mkDefault
    ;
in {
  options.services.nextcloud-module = {
    enable = mkEnableOption "Nextcloud - Self-hosted collaboration platform";

    hostName = mkOption {
      type = types.str;
      example = "cloud.example.com";
      description = "The hostname for Nextcloud (must resolve to this server)";
    };

    database = {
      create = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically create the database and user";
      };

      name = mkOption {
        type = types.str;
        default = "nextcloud";
        description = "PostgreSQL database name";
      };

      user = mkOption {
        type = types.str;
        default = "nextcloud";
        description = "PostgreSQL database user";
      };
    };

    admin = {
      user = mkOption {
        type = types.str;
        default = "admin";
        description = "Nextcloud admin username";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/secrets/nextcloud-admin-pass";
        description = "Path to file containing admin password (use sops-nix)";
      };
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/nextcloud";
      description = "Nextcloud data directory";
    };

    maxUploadSize = mkOption {
      type = types.str;
      default = "16G";
      description = "Maximum upload size for files (e.g., 16G, 512M)";
    };

    apps = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Nextcloud apps";
      };

      files = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Files app (file sync and sharing)";
      };

      text = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Text app (collaborative Markdown editing)";
      };

      deck = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Deck app (Kanban boards for project tracking)";
      };

      calendar = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Calendar app (CalDAV)";
      };

      contacts = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Contacts app (CardDAV)";
      };

      tasks = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Tasks app";
      };

      notes = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Notes app (Markdown notes with mobile sync)";
      };

      talk = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Talk app (video calls, chat, and Matrix bridge)";
      };

      onlyoffice = mkOption {
        type = types.bool;
        default = false;
        description = "Enable OnlyOffice (collaborative document editing)";
      };

      collabora = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Collabora (LibreOffice Online)";
      };
    };

    https = mkOption {
      type = types.bool;
      default = true;
      description = "Enable HTTPS with automatic certificate generation";
    };

    synapseIntegration = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Create integration directories for Synapse AI command center";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/nextcloud/data/synapse";
        description = "Directory for Synapse-generated content";
      };
    };

    php = {
      memoryLimit = mkOption {
        type = types.str;
        default = "512M";
        description = "PHP memory limit";
      };

      maxExecutionTime = mkOption {
        type = types.int;
        default = 3600;
        description = "PHP maximum execution time in seconds";
      };
    };
  };

  config = mkIf cfg.enable {
    services = {
      postgresql = mkIf cfg.database.create {
        enable = lib.mkDefault true;
        ensureDatabases = [cfg.database.name];
        ensureUsers = [
          {
            name = cfg.database.user;
            ensureDBOwnership = true;
          }
        ];
      };

      nextcloud = {
        enable = lib.mkDefault true;

        inherit (cfg) hostName https;

        config = {
          dbtype = "pgsql";
          dbuser = cfg.database.user;
          dbname = cfg.database.name;
          dbhost = "/run/postgresql";

          adminuser = cfg.admin.user;
          adminpassFile = cfg.admin.passwordFile;
        };

        phpOptions = {
          "upload_max_filesize" = cfg.maxUploadSize;
          "post_max_size" = cfg.maxUploadSize;
          "memory_limit" = cfg.php.memoryLimit;
          "max_execution_time" = toString cfg.php.maxExecutionTime;
          "max_input_time" = toString cfg.php.maxExecutionTime;
        };

        autoUpdateApps.enable = true;

        caching = {
          redis = true;
          apcu = true;
        };

        configureRedis = true;

        settings = {
          "memcache.local" = "\\OC\\Memcache\\APCu";
          "memcache.distributed" = "\\OC\\Memcache\\Redis";
          "memcache.locking" = "\\OC\\Memcache\\Redis";
          "redis.host" = "localhost";
          "redis.port" = 6379;

          "default_phone_region" = "US";

          "enable_previews" = true;
          "enabledPreviewProviders" = [
            "OC\\Preview\\Image"
            "OC\\Preview\\MarkDown"
            "OC\\Preview\\TXT"
            "OC\\Preview\\OpenDocument"
            "OC\\Preview\\Movie"
          ];

          "session_lifetime" = 86400;
          "session_keepalive" = true;

          "cron.log" = true;
        };

        extraOptions = {
          "dbserveroptions" = {
            "max_connections" = 100;
          };
        };
      };

      redis.servers.nextcloud = {
        enable = lib.mkDefault true;
        bind = "127.0.0.1";
        port = 6379;
      };

      nginx = {
        enable = mkDefault true;

        clientMaxBodySize = cfg.maxUploadSize;

        virtualHosts.${cfg.hostName} = mkMerge [
          {
            forceSSL = cfg.https;
            enableACME = cfg.https;
          }
          {
            extraConfig = ''
              add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
              add_header X-Frame-Options "SAMEORIGIN" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header X-XSS-Protection "1; mode=block" always;

              gzip on;
              gzip_vary on;
              gzip_comp_level 6;
              gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/rss+xml font/truetype font/opentype application/vnd.ms-fontobject image/svg+xml;
            '';
          }
        ];
      };

      cron = {
        enable = lib.mkDefault true;
        systemCronJobs = [
          "*/5 * * * * nextcloud php -f ${config.services.nextcloud.package}/occ system:cron"
        ];
      };

      prometheus.exporters.nextcloud = mkIf config.services.prometheus.enable {
        enable = lib.mkDefault true;
        url = "https://${cfg.hostName}";
        username = cfg.admin.user;
        inherit (cfg.admin) passwordFile;
      };
    };

    networking.firewall = mkIf cfg.https {
      allowedTCPPorts = lib.mkOptionDefault [
        80
        443
      ];
    };

    systemd = mkIf cfg.synapseIntegration.enable {
      tmpfiles.rules = [
        "d ${cfg.synapseIntegration.dataDir} 0755 nextcloud nextcloud -"
        "d ${cfg.synapseIntegration.dataDir}/agent-logs 0755 nextcloud nextcloud -"
        "d ${cfg.synapseIntegration.dataDir}/conversation-history 0755 nextcloud nextcloud -"
        "d ${cfg.synapseIntegration.dataDir}/project-artifacts 0755 nextcloud nextcloud -"
      ];

      services = {
        nextcloud-setup.serviceConfig = {
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          RestrictRealtime = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
        };

        "php-fpm-nextcloud".serviceConfig = {
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          RestrictRealtime = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
        };
      };
    };

    environment = {
      systemPackages = with pkgs; [
        nextcloud-client
        nextcloud-exporter
      ];

      etc."nextcloud-integration.md".text = ''

        - Web: https://${cfg.hostName}
        - WebDAV: https://${cfg.hostName}/remote.php/webdav/
        - CalDAV: https://${cfg.hostName}/remote.php/dav/

        ```bash
        environment.systemPackages = [ pkgs.nextcloud-client ];

        flatpak install flathub com.nextcloud.desktopclient.nextcloud
        ```

        ${mkIf cfg.synapseIntegration.enable ''
          Synapse data directories:
          - Agent logs: ${cfg.synapseIntegration.dataDir}/agent-logs
          - Conversations: ${cfg.synapseIntegration.dataDir}/conversation-history
          - Artifacts: ${cfg.synapseIntegration.dataDir}/project-artifacts

          WebDAV mount in Synapse:
          - URL: https://${cfg.hostName}/remote.php/webdav/
          - Username: ${cfg.admin.user}
          - Password: <your-password>
        ''}
      '';
    };
  };
}
