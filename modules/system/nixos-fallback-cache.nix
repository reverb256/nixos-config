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
    systemd.tmpfiles.rules = [
      "d ${cfg.cachePath} 0755 root root -"
    ];

    environment.etc."nixos/scripts/sync-nixos-cache.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        SOURCE="${cfg.sourcePath}"
        CACHE="${cfg.cachePath}"

        if [ ! -d "$SOURCE" ]; then
          echo "nixos-fallback-cache: NFS source not available, keeping existing cache"
          exit 0
        fi

        rsync -a --delete "$SOURCE/" "$CACHE/" 2>/dev/null || true

        echo "$(date -Iseconds)" > "$CACHE/.last-sync"

        logger -t nixos-fallback-cache "Synced config from NFS to local cache"
      '';
    };

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

    environment.etc."nixos/scripts/nixos-rebuild-wrapper.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash

        set -euo pipefail

        SOURCE="${cfg.sourcePath}"
        CACHE="${cfg.cachePath}"
        FLAKE_DIR="\${_FLAKE_DIR: -/etc/nixos}"

        if [ -d "$SOURCE" ] && [ -f "$SOURCE/flake.nix" ]; then
          exec sudo nixos-rebuild "$@" --flake "$SOURCE#\$(hostname -s)"
        elif [ -d "$CACHE" ] && [ -f "$CACHE/flake.nix" ]; then
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
  };
}
