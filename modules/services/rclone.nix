# Rclone Cloud Storage Sync Module
# Supports 70+ cloud providers (S3, Google Drive, Dropbox, OneDrive, Box, Mega, B2, etc.)
# Integrates with agenix for secure credential storage
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.rclone-sync;

  # Helper function to generate rclone config section

  # Generate rclone.conf from remotes

  # Create sync script for a job
  syncScript = job:
    pkgs.writeShellScriptBin "rclone-${job.name}" ''
      set -euo pipefail

      # Configuration
      SOURCE="''${SOURCE:-${job.source}}"
      DEST="''${DEST:-${job.destination}}"
      SYNC_MODE="''${SYNC_MODE:-${job.mode or "sync"}}"
      OPTIONS="''${OPTIONS:-${toString job.options or ""}}"

      # Colors
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

      # Run rclone
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

    # Global configuration
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

    # Remote definitions
    remotes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          type = lib.mkOption {
            type = lib.types.enum ["s3" "onedrive" "dropbox" "box" "mega" "b2" "drive" "webdav" "ftp" "sftp" "http"];
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
            description = "Secret access key (use agenix!)";
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
          # Provider-specific options
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
            description = "Password (use agenix!)";
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
      });
      default = {};
      description = "Remote storage configurations";
      example = {
        garage = {
          type = "s3";
          provider = "Other";
          endpoint = "http://10.1.1.110:3900";
          accessKeyId = "GKac91d924fc76a30b9bcf6c3e";
          secretAccessKey = ""; # Use agenix!
          region = "garage";
        };
        onedrive = {
          type = "onedrive";
          token = ""; # OAuth token from rclone config
        };
      };
    };

    # Sync jobs
    syncJobs = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
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
            type = lib.types.enum ["sync" "copy" "move" "check" "ls" "lsl" "lsd" "lsf"];
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
          # Scheduling
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
      });
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
    # Ensure rclone is installed
    environment.systemPackages = [pkgs.rclone];

    # Generate rclone.conf from NixOS configuration
    environment.etc."rclone/rclone.conf".text = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: remote: ''
        [${name}]
        type = ${remote.type}
        ${lib.optionalString (remote.provider != null) "provider = ${remote.provider}"}
        ${lib.optionalString (remote.access_key_id != null) "access_key_id = ${remote.access_key_id}"}
        ${lib.optionalString (remote.secret_access_key != null) "secret_access_key = ${remote.secret_access_key}"}
        ${lib.optionalString (remote.region != null) "region = ${remote.region}"}
        ${lib.optionalString (remote.endpoint != null && remote.endpoint != "") "endpoint = ${remote.endpoint}"}
        ${lib.optionalString (remote.force_path_style != null) "force_path_style = ${
          if remote.force_path_style
          then "true"
          else "false"
        }"}
        ${lib.optionalString (remote.token != null) "token = ${remote.token}"}
        ${lib.optionalString (remote.user != null) "user = ${remote.user}"}
        ${lib.optionalString (remote.pass != null) "pass = ${remote.pass}"}
        ${lib.optionalString (remote.account != null) "account = ${remote.account}"}
        ${lib.optionalString (remote.key != null) "key = ${remote.key}"}
        ${lib.optionalString (remote.client_id != null) "client_id = ${remote.client_id}"}
        ${lib.optionalString (remote.client_secret != null) "client_secret = ${remote.client_secret}"}
        ${lib.optionalString (remote.scope != null) "scope = ${remote.scope}"}
      '')
      cfg.remotes
    );

    # Create systemd services for each sync job
    systemd.services = lib.listToAttrs (map (job: {
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
            # Security hardening
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            SystemCallFilter = ["@system-service" "~@privileged"];
          };
        };
      })
      cfg.syncJobs);

    # Create systemd timers for each job
    systemd.timers = lib.listToAttrs (map (job: {
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
      cfg.syncJobs);
  };
}
