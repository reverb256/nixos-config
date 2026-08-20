{
  config,
  lib,
  pkgs,
  ...
}:
# memlawb fs-blobstore backup to Garage S3 (dedicated, per-file sync).
#
# REUSES the existing Garage S3 credential convention already wired on sentry
# by services.backup-to-garage / hosts/sentry/secretspec-creds-wiring.nix:
#   - sops secrets at /run/secrets/garage-s3-access-key-id + garage-s3-secret-key
#   - endpoint http://10.1.1.120:3900, region "garage", bucket "backups"
# We deliberately do NOT duplicate a separate rclone config; we reuse the same
# secret files and bucket convention, and mirror backup-to-garage's
# secret-wrapper + EnvironmentFile plumbing (awscli2 s3 sync).
#
# This complements (does not replace) the tar-based /persistent backup in
# services.backup-to-garage: a per-file `aws s3 sync` gives granular,
# directly-restorable copies of the ciphertext blobstore, so a single corrupt
# blob can be restored without unpacking a whole tarball.
#
# Enable on sentry, e.g. in hosts/sentry/configuration.nix:
#   services.memlawb-backup.enable = true;
let
  cfg = config.services.memlawb-backup;

  backupScript = pkgs.writeShellScriptBin "memlawb-backup" ''
    set -euo pipefail

    GARAGE_ENDPOINT="''${GARAGE_ENDPOINT:-http://10.1.1.120:3900}"
    GARAGE_REGION="''${GARAGE_REGION:-garage}"
    BACKUP_BUCKET="''${BACKUP_BUCKET:-backups}"
    SOURCE_DIR="''${SOURCE_DIR:-/persistent/memlawb-data}"
    DEST_PREFIX="''${DEST_PREFIX:-memlawb-data}"

    export AWS_ACCESS_KEY_ID="$GARAGE_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$GARAGE_SECRET_KEY"
    export AWS_DEFAULT_REGION="$GARAGE_REGION"
    export AWS_EC2_METADATA_DISABLED=true

    if [ ! -d "$SOURCE_DIR" ]; then
      echo "memlawb-backup: source dir missing: $SOURCE_DIR" >&2
      exit 1
    fi

    if ! ${pkgs.awscli2}/bin/aws --endpoint-url "$GARAGE_ENDPOINT" s3 ls >/dev/null 2>&1; then
      echo "memlawb-backup: cannot connect to Garage at $GARAGE_ENDPOINT" >&2
      exit 1
    fi

    echo "memlawb-backup: syncing $SOURCE_DIR -> s3://$BACKUP_BUCKET/$DEST_PREFIX"
    # NOTE: no --delete — a backup must never prune remote objects if the local
    # store is briefly empty/partial (e.g. during a store rebuild). Additive
    # sync only; old blobs accumulate (cheap, and they are the safety net).
    if ! ${pkgs.awscli2}/bin/aws --endpoint-url "$GARAGE_ENDPOINT" s3 sync \
      "$SOURCE_DIR" "s3://$BACKUP_BUCKET/$DEST_PREFIX" --no-progress; then
      echo "memlawb-backup: sync failed" >&2
      exit 1
    fi

    # Verify the destination prefix is reachable and non-empty.
    if ! ${pkgs.awscli2}/bin/aws --endpoint-url "$GARAGE_ENDPOINT" s3 ls \
      "s3://$BACKUP_BUCKET/$DEST_PREFIX/" >/dev/null 2>&1; then
      echo "memlawb-backup: verification ls failed for s3://$BACKUP_BUCKET/$DEST_PREFIX/" >&2
      exit 1
    fi

    echo "memlawb-backup: OK -> s3://$BACKUP_BUCKET/$DEST_PREFIX"
  '';

  # Read the sops-decrypted key files and export them, then exec the script.
  # Hoisted to file-level `let` so systemd.services can reference it directly.
  secretWrapper = pkgs.writeShellScript "memlawb-backup-secret-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail
    # /etc/memlawb-backup/credentials is sourced by systemd via EnvironmentFile.
    if [ -r ${toString cfg.accessKeyFile} ]; then
      export GARAGE_ACCESS_KEY="$(cat ${toString cfg.accessKeyFile})"
    fi
    if [ -r ${toString cfg.secretKeyFile} ]; then
      export GARAGE_SECRET_KEY="$(cat ${toString cfg.secretKeyFile})"
    fi
    if [ -z "''${GARAGE_ACCESS_KEY:-}" ] || [ -z "''${GARAGE_SECRET_KEY:-}" ]; then
      echo "memlawb-backup: missing Garage S3 credentials" >&2
      exit 1
    fi
    exec ${backupScript}/bin/memlawb-backup
  '';
in {
  options.services.memlawb-backup = {
    enable = lib.mkEnableOption "Daily backup of the memlawb fs blobstore to Garage S3";

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://10.1.1.120:3900";
      description = "Garage S3 endpoint URL (matches services.backup-to-garage on sentry).";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "garage";
      description = "Garage S3 region.";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "backups";
      description = "Garage S3 bucket (existing cluster backups bucket). Destination is s3://bucket/destPrefix.";
    };

    sourceDir = lib.mkOption {
      type = lib.types.str;
      default = "/persistent/memlawb-data";
      description = "Local fs blobstore to back up (services.memlawb-server.dataDir).";
    };

    destPrefix = lib.mkOption {
      type = lib.types.str;
      default = "memlawb-data";
      description = "S3 key prefix under the bucket (s3://bucket/destPrefix).";
    };

    accessKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = /run/secrets/garage-s3-access-key-id;
      description = "File with Garage S3 access key ID (sops, provisioned on sentry).";
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = /run/secrets/garage-s3-secret-key;
      description = "File with Garage S3 secret key (sops, provisioned on sentry).";
    };

    startAt = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      description = "systemd timer OnCalendar for the daily backup.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User to run as (must read the sops secret files, which are root:root 0440).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      awscli2
      rclone
    ];

    # Non-secret config consumed by the backup script.
    environment.etc."memlawb-backup/credentials" = {
      text = ''
        GARAGE_ENDPOINT=${cfg.endpoint}
        GARAGE_REGION=${cfg.region}
        BACKUP_BUCKET=${cfg.bucket}
        SOURCE_DIR=${cfg.sourceDir}
        DEST_PREFIX=${cfg.destPrefix}
      '';
      mode = "0600";
    };

    systemd.services.memlawb-backup = {
      description = "Backup memlawb fs blobstore to Garage S3";
      after = [
        "network-online.target"
      ];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.user;
        Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin";
        EnvironmentFile = "/etc/memlawb-backup/credentials";
        ExecStart = "${secretWrapper}";
        NoNewPrivileges = true;
        ReadOnlyPaths = [cfg.sourceDir];
      };
    };

    systemd.timers.memlawb-backup = {
      description = "Daily memlawb Garage backup timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;
        Unit = "memlawb-backup.service";
      };
    };
  };
}
