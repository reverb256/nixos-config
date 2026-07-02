{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  cfg = config.services.rclone-sync;

  syncScript = job:
    pkgs.writeShellScriptBin "rclone-${job.name}" ''
      set -euo pipefail

      SOURCE="''${SOURCE:-${job.source}}"
      DEST="''${DEST:-${job.destination}}"
      SYNC_MODE="''${SYNC_MODE:-${job.mode or "sync"}}"
      OPTIONS="''${OPTIONS:-${toString job.options or ""}}"

      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      BLUE='\033[0;34m'
      NC='\033[0m'

      log_info() { echo -e "''${BLUE}[INFO]''${NC} $1"; }
      log_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
      log_warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }
      log_error() { echo -e "''${RED}[ERROR]''${NC} $1"; }

      log_info "Starting rclone job: ${job.name}"
      log_info "Source: $SOURCE"
      log_info "Destination: $DEST"
      log_info "Mode: $SYNC_MODE"

      if ${pkgs.rclone}/bin/rclone "$SYNC_MODE" "$SOURCE" "$DEST" \
        --config "${cfg.configFile}" \
        --progress \
        --transfers ${toString job.transfers or 4} \
        --checkers ${toString job.checkers or 8} \
        ${
        if job.exclude != null
        then "--exclude=${job.exclude}"
        else ""
      } \
        ${
        if job.excludeFrom != null
        then "--exclude-from=${job.excludeFrom}"
        else ""
      } \
        ${
        if job.include != null
        then "--include=${job.include}"
        else ""
      } \
        ${
        if job.includeFrom != null
        then "--include-from=${job.includeFrom}"
        else ""
      } \
        ${lib.concatStringsSep " " (map (o: "--${o}") (job.extraFlags or []))} \
        $OPTIONS; then
        log_success "Job '${job.name}' completed"
      else
        log_error "Job '${job.name}' failed"
        exit 1
      fi
    '';
in {
  options.services.rclone-sync = {
    enable = lib.mkEnableOption "Rclone cloud storage synchronization";

    configFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/rclone/rclone.conf";
      description = "Path to rclone configuration file";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User to run rclone services as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Group to run rclone services as";
    };

    remotes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            type = lib.mkOption {
              type = lib.types.enum [
                "s3"
                "onedrive"
                "dropbox"
                "box"
                "mega"
                "b2"
                "drive"
                "webdav"
                "ftp"
                "sftp"
                "http"
              ];
              default = "s3";
              description = "Remote storage type";
            };
            provider = lib.mkOption {
              type = lib.types.str;
              default = "Other";
              description = "S3 provider (AWS, Other, Minio, etc.)";
            };
            endpoint = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "S3 endpoint URL";
            };
            accessKeyId = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Access key ID for S3";
            };
            secretAccessKey = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Secret access key (use sops-nix!)";
            };
            region = lib.mkOption {
              type = lib.types.str;
              default = "us-east-1";
              description = "S3 region";
            };
            forcePathStyle = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Force path-style S3 URLs";
            };
            token = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OAuth token (for onedrive, dropbox, etc.)";
            };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Username (for mega, ftp, sftp)";
            };
            pass = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Password (use sops-nix!)";
            };
            account = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Account ID (for B2)";
            };
            key = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Application key (for B2)";
            };
            client_id = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OAuth client ID";
            };
            client_secret = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OAuth client secret";
            };
            scope = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OAuth scope (for Google Drive)";
            };
          };
        }
      );
      default = {};
      description = "Remote storage configurations";
      example = {
        garage = {
          type = "s3";
          provider = "Other";
          endpoint = "http://${cluster.hosts.zephyr.ip}:3900";
          region = "garage";
        };
        onedrive = {
          type = "onedrive";
          token = "";
        };
      };
    };

    syncJobs = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Job name (used for service/timer names)";
            };
            source = lib.mkOption {
              type = lib.types.str;
              description = "Source path (remote: or /local/path)";
            };
            destination = lib.mkOption {
              type = lib.types.str;
              description = "Destination path (remote: or /local/path)";
            };
            mode = lib.mkOption {
              type = lib.types.enum [
                "sync"
                "copy"
                "move"
                "check"
                "ls"
                "lsl"
                "lsd"
                "lsf"
              ];
              default = "sync";
              description = "Rclone operation mode";
            };
            transfers = lib.mkOption {
              type = lib.types.int;
              default = 4;
              description = "Number of parallel file transfers";
            };
            checkers = lib.mkOption {
              type = lib.types.int;
              default = 8;
              description = "Number of checkers to run in parallel";
            };
            exclude = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Exclude files matching pattern";
            };
            excludeFrom = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Read exclude patterns from file";
            };
            include = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Include files matching pattern";
            };
            includeFrom = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Read include patterns from file";
            };
            options = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Additional options string";
            };
            extraFlags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Extra command-line flags (without -- prefix)";
            };
            enableTimer = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable systemd timer for automated execution";
            };
            startAt = lib.mkOption {
              type = lib.types.str;
              default = "02:00";
              description = "When to run (systemd timer calendar format)";
            };
          };
        }
      );
      default = [];
      description = "Sync job definitions";
      example = [
        {
          name = "garage-to-onedrive";
          source = "garage:backups";
          destination = "onedrive:garage-backups";
          mode = "sync";
          startAt = "03:00";
        }
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.rclone];

    # The rclone config should contain all remote definitions with credentials.
    # Remove individual remote credential options when migrating fully to sops-nix.
    environment.etc."rclone/rclone.conf" = {
      source = "/run/secrets/rclone-config";
      mode = "0400";
      user = "root";
      group = "root";
    };

    systemd.services = lib.listToAttrs (
      map (job: {
        name = "rclone-${job.name}";
        value = {
          description = "Rclone sync: ${job.name}";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            ExecStart = "${syncScript job}/bin/rclone-${job.name}";
            Environment = [
              "PATH=/run/current-system/sw/bin"
              "RCLONE_CONFIG=${cfg.configFile}"
            ];
            PrivateTmp = true;
            NoNewPrivileges = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
            ];
          };
        };
      })
      cfg.syncJobs
    );

    systemd.timers = lib.listToAttrs (
      map (job: {
        name = "rclone-${job.name}";
        value =
          {
            inherit (job) enableTimer;
          }
          // lib.optionalAttrs job.enableTimer {
            wantedBy = ["timers.target"];
            timerConfig = {
              OnCalendar = job.startAt;
              Persistent = true;
              Unit = "rclone-${job.name}.service";
            };
          };
      })
      cfg.syncJobs
    );
  };
}
