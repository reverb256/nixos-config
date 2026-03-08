{ config, lib, ... }:

with lib;
let
  cfg = config.services.ci-runner;
in {
  options.services.ci-runner = {
    enable = mkEnableOption "GitHub Actions self-hosted runner";

    user = mkOption {
      type = types.str;
      default = "actions-runner";
      description = "User to run the runner as";
    };

    repo = mkOption {
      type = types.str;
      example = "username/nixos-config";
      description = "GitHub repository (owner/repo)";
    };
  };

  config = mkIf cfg.enable {
    users.groups.${cfg.user} = {};

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      # Security: wheel removed - CI runner must not have sudo privileges
      description = "GitHub Actions runner";
    };

    systemd.services.github-actions-runner = {
      description = "GitHub Actions Self-Hosted Runner";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = "/var/lib/${cfg.user}";
        ExecStart = "/var/lib/${cfg.user}/run.sh";
        Restart = "always";
        RestartSec = "10s";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
