{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  cfg = config.services.backup-to-garage;
  backupScript = pkgs.writeShellScriptBin "backup-to-garage" ''

        set -euo pipefail

        # Get zephyr IP from cluster config (fallback to localhost)
        ZEPHYR_IP=cluster.hosts.zephyr.ip
        GARAGE_ENDPOINT="''${GARAGE_ENDPOINT:-http://$ZEPHYR_IP:3900}"
        GARAGE_REGION="''${GARAGE_REGION:-garage}"
        GARAGE_SECRET_KEY="''${GARAGE_SECRET_KEY:-}"
        BACKUP_BUCKET="''${BACKUP_BUCKET:-backups}"
        BACKUP_DATE="$(date +%Y%m%d-%H%M%S)"
        BACKUP_PREFIX="cluster-backup"
        RETENTION_DAYS="''${RETENTION_DAYS:-30}"

        BACKUP_SOURCES=(
          "/data/shared"
        )

        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m'

        log_info() {
            echo -e "''${BLUE}[INFO]''${NC} $1"
        }

        log_success() {
            echo -e "''${GREEN}[SUCCESS]''${NC} $1"
        }

        log_warn() {
            echo -e "''${YELLOW}[WARN]''${NC} $1"
        }

        log_error() {
            echo -e "''${RED}[ERROR]''${NC} $1"
        }

        if ! command -v aws >/dev/null 2>&1; then
            log_error "awscli2 not found. Install with: nix-shell -p awscli2"
            exit 1
        fi

        # Access/secret keys are exported by the systemd wrapper from sops-nix secrets
        export AWS_ACCESS_KEY_ID="$GARAGE_ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$GARAGE_SECRET_KEY"
        export AWS_DEFAULT_REGION="$GARAGE_REGION"

        if ! aws --endpoint-url "$GARAGE_ENDPOINT" s3 ls >/dev/null 2>&1; then
            log_error "Cannot connect to Garage at $GARAGE_ENDPOINT"
            exit 1
        fi

        log_info "Starting backup: $BACKUP_DATE"
        backup_dir="/tmp/garage-backup-$BACKUP_DATE"
        archive_file="/tmp/cluster-backup-$BACKUP_DATE.tar.gz"

        mkdir -p "$backup_dir"

        log_info "Backing up NixOS configuration..."
        if [ -d /etc/nixos ]; then
            tar -czf "$backup_dir/nixos-config.tar.gz" -C /etc nixos 2>/dev/null || true
            log_success "NixOS configuration backed up"
        fi

        log_info "Backing up shared data..."
        for source in "''${BACKUP_SOURCES[@]}"; do
            if [ -d "$source" ]; then
                dirname=$(basename "$source")
                log_info "  Archiving $source..."
                tar -czf "$backup_dir/$dirname.tar.gz" -C "$(dirname "$source")" "$dirname" 2>/dev/null || log_warn "    (some files skipped)"
            fi
        done

        cat > "$backup_dir/metadata.json" <<EOF
    {
      "backup_date": "$BACKUP_DATE",
      "hostname": "$(hostname)",
      "cluster": "nixos-cluster",
      "created_at": "$(date -Iseconds)",
      "created_by": "$(whoami)"
    }
    EOF

        log_info "Creating final archive..."
        tar -czf "$archive_file" -C "$backup_dir" .
        archive_size=$(du -h "$archive_file" | cut -f1)
        log_success "Archive created: $archive_file ($archive_size)"

        log_info "Uploading to Garage S3..."
        s3_key="$BACKUP_PREFIX/cluster-backup-$BACKUP_DATE.tar.gz"

        if aws --endpoint-url "$GARAGE_ENDPOINT" s3 cp "$archive_file" "s3://$BACKUP_BUCKET/$s3_key" --checksum-algorithm CRC32; then
            log_success "Backup uploaded: s3://$BACKUP_BUCKET/$s3_key"
        else
            log_error "Upload failed"
            rm -f "$archive_file"
            rm -rf "$backup_dir"
            exit 1
        fi

        rm -f "$archive_file"
        rm -rf "$backup_dir"

        log_info "Rotating backups older than $RETENTION_DAYS days..."
        cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d 2>/dev/null || date -v-"$RETENTION_DAYS"d +%Y%m%d)

        aws --endpoint-url "$GARAGE_ENDPOINT" s3 ls "s3://$BACKUP_BUCKET/$BACKUP_PREFIX/" --recursive 2>/dev/null | while read -r line; do
            filename=$(echo "$line" | awk '{print $4}')
            file_date=$(echo "$filename" | grep -oP '\d{8}-\d{6}' | head -1 | cut -d- -f1)

            if [ -n "$file_date" ] && [ "$file_date" -lt "$cutoff_date" ]; then
                log_info "  Deleting old backup: $filename"
                aws --endpoint-url "$GARAGE_ENDPOINT" s3 rm "s3://$BACKUP_BUCKET/$filename"
            fi
        done

        log_success "Backup completed successfully"
  '';
  # Wrap shell command (source credentials + read secret + exec) in a
  # writeShellScript instead of bash -c per AGENTS.md lib helpers rule.
  # Hoisted to the file-level `let` so systemd.services can reference it
  # without needing `rec { ... }`.
  secretWrapper = pkgs.writeShellScript "backup-to-garage-secret-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail
    # /etc/backup-to-garage/credentials is already sourced by systemd
    # via EnvironmentFile below — no need to re-source here.
    ${lib.optionalString (cfg.accessKeyFile != null) ''
    if [ -r ${toString cfg.accessKeyFile} ]; then
      export GARAGE_ACCESS_KEY="$(cat ${toString cfg.accessKeyFile})"
    fi
    ''}
    ${lib.optionalString (cfg.secretKeyFile != null) ''
    if [ -r ${toString cfg.secretKeyFile} ]; then
      export GARAGE_SECRET_KEY="$(cat ${toString cfg.secretKeyFile})"
    fi
    ''}
    exec ${backupScript}/bin/backup-to-garage
  '';
in {
  options.services.backup-to-garage = {
    enable = lib.mkEnableOption "Automated backups to Garage S3";

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://${cluster.hosts.zephyr.ip}:3900"; # zephyr cluster host
      description = "Garage S3 endpoint URL";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "garage";
      description = "Garage S3 region";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "backups";
      description = "Garage S3 bucket for backups";
    };

    accessKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing Garage S3 access key ID (sops-nix)";
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing Garage S3 secret key (sops-nix)";
    };

    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Number of days to retain backups";
    };

    startAt = lib.mkOption {
      type = lib.types.str;
      default = "02:00";
      description = "When to run backups (systemd timer calendar format)";
    };

    backupPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/etc/nixos"
        "/data/shared"
      ];
      description = "Paths to include in backups";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      awscli2
      rclone
      backupScript
    ];

    # Credentials file for non-secret config values; access key and secret key
    # are read from sops-nix secrets at runtime.
    environment.etc."backup-to-garage/credentials" = {
      text = ''
        GARAGE_ENDPOINT=${cfg.endpoint}
        GARAGE_REGION=${cfg.region}
        BACKUP_BUCKET=${cfg.bucket}
        RETENTION_DAYS=${toString cfg.retentionDays}
      '';
      mode = "0600";
    };

    systemd.services.backup-to-garage = {
      description = "Backup to Garage S3";
      after = [
        "network-online.target"
        "garage.service"
      ];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin";
        ExecStart =
          if cfg.secretKeyFile != null
          then "${secretWrapper}"
          else "${backupScript}/bin/backup-to-garage";
        EnvironmentFile = "/etc/backup-to-garage/credentials";
        User = "root";
        Group = "root";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadOnlyPaths = cfg.backupPaths;
        ReadWritePaths = ["/tmp"];
      };
    };

    systemd.timers.backup-to-garage = {
      description = "Daily backup to Garage S3";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;
        Unit = "backup-to-garage.service";
      };
    };
  };
}
