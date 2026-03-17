# Flake Lock Sync Module
# Automatically syncs flake.lock from NFS source to local /etc/nixos
# Prevents drift between Zephyr (source) and remote hosts
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.flake-lock-sync;
  currentHost = config.networking.hostName or "unknown";
  isZephyr = currentHost == "zephyr";
in {
  options.services.flake-lock-sync = {
    enable = lib.mkEnableOption "flake.lock sync from NFS mount";

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
    # Only run on remote hosts (not Zephyr, which is the source)
    assertions = [
      {
        assertion = isZephyr -> !cfg.enable;
        message = "flake-lock-sync should not be enabled on Zephyr (it is the source)";
      }
    ];

    # Sync script
    environment.etc."nixos/scripts/sync-flake-lock.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        SOURCE="${cfg.sourcePath}"
        TARGET="${cfg.targetPath}"
        STATE_FILE="/var/lib/flake-lock-sync/last-sync"

        # Only proceed if source exists (NFS might be unavailable)
        if [ ! -f "$SOURCE" ]; then
          echo "flake-lock-sync: Source not available ($SOURCE)"
          exit 0
        fi

        # Calculate checksums
        SOURCE_SUM=$(md5sum "$SOURCE" | cut -d' ' -f1)
        TARGET_SUM=$(md5sum "$TARGET" 2>/dev/null | cut -d' ' -f1 || echo "none")

        # Skip if identical
        if [ "$SOURCE_SUM" = "$TARGET_SUM" ]; then
          exit 0
        fi

        # Create backup before overwriting
        if [ -f "$TARGET" ]; then
          cp "$TARGET" "''${TARGET}.backup"
        fi

        # Sync the file
        cp "$SOURCE" "$TARGET"

        # Record state
        mkdir -p "$(dirname "$STATE_FILE")"
        echo "$SOURCE_SUM" > "$STATE_FILE"

        logger -t flake-lock-sync "Synced flake.lock from NFS (checksum: $SOURCE_SUM)"
        echo "flake-lock-sync: Synced flake.lock from NFS"
      '';
    };

    # Systemd service for on-demand sync
    systemd.services.flake-lock-sync = {
      description = "Sync flake.lock from NFS mount";
      wantedBy = ["multi-user.target"];
      after = ["nixos-shared.mount" "network-online.target"];
      requires = ["nixos-shared.mount"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/nixos/scripts/sync-flake-lock.sh";
        RemainAfterExit = false;
      };

      # Don't start on Zephyr (it's the source)
      stopIfChanged = false;
    } // lib.optionalAttrs isZephyr {enable = false;};

    # Systemd timer for periodic sync
    systemd.timers.flake-lock-sync = {
      description = "Periodic flake.lock sync from NFS";
      wantedBy = ["timers.target"];
      partOf = ["flake-lock-sync.service"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "1s";
      };
    } // lib.optionalAttrs isZephyr {enable = false;};

    # State directory for sync tracking
    systemd.tmpfiles.rules = [
      "d /var/lib/flake-lock-sync 0755 root root -"
    ];
  };
}
