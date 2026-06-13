{
  config,
  lib,
  pkgs,
  ...
}: {
  options.services.btrfs-quota = {
    enable = lib.mkEnableOption "BTRFS subvolume quota tracking for per-subvolume storage accounting";

    scanInterval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "How often to rescan qgroups (systemd calendar/timer format)";
    };
  };

  config = lib.mkIf config.services.btrfs-quota.enable {
    systemd.services.btrfs-quota-enable = {
      description = "Enable BTRFS subvolume quota tracking";
      after = ["local-fs.target"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.btrfs-progs];
      script = ''
        for mount in $(findmnt -t btrfs -n -o TARGET 2>/dev/null | sort -u); do
          if ! btrfs qgroup show "$mount" &>/dev/null; then
            btrfs quota enable "$mount"
            echo "Quotas enabled: $mount"
          fi
        done
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    systemd.services.btrfs-qgroup-rescan = {
      description = "BTRFS qgroup rescan for accurate subvolume usage";
      path = [pkgs.btrfs-progs];
      script = ''
        for mount in $(findmnt -t btrfs -n -o TARGET 2>/dev/null | sort -u); do
          if btrfs qgroup show "$mount" &>/dev/null; then
            btrfs quota rescan "$mount" 2>/dev/null || true
          fi
        done
      '';
      serviceConfig = {
        Type = "oneshot";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.btrfs-qgroup-rescan = {
      wantedBy = ["timers.target"];
      partOf = ["btrfs-qgroup-rescan.service"];
      timerConfig = {
        OnCalendar = config.services.btrfs-quota.scanInterval;
        Persistent = true;
      };
    };

    environment.systemPackages = [pkgs.btrfs-progs];
  };
}
