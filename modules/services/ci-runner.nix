{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.ci-runner;
  runnerHome = "/var/lib/${cfg.user}";
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

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Automatically start the runner service.
        NOTE: The runner must be manually configured first by running:
        sudo /etc/nixos/scripts/ci/setup-runner.sh owner/repo

        Set to true only after completing the setup script.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.groups.${cfg.user} = {};

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      # Security: wheel removed - CI runner must not have sudo privileges
      description = "GitHub Actions runner";
      home = runnerHome;
      createHome = true;
    };

    # Only enable the service if the runner has been configured
    systemd.services.github-actions-runner = lib.mkIf (cfg.autoStart) {
      description = "GitHub Actions Self-Hosted Runner";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = runnerHome;
        ExecStart = "${runnerHome}/run.sh";
        Restart = "always";
        RestartSec = "10s";
        # Fail gracefully if runner not configured yet
        ConditionPathExists = "${runnerHome}/run.sh";
      };

      wantedBy = ["multi-user.target"];
    };
  };
}
