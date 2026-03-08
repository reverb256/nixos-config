# Cluster Storage Module
# Ensures all configured storage is properly mounted across cluster nodes
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf mkDefault;

  cfg = config.services.cluster-storage;
in {
  options.services.cluster-storage = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Ensure cluster storage mounts are active on boot";
    };
  };

  config = mkIf cfg.enable {
    # Systemd service to verify all storage is mounted after boot
    systemd.services.ensure-cluster-storage = {
      description = "Ensure all cluster storage mounts are active";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target" "remote-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "ensure-cluster-storage" ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "[cluster-storage] Verifying all configured mounts are active..."

          # Try to mount any filesystems that aren't mounted
          # This handles cases where mounts failed during boot due to timing issues
          mount -a 2>/dev/null || true

          # Check node-specific critical mounts
          case "${config.networking.hostName}" in
            nexus)
              # Verify /data subvolumes are mounted
              for mount in /data/worn /data/home /data/shared /data/backups /data/media /var/lib/containers; do
                if mountpoint -q "$mount"; then
                  echo "[cluster-storage] ✓ $mount is active"
                else
                  echo "[cluster-storage] ✗ $mount is NOT mounted, attempting to mount..."
                  mount "$mount" 2>/dev/null || echo "[cluster-storage] WARNING: Failed to mount $mount"
                fi
              done
              ;;
            sentry)
              # Verify /storage is mounted
              if mountpoint -q /storage; then
                echo "[cluster-storage] ✓ /storage is active"
              else
                echo "[cluster-storage] ✗ /storage is NOT mounted, attempting to mount..."
                mount /storage 2>/dev/null || echo "[cluster-storage] WARNING: Failed to mount /storage"
              fi
              ;;
            zephyr)
              # Verify /data is mounted
              if mountpoint -q /data; then
                echo "[cluster-storage] ✓ /data is active"
              else
                echo "[cluster-storage] ✗ /data is NOT mounted, attempting to mount..."
                mount /data 2>/dev/null || echo "[cluster-storage] WARNING: Failed to mount /data"
              fi
              ;;
            forge)
              # No special storage checks for forge
              echo "[cluster-storage] ✓ No special storage mounts for forge"
              ;;
          esac

          echo "[cluster-storage] Storage verification complete"
        '';
      };
    };

    # Run the verification on boot
    systemd.timers.ensure-cluster-storage = {
      description = "Periodically verify cluster storage mounts";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";  # Run 30s after boot
        OnUnitActiveSec = "5min";  # Then every 5 minutes
      };
    };
  };
}
