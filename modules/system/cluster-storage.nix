{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf;

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
    systemd.services.ensure-cluster-storage = {
      description = "Ensure all cluster storage mounts are active";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target" "remote-fs.target"];
      environment.PATH = lib.mkForce (lib.makeBinPath [pkgs.util-linux pkgs.coreutils]);
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "ensure-cluster-storage" ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "[cluster-storage] Verifying all configured mounts are active..."

          mount -a 2>/dev/null || true

          case "${config.networking.hostName}" in
            nexus)
                if mountpoint -q "$mount"; then
                  echo "[cluster-storage] ✓ $mount is active"
                else
                  echo "[cluster-storage] ✗ $mount is NOT mounted, attempting to mount..."
                  mount "$mount" 2>/dev/null || echo "[cluster-storage] WARNING: Failed to mount $mount"
                fi
              done
              ;;
            sentry)
              if mountpoint -q /storage; then
                echo "[cluster-storage] ✓ /storage is active"
              else
                echo "[cluster-storage] ✗ /storage is NOT mounted, attempting to mount..."
                mount /storage 2>/dev/null || echo "[cluster-storage] WARNING: Failed to mount /storage"
              fi
              ;;
            zephyr)
              if mountpoint -q /data; then
                echo "[cluster-storage] ✓ /data is active"
              else
                echo "[cluster-storage] ✗ /data is NOT mounted, attempting to mount..."
                mount /data 2>/dev/null || echo "[cluster-storage] WARNING: Failed to mount /data"
              fi
              ;;
            forge)
              echo "[cluster-storage] ✓ No special storage mounts for forge"
              ;;
          esac

          echo "[cluster-storage] Storage verification complete"
        '';
      };
    };

    systemd.timers.ensure-cluster-storage = {
      description = "Periodically verify cluster storage mounts";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
