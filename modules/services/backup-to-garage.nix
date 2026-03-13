# backup-to-garage.nix - Automated backup service to Garage S3
# Systemd timer for daily backups to Garage cluster

{ config, lib, pkgs, ... }:

let
  cfg = config.services.backup-to-garage;
  # Embed the backup script directly to avoid path resolution issues
  # Note: writeShellScriptBin automatically adds the shebang
  backupScript = pkgs.writeShellScriptBin "backup-to-garage" ''
    # backup-to-garage.sh - Backup critical cluster data to Garage S3
    # Run this after Garage cluster layout is applied

    set -euo pipefail

    # Configuration from environment or defaults
    GARAGE_ENDPOINT="''${GARAGE_ENDPOINT:-http://10.1.1.110:3900}"
    GARAGE_REGION="''${GARAGE_REGION:-garage}"
    GARAGE_ACCESS_KEY="''${GARAGE_ACCESS_KEY:-GKac91d924fc76a30b9bcf6c3e}"
    GARAGE_SECRET_KEY="''${GARAGE_SECRET_KEY:-}"
    BACKUP_BUCKET="''${BACKUP_BUCKET:-backups}"
    BACKUP_DATE="$(date +%Y%m%d-%H%M%S)"
    BACKUP_PREFIX="cluster-backup"
    RETENTION_DAYS="''${RETENTION_DAYS:-30}"

    # Directories to backup
    BACKUP_SOURCES=(
      "/etc/nixos"
      "/data/shared"
    )

    # Colors for output
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

    # Check dependencies
    if ! command -v aws >/dev/null 2>&1; then
        log_error "awscli2 not found. Install with: nix-shell -p awscli2"
        exit 1
    fi

    # Configure AWS CLI for Garage
    export AWS_ACCESS_KEY_ID="$GARAGE_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$GARAGE_SECRET_KEY"
    export AWS_DEFAULT_REGION="$GARAGE_REGION"

    # Test connection
    if ! aws --endpoint-url "$GARAGE_ENDPOINT" s3 ls >/dev/null 2>&1; then
        log_error "Cannot connect to Garage at $GARAGE_ENDPOINT"
        exit 1
    fi

    # Create backup archive
    log_info "Starting backup: $BACKUP_DATE"
    backup_dir="/tmp/garage-backup-$BACKUP_DATE"
    archive_file="/tmp/cluster-backup-$BACKUP_DATE.tar.gz"

    mkdir -p "$backup_dir"

    # Backup NixOS configuration
    log_info "Backing up NixOS configuration..."
    if [ -d /etc/nixos ]; then
        tar -czf "$backup_dir/nixos-config.tar.gz" -C /etc nixos 2>/dev/null || true
        log_success "NixOS configuration backed up"
    fi

    # Backup shared data
    log_info "Backing up shared data..."
    for source in "''${BACKUP_SOURCES[@]}"; do
        if [ -d "$source" ]; then
            dirname=$(basename "$source")
            log_info "  Archiving $source..."
            tar -czf "$backup_dir/$dirname.tar.gz" -C "$(dirname "$source")" "$dirname" 2>/dev/null || log_warn "    (some files skipped)"
        fi
    done

    # Create backup metadata
    cat > "$backup_dir/metadata.json" <<EOF
{
  "backup_date": "$BACKUP_DATE",
  "hostname": "$(hostname)",
  "cluster": "nixos-cluster",
  "created_at": "$(date -Iseconds)",
  "created_by": "$(whoami)"
}
EOF

    # Create final archive
    log_info "Creating final archive..."
    tar -czf "$archive_file" -C "$backup_dir" .
    archive_size=$(du -h "$archive_file" | cut -f1)
    log_success "Archive created: $archive_file ($archive_size)"

    # Upload to Garage
    log_info "Uploading to Garage S3..."
    s3_key="$BACKUP_PREFIX/cluster-backup-$BACKUP_DATE.tar.gz"

    if aws --endpoint-url "$GARAGE_ENDPOINT" s3 cp "$archive_file" "s3://$BACKUP_BUCKET/$s3_key"; then
        log_success "Backup uploaded: s3://$BACKUP_BUCKET/$s3_key"
    else
        log_error "Upload failed"
        rm -f "$archive_file"
        rm -rf "$backup_dir"
        exit 1
    fi

    # Cleanup
    rm -f "$archive_file"
    rm -rf "$backup_dir"

    # Rotate old backups
    log_info "Rotating backups older than $RETENTION_DAYS days..."
    cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d 2>/dev/null || date -v-"$RETENTION_DAYS"d +%Y%m%d)

    aws --endpoint-url "$GARAGE_ENDPOINT" s3 ls "s3://$BACKUP_BUCKET/$BACKUP_PREFIX/" --recursive 2>/dev/null | while read -r line; do
        filename=$(echo "$line" | awk '{print $4}')
        file_date=$(echo "$filename" | grep -oP '\d{8}-\d{6}' | head -1)

        if [ -n "$file_date" ] && [ "$file_date" -lt "$cutoff_date" ]; then
            log_info "  Deleting old backup: $filename"
            aws --endpoint-url "$GARAGE_ENDPOINT" s3 rm "s3://$BACKUP_BUCKET/$filename"
        fi
    done

    log_success "Backup completed successfully"
  '';
in
{
  options.services.backup-to-garage = {
    enable = lib.mkEnableOption "Automated backups to Garage S3";

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://10.1.1.110:3900";
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

    accessKey = lib.mkOption {
      type = lib.types.str;
      default = "GKac91d924fc76a30b9bcf6c3e";
      description = "Garage S3 access key ID";
    };

    # Secret key should be set via agenix
    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing Garage S3 secret key (agenix)";
    };

    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Number of days to retain backups";
    };

    # Backup schedule (systemd timer format)
    startAt = lib.mkOption {
      type = lib.types.str;
      default = "02:00";  # 2 AM daily
      description = "When to run backups (systemd timer calendar format)";
    };

    # What to backup
    backupPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/etc/nixos" "/data/shared" ];
      description = "Paths to include in backups";
    };
  };

  config = lib.mkIf cfg.enable {
    # Required packages
    environment.systemPackages = with pkgs; [
      awscli2
      rclone
      backupScript
    ];

    # Environment file for secrets
    environment.etc."backup-to-garage/credentials".text = ''
      GARAGE_ENDPOINT=${cfg.endpoint}
      GARAGE_REGION=${cfg.region}
      GARAGE_ACCESS_KEY=${cfg.accessKey}
      BACKUP_BUCKET=${cfg.bucket}
      RETENTION_DAYS=${toString cfg.retentionDays}
    '';

    # Systemd service
    systemd.services.backup-to-garage = {
      description = "Backup to Garage S3";
      after = [ "network-online.target" "garage.service" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        # Explicit PATH for AWS CLI
        Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin";
        # Inject secret key directly into environment via shell wrapper if secretKeyFile is set
        ExecStart = if cfg.secretKeyFile != null then
          "${pkgs.bash}/bin/bash -c 'source /etc/backup-to-garage/credentials && export GARAGE_SECRET_KEY=$(cat ${cfg.secretKeyFile}) && exec ${backupScript}/bin/backup-to-garage'"
        else
          "${backupScript}/bin/backup-to-garage";
        EnvironmentFile = "/etc/backup-to-garage/credentials";
        User = "root";
        Group = "root";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadOnlyPaths = cfg.backupPaths;
        ReadWritePaths = [ "/tmp" ];
      };
    };

    # Systemd timer
    systemd.timers.backup-to-garage = {
      description = "Daily backup to Garage S3";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;  # Run immediately if last run was missed
        Unit = "backup-to-garage.service";
      };
    };
  };
}
