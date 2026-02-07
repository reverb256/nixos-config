{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.backup;
in {
  options.services.backup = {
    enable = mkEnableOption "BorgBackup System";
    paths = mkOption {
      type = types.listOf types.str;
      default = [
        "/etc/nixos"
        "/var/lib/openclaw"
        "/home/j_kro/.local/share"
      ];
      description = "Paths to backup";
    };
    repository = mkOption {
      type = types.str;
      default = "/mnt/backup";
      description = "Borg repository path";
    };
    encryptionRepo = mkOption {
      type = types.str;
      default = "/run/agenix/backup-encryption-key";
      description = "Path to encryption key (agenix)";
    };
    # SECURITY NOTE: backup-encryption-key.age must be created before enabling backup service
    # Run: openssl rand -base64 32 | nix-shell -p age --run 'age -r <AGE_PUBLIC_KEY> -o /etc/nixos/secrets/backup-encryption-key.age /dev/stdin'
    # Then add backup-encryption-key entry to secrets/age-secrets.nix
    excludePatterns = mkOption {
      type = types.listOf types.str;
      default = [
        "*.pyc"
        "*.so"
        "*.tmp"
        "/var/lib/openclaw/.cache"
        "/home/j_kro/.cache"
      ];
      description = "Patterns to exclude from backup";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.borgmatic];

    # Create backup directories
    systemd.tmpfiles.rules = [
      "d /var/lib/borg 0750 root root - -"
      "d /var/log/borg 0750 root root - -"
    ];

    # Borgmatic configuration
    environment.etc."borgmatic/config.yaml".text = ''
      location:
        source_directories:
          ${builtins.concatStringsSep "\n          " cfg.paths}
        exclude_patterns:
          ${builtins.concatStringsSep "\n          " cfg.excludePatterns}
        repositories:
          - ${cfg.repository}
        one_file_system: true
        skip_files:
          - var/lib/docker
          - var/lib/containers

      storage:
        encryption_passcommand: "cat ${cfg.encryptionRepo}"
        compression: lz4
        archive_name_format: '{hostname}-{now:%Y-%m-%d_%H:%M:%S}'

      retention:
        keep_daily: 7
        keep_weekly: 4
        keep_monthly: 12
        keep_yearly: 5

      hooks:
        before_backup:
          - echo "Starting backup..."
        after_backup:
          - echo "Backup completed"
    '';

    # Daily backup timer
    systemd.timers.borgmatic = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00"; # Daily at 3 AM
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.services.borgmatic = {
      description = "BorgBackup Automated Backup";
      after = ["network.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.borgmatic}/bin/borgmatic --verbosity 1";
        ReadWritePaths = ["/var/lib/borg" "/var/log/borg"];
      };
    };
  };
}
