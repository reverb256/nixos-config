# Crash Watchdog Service
# Tracks system crashes and logs diagnostic information
{
  config,
  lib,
  ...
}: let
  # inherit (config.lib) systemd-helpers;
  # TEMPORARILY DISABLED: Helper libraries being fixed (2026-03-23)
in {
  options.services.crash-watchdog = {
    enable = lib.mkEnableOption "Crash detection and logging service";
  };

  config = lib.mkIf config.services.crash-watchdog.enable {
    # Create log directory for crash information
    systemd.tmpfiles.rules = [
      "d /var/log/crash-watchdog 0755 root root -"
    ];

    # Service that runs after boot to detect and log crashes
    systemd.services.crash-watchdog = {
      description = "Detect and log system crashes";
      after = ["network.target" "local-fs.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig.Type = "oneshot";

      script = ''
        #!/bin/sh
        set -euo pipefail

        CRASH_LOG="/var/log/crash-watchdog/crashes.log"
        STATE_FILE="/var/log/crash-watchdog/last_boot_id"

        # Get current boot ID
        CURRENT_BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)

        # Create state file if it doesn't exist
        if [ ! -f "$STATE_FILE" ]; then
          echo "$CURRENT_BOOT_ID" > "$STATE_FILE"
          echo "$(date -Iseconds) - Initial boot: $CURRENT_BOOT_ID" >> "$CRASH_LOG"
          exit 0
        fi

        # Read last boot ID
        LAST_BOOT_ID=$(cat "$STATE_FILE")

        # Check if this is a new boot (potential crash)
        if [ "$CURRENT_BOOT_ID" != "$LAST_BOOT_ID" ]; then
          # Log the crash with system state
          {
            echo "=========================================="
            echo "CRASH DETECTED: $(date -Iseconds)"
            echo "Previous boot ID: $LAST_BOOT_ID"
            echo "Current boot ID: $CURRENT_BOOT_ID"
            echo ""
            echo "--- UPTIME ---"
            uptime -s || echo "Unable to determine uptime"
            echo ""
            echo "--- MEMORY (pre-crash estimate) ---"
            journalctl -b -1 --no-pager | grep -i "meminfo\|memory\|oom" | tail -20 || echo "No memory logs found"
            echo ""
            echo "--- GPU STATUS (if available) ---"
            journalctl -b -1 --no-pager | grep -i "nvidia\|gpu" | tail -10 || echo "No GPU logs found"
            echo ""
            echo "--- LAST 50 LOG LINES ---"
            journalctl -b -1 --no-pager | tail -50
            echo "=========================================="
            echo ""
          } >> "$CRASH_LOG"

          # Update state file
          echo "$CURRENT_BOOT_ID" > "$STATE_FILE"
        fi
      '';

      # Security hardening
      serviceConfig = {
        RemainAfterExit = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = "/";
        ReadWritePaths = "/var/log/crash-watchdog";
      };
    };
  };
}
