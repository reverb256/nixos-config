{
  lib,
  config,
  ...
}: let
  currentHost = config.networking.hostName or "unknown";
  isZephyr = currentHost == "zephyr";
  cfg = {
    enable = !isZephyr;
    interval = "15min";
    sourcePath = "/run/nixos-shared/flake.lock";
    targetPath = "/etc/nixos/flake.lock";
  };
in {
  options.services.flake-lock-sync = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = !isZephyr;
      description = "Enable flake.lock sync from NFS mount (auto-disabled on Zephyr)";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "Systemd timer interval for automatic sync";
    };

    sourcePath = lib.mkOption {
      type = lib.types.str;
      default = "/run/nixos-shared/flake.lock";
      description = "Source flake.lock path (NFS mount)";
    };

    targetPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/flake.lock";
      description = "Target flake.lock path (local copy)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."nixos/scripts/sync-flake-lock.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        SOURCE="${cfg.sourcePath}"
        TARGET="${cfg.targetPath}"
        STATE_FILE="/var/lib/flake-lock-sync/last-sync"

        if [ ! -f "$SOURCE" ]; then
          echo "flake-lock-sync: Source not available ($SOURCE)"
          exit 0
        fi

        SOURCE_SUM=$(md5sum "$SOURCE" | cut -d' ' -f1)
        TARGET_SUM=$(md5sum "$TARGET" 2>/dev/null | cut -d' ' -f1 || echo "none")

        if [ "$SOURCE_SUM" = "$TARGET_SUM" ]; then
          exit 0
        fi

        if [ -f "$TARGET" ]; then
          cp "$TARGET" "''${TARGET}.backup"
        fi

        cp "$SOURCE" "$TARGET"

        mkdir -p "$(dirname "$STATE_FILE")"
        echo "$SOURCE_SUM" > "$STATE_FILE"

        logger -t flake-lock-sync "Synced flake.lock from NFS (checksum: $SOURCE_SUM)"
        echo "flake-lock-sync: Synced flake.lock from NFS"
      '';
    };

    systemd.services.flake-lock-sync = {
      description = "Sync flake.lock from NFS mount";
      wantedBy = ["multi-user.target"];
      after = [
        "nixos-shared.mount"
        "network-online.target"
      ];
      wants = [
        "nixos-shared.mount"
        "network-online.target"
      ];
      requires = ["nixos-shared.mount"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/nixos/scripts/sync-flake-lock.sh";
        RemainAfterExit = false;
      };
    };

    systemd.timers.flake-lock-sync = {
      description = "Periodic flake.lock sync from NFS";
      wantedBy = ["timers.target"];
      partOf = ["flake-lock-sync.service"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "1s";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/flake-lock-sync 0755 root root -"
    ];
  };
}
