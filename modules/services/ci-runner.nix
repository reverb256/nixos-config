{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.ci-runner;
  runnerHome = "/var/lib/${cfg.user}";
  runnerPackage = pkgs.github-runners.${cfg.repo}.nexus or pkgs.github-runner;
in {
  options.services.ci-runner = {
    enable = mkEnableOption "GitHub Actions self-hosted runner";

    user = mkOption {
      type = types.str;
      default = "runner";
      description = "User to run the runner as";
    };

    repo = mkOption {
      type = types.str;
      example = "username/nixos-config";
      description = "GitHub repository (owner/repo)";
    };

    tokenFile = mkOption {
      type = types.str;
      description = "Path to file containing GitHub runner token";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Automatically start the runner service.
        NOTE: The runner must be configured first by placing the token in tokenFile.
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
      wantedBy = [];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = runnerHome;
        ExecStart = "${pkgs.github-runner}/bin/runsvc.sh";
        Restart = "always";
        RestartSec = "10s";
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [runnerHome];
      };
    };

    # Setup script to register the runner
    systemd.services.github-actions-runner-setup = {
      description = "GitHub Actions Runner Setup";
      before = ["github-actions-runner.service"];
      requiredBy = ["github-actions-runner.service"];
      script = ''
        if [ ! -f "${runnerHome}/.runner" ]; then
          ${pkgs.github-runner}/bin/config.sh \
            --url "https://github.com/${cfg.repo}" \
            --token "$(cat ${cfg.tokenFile})" \
            --name "${config.networking.hostName}-runner" \
            --labels "nixos" \
            --unattended
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        WorkingDirectory = runnerHome;
      };
    };
  };
}
