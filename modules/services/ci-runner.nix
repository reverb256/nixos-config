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
      description = "GitHub Actions runner";
      home = runnerHome;
      createHome = true;
    };

    systemd.services.github-actions-runner = lib.mkIf cfg.autoStart {
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
        ConditionPathExists = "${runnerHome}/run.sh";

        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ runnerHome ];
      };

      wantedBy = ["multi-user.target"];
    };
  };
}
