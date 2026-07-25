{
  config,
  lib,
  pkgs,
  ...
}: let
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

    clusterStatePath = mkOption {
      type = types.path;
      default = "/etc/nixos/cluster-state.nix";
      description = ''
        Path to cluster-state.nix — source-of-truth for static STATUS.md
        sections (Cluster Health Overview, GPU Resources, Migration
        Progress, Known Issues, Notes). The regen script reads it via
        `nix eval --json --file <path>` and pipes rows through ``jq``.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.status-update = {
      description = "Update STATUS.md with current cluster state";
      after = ["network.target" "kubernetes.target"];
      wants = ["network-online.target"];
      # Pass source-of-truth path so the regen script can find it without
      # hard-coding /etc/nixos/cluster-state.nix. env CLUSTER_STATE_NIX
      # → override; default in script still applies if neither set.
      environment.CLUSTER_STATE_NIX = toString cfg.clusterStatePath;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.scriptPath}";
        User = "root";
        Group = "root";
        WorkingDirectory = "/etc/nixos";
        # Only run on cluster nodes where the full toolchain is present.
        ConditionPathExists = [
          "/run/current-system/sw/bin/kubectl"
          "/run/current-system/sw/bin/nix"
          "/run/current-system/sw/bin/jq"
          "!/etc/nixos/STATUS.md.lock"
        ];
      };
    };

    systemd.timers.status-update = {
      description = "Timer for STATUS.md auto-update";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "1min";
        Persistent = true;
      };
    };

    # Ensure the script exists and is executable
    systemd.tmpfiles.rules = [
      "Z ${cfg.scriptPath} 0755 root root -"
    ];
  };
}
