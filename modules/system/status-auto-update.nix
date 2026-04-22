{ config, lib, pkgs, ... }:

let
  cfg = config.services.status-auto-update;
  inherit (lib) mkEnableOption mkIf mkOption types;
in {
  options.services.status-auto-update = {
    enable = mkEnableOption "STATUS.md auto-update service";

    interval = mkOption {
      type = types.str;
      default = "hourly";
      description = "How often to update STATUS.md (systemd timer format)";
    };

    statusPath = mkOption {
      type = types.path;
      default = "/etc/nixos/STATUS.md";
      description = "Path to STATUS.md file";
    };

    scriptPath = mkOption {
      type = types.path;
      default = "/etc/nixos/scripts/update-status.sh";
      description = "Path to update script";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.status-update = {
      description = "Update STATUS.md with current cluster state";
      after = [ "network.target" "kubernetes.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [ kubectl kubernetes-helm jq gawk ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.scriptPath}";
        User = "root";
        Group = "root";
        WorkingDirectory = "/etc/nixos";
        ConditionPathExists = [
          "/run/current-system/sw/bin/kubectl"
          "!/etc/nixos/STATUS.md.lock"
        ];
      };
    };

    systemd.timers.status-update = {
      description = "Timer for STATUS.md auto-update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "1min";
        Persistent = true;
      };
    };

    systemd.tmpfiles.rules = [
      "Z ${cfg.scriptPath} 0755 root root -"
    ];
  };
}
