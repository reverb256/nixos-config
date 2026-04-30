{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nfs-state-sync;
in {
  options.services.nfs-state-sync = {
    enable = lib.mkEnableOption "Sync hermes/pi state from primary to secondary NFS server";

    sourceHost = lib.mkOption {
      type = lib.types.str;
      default = "zephyr";
      description = "Primary NFS server to sync from";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["/data/hermes" "/data/pi"];
      description = "Paths to sync via rsync";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "Systemd timer interval";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.timers.nfs-state-sync = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };

    systemd.services.nfs-state-sync = {
      description = "Sync NFS state from ${cfg.sourceHost}";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      path = with pkgs; [rsync openssh];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        # Don't spam logs or fail the timer if source is unreachable
        ExecStart = pkgs.writeShellScript "nfs-state-sync" ''
          ${lib.concatMapStringsSep "\n" (path: ''
              echo "[nfs-state-sync] Syncing ${path} from ${cfg.sourceHost}..."
              rsync -az --delete \
                --timeout=30 \
                -e "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new" \
                ${cfg.sourceHost}:${path}/ ${path}/ 2>&1 || {
                echo "[nfs-state-sync] Failed to sync ${path} (source may be down)"
              }
            '')
            cfg.paths}
        '';
      };
    };
  };
}
