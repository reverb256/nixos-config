{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.openclaw-backups;
in {
  options.services.openclaw-backups = {
    enable = lib.mkEnableOption "automated cloud backups for OpenClaw AIStor";

    remote = lib.mkOption {
      type = lib.types.str;
      default = "gdrive";
      description = "Rclone remote name for cloud backups (e.g., gdrive, b2, s3)";
    };

    buckets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["ai-models" "experiments"];
      description = "Buckets to backup to cloud";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Backup interval (systemd calendar format)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "lobster";
      description = "User to run backup scripts";
    };

    aistorEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://192.168.100.X:9000";
      description = "AIStor S3 endpoint";
    };

    rcloneConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to rclone config file (if not using default location)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure rclone is installed
    environment.systemPackages = with pkgs; [
      rclone
    ];

    # Create backup scripts
    environment.etc = {
      "openclaw/backup-models.sh" = {
        text = ''
          #!/usr/bin/env bash
          set -e

          REMOTE="${cfg.remote}"
          LOG_FILE="/var/lib/lobster/storage/logs/backup-models-$(date +%Y%m%d).log"

          mkdir -p "$(dirname "$LOG_FILE")"

          echo "[$(date)] Starting models backup to $REMOTE..." >> "$LOG_FILE"

          ${pkgs.rclone}/bin/rclone sync \
            :s3:ai-models \
            "$REMOTE:openclaw-ai-models-backup" \
            --s3-endpoint "${cfg.aistorEndpoint}" \
            --s3-provider Minio \
            --s3-region us-east-1 \
            --s3-force-path-style \
            --progress \
            --transfers 4 \
            --checkers 8 \
            --log-file "$LOG_FILE" \
            --log-level INFO \
            --exclude ".tmp/**" \
            --exclude "*.temp"

          echo "[$(date)] Models backup complete" >> "$LOG_FILE"
        '';
        mode = "0755";
      };

      "openclaw/backup-experiments.sh" = {
        text = ''
          #!/usr/bin/env bash
          set -e

          REMOTE="${cfg.remote}"
          LOG_FILE="/var/lib/lobster/storage/logs/backup-experiments-$(date +%Y%m%d).log"

          mkdir -p "$(dirname "$LOG_FILE")"

          echo "[$(date)] Starting experiments backup to $REMOTE..." >> "$LOG_FILE"

          ${pkgs.rclone}/bin/rclone sync \
            :s3:experiments \
            "$REMOTE:openclaw-experiments-backup" \
            --s3-endpoint "${cfg.aistorEndpoint}" \
            --s3-provider Minio \
            --s3-region us-east-1 \
            --s3-force-path-style \
            --progress \
            --transfers 4 \
            --checkers 8 \
            --log-file "$LOG_FILE" \
            --log-level INFO

          echo "[$(date)] Experiments backup complete" >> "$LOG_FILE"
        '';
        mode = "0755";
      };

      "openclaw/backup-all.sh" = {
        text = ''
          #!/usr/bin/env bash
          set -e

          REMOTE="''${1:-${cfg.remote}}"

          echo "=== Starting full backup to $REMOTE ==="

          echo "Backing up ai-models..."
          /etc/openclaw/backup-models.sh

          echo "Backing up experiments..."
          /etc/openclaw/backup-experiments.sh

          echo "=== Full backup complete ==="
        '';
        mode = "0755";
      };
    };

    # Create systemd service and timer
    systemd.services.openclaw-backup = {
      description = "OpenClaw AIStor Cloud Backup";
      after = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.user;
        ExecStart = "/etc/openclaw/backup-all.sh";
        Environment = lib.optional (cfg.rcloneConfigFile != null) "RCLONE_CONFIG=${cfg.rcloneConfigFile}";
      };
    };

    systemd.timers.openclaw-backup = {
      description = "Scheduled backup of OpenClaw AIStor to cloud";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = 3600; # Randomize within 1 hour to avoid thundering herd
      };
    };

    # Ensure log directory exists
    systemd.tmpfiles.settings.openclaw-backups = {
      "/var/lib/lobster/storage/logs" = {
        d = {
          user = cfg.user;
          group = cfg.user;
          mode = "0750";
        };
      };
    };
  };
}
