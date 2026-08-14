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
        ZEPHYR_IP=${cluster.hosts.zephyr.ip}
        GARAGE_ENDPOINT="''${GARAGE_ENDPOINT:-http://$ZEPHYR_IP:3900}"
        GARAGE_REGION="''${GARAGE_REGION:-garage}"
        GARAGE_SECRET_KEY="''${GARAGE_SECRET_KEY:-}"
        BACKUP_BUCKET="''${BACKUP_BUCKET:-backups}"
        BACKUP_DATE="$(date +%Y%m%d-%H%M%S)"
        BACKUP_PREFIX="cluster-backup"
        RETENTION_DAYS="''${RETENTION_DAYS:-30}"

        # Use the declarative backupPaths option (was hardcoded /data/shared,
        # which does not exist on zephyr — mount-namespace NAMESPACE 226
        # failure 2026-08-14).
        BACKUP_SOURCES=(
          ${builtins.concatStringsSep "\n" (map (p: "\"${p}\"") cfg.backupPaths)}
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
        # STREAM to Garage — never buffer full tarballs in /tmp. The old
        # implementation tar'd every source into /tmp/garage-backup-*/ then
        # re-tar'd into a second archive before uploading, which filled the
        # root volume (PrivateTmp=true puts it on /) — 2026-08-14 wedge:
        # 173G partial tarball, root at 100%, system went read-only.
        # Now each source streams: tar | aws s3 cp - (S3 multipart stdin).
        s3_key="$BACKUP_PREFIX/$BACKUP_DATE/"
        log_info "Backing up NixOS configuration..."
        if [ -d /etc/nixos ]; then
            log_info "  Streaming nixos-config to s3://$BACKUP_BUCKET/$s3_key"
            tar -czf - -C /etc nixos 2>/dev/null \
              | aws --endpoint-url "$GARAGE_ENDPOINT" s3 cp - "s3://$BACKUP_BUCKET/${s3_key}nixos-config.tar.gz" --checksum-algorithm CRC32 \
              && log_success "  nixos-config backed up" \
              || log_warn "  nixos-config backup failed"
        fi

        log_info "Backing up shared data..."
        for source in "''${BACKUP_SOURCES[@]}"; do
            if [ -d "$source" ]; then
                dirname=$(basename "$source")
                log_info "  Streaming $source..."
                tar -czf - -C "$(dirname "$source")" "$dirname" 2>/dev/null \
                  | aws --endpoint-url "$GARAGE_ENDPOINT" s3 cp - "s3://$BACKUP_BUCKET/${s3_key}${dirname}.tar.gz" --checksum-algorithm CRC32 \
                  && log_success "  $dirname backed up" \
                  || log_warn "  $dirname backup failed (some files may be in use)"
            fi
        done

        cat > /tmp/garage-backup-metadata-$$.json <<EOF
    {
      "backup_date": "$BACKUP_DATE",
      "hostname": "$(hostname)",
      "cluster": "nixos-cluster",
      "created_at": "$(date -Iseconds)",
      "created_by": "$(whoami)"
    }
EOF
        aws --endpoint-url "$GARAGE_ENDPOINT" s3 cp /tmp/garage-backup-metadata-$$.json "s3://$BACKUP_BUCKET/${s3_key}metadata.json" --checksum-algorithm CRC32 >/dev/null 2>&1 || true
        rm -f /tmp/garage-backup-metadata-$$.json
        log_success "Backup uploaded: s3://$BACKUP_BUCKET/$s3_key"

        log_info "Rotating backups older than $RETENTION_DAYS days..."
        cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d 2>/dev/null || date -v-"$RETENTION_DAYS"d +%Y%m%d)

        # Streaming layout: s3://bucket/$BACKUP_PREFIX/<YYYYMMDD-HHMMSS>/<source>.tar.gz
        # Rotate by directory prefix date.
        aws --endpoint-url "$GARAGE_ENDPOINT" s3 ls "s3://$BACKUP_BUCKET/$BACKUP_PREFIX/" 2>/dev/null | while read -r line; do
            prefix=$(echo "$line" | awk '{print $2}')
            [ -z "$prefix" ] && continue
            dir_date=$(echo "$prefix" | grep -oE '^[0-9]{8}' | head -1)

            if [ -n "$dir_date" ] && [ "$dir_date" -lt "$cutoff_date" ]; then
                log_info "  Deleting old backup: $prefix"
                aws --endpoint-url "$GARAGE_ENDPOINT" s3 rm --recursive "s3://$BACKUP_BUCKET/$BACKUP_PREFIX/$prefix"
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
      default = "http://${cluster.hosts.nexus.ip}:3900"; # Garage S3 server on nexus
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
        # No PrivateTmp: the old tar-to-/tmp approach filled the root volume
        # (2026-08-14 wedge — 173G tarball). Streaming to Garage needs no
        # private temp; keep the sandbox tight instead.
        NoNewPrivileges = true;
        ReadOnlyPaths = cfg.backupPaths;
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
