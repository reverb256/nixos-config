{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.services.cluster-watchdog;
in {
  options.services.cluster-watchdog = {
    enable = mkEnableOption "Cluster deployment watchdog timer";
    interval = mkOption {
      type = types.str;
      default = "5min";
      description = "How often to run the cluster health check";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.cluster-watchdog = {
      description = "Cluster deployment status watchdog";
      script = ''
        exec ${pkgs.bash}/bin/bash /etc/nixos/scripts/cluster-watchdog.sh
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Nice = 19;
      };
    };

    systemd.timers.cluster-watchdog = {
      description = "Periodic cluster deployment status check";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "30s";
      };
    };
  };
}
