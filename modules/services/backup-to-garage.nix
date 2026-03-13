# backup-to-garage.nix - Automated backup service to Garage S3
# Systemd timer for daily backups to Garage cluster

{ config, lib, pkgs, ... }:

let
  cfg = config.services.backup-to-garage;
  backupScript = pkgs.writeShellScriptBin "backup-to-garage" (builtins.readFile ../../../scripts/backup-to-garage.sh);
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
        ExecStart = "${backupScript}/bin/backup-to-garage --auto";
        EnvironmentFile = lib.mkIf (cfg.secretKeyFile != null) (
          "/etc/backup-to-garage/credentials " +
          "-e GARAGE_SECRET_KEY=$(cat ${cfg.secretKeyFile})"
        );
        # Fallback if no secret key file
        Environment = lib.mkIf (cfg.secretKeyFile == null) [
          "GARAGE_SECRET_KEY=PLEASE_SET_SECRET_KEY_FILE"
        ];
        User = "root";
        Group = "root";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadOnlyPaths = lib.mkMerge (map (p: [ p p ]) cfg.backupPaths);
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
