# NixOS Configuration Fallback Cache
# Provides local fallback when NFS mount is unavailable
# Enables graceful degradation during network outages
{
  lib,
  config,
  ...
}: let
  cfg = config.services.nixos-fallback-cache;
  currentHost = config.networking.hostName or "unknown";
  isRemote = currentHost != "zephyr";
in {
  options.services.nixos-fallback-cache = {
    enable = lib.mkEnableOption "NixOS configuration fallback cache for remote hosts";

    cachePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/nixos-config";
      description = "Local cache directory for NixOS configuration";
    };

    sourcePath = lib.mkOption {
      type = lib.types.str;
      default = "/run/nixos-shared";
      description = "NFS mount path to cache from";
    };

    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "How often to update the local cache";
    };
  };

  config = lib.mkIf (cfg.enable && isRemote) {
    # Create cache directory
    systemd.tmpfiles.rules = [
      "d ${cfg.cachePath} 0755 root root -"
    ];

    # Sync script - copies NFS config to local cache
    environment.etc."nixos/scripts/sync-nixos-cache.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        SOURCE="${cfg.sourcePath}"
        CACHE="${cfg.cachePath}"

        # Only sync if source is available
        if [ ! -d "$SOURCE" ]; then
          echo "nixos-fallback-cache: NFS source not available, keeping existing cache"
          exit 0
        fi

        # Use rsync for efficient incremental updates
        rsync -a --delete "$SOURCE/" "$CACHE/" 2>/dev/null || true

        # Record sync time
        echo "$(date -Iseconds)" > "$CACHE/.last-sync"

        logger -t nixos-fallback-cache "Synced config from NFS to local cache"
      '';
    };

    # Sync service - runs on boot and periodically
    systemd.services.nixos-fallback-cache-sync = {
      description = "Sync NixOS configuration from NFS to local cache";
      wantedBy = ["multi-user.target"];
      after = ["nixos-shared.mount" "network-online.target"];
      wants = ["nixos-shared.mount"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/nixos/scripts/sync-nixos-cache.sh";
        RemainAfterExit = true;
      };
    };

    # Periodic sync via timer
    systemd.timers.nixos-fallback-cache-sync = {
      description = "Periodic NixOS config cache sync from NFS";
      wantedBy = ["timers.target"];
      partOf = ["nixos-fallback-cache-sync.service"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.syncInterval;
        AccuracySec = "5min";
      };
    };

    # Wrapper script for nixos-rebuild that uses cache when NFS unavailable
    environment.etc."nixos/scripts/nixos-rebuild-wrapper.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        # Graceful nixos-rebuild - falls back to cache when NFS unavailable

        set -euo pipefail

        SOURCE="${cfg.sourcePath}"
        CACHE="${cfg.cachePath}"
        FLAKE_DIR="\${_FLAKE_DIR: -/etc/nixos}"

        # Prefer NFS, fall back to cache
        if [ -d "$SOURCE" ] && [ -f "$SOURCE/flake.nix" ]; then
          # NFS available - use it
          exec sudo nixos-rebuild "$@" --flake "$SOURCE#\$(hostname -s)"
        elif [ -d "$CACHE" ] && [ -f "$CACHE/flake.nix" ]; then
          # NFS unavailable - use cache
          echo "⚠ NFS unavailable, using local cache (last sync: $(cat "$CACHE/.last-sync" 2>/dev/null || echo 'unknown'))"
          exec sudo nixos-rebuild "$@" --flake "$CACHE#\$(hostname -s)"
        else
          echo "❌ Error: Neither NFS mount nor local cache available"
          echo "   NFS: $SOURCE"
          echo "   Cache: $CACHE"
          exit 1
        fi
      '';
    };

    # Optional: Create a symlink to make cache the default flake location
    # This allows builds to work even when NFS is down
    # system.stateVersion would need to be managed carefully here
  };
}
