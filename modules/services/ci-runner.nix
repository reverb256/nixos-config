{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.ci-runner;
  runner = pkgs.github-runner.override { nodeRuntimes = [ "node24" ]; };
  runnerHome = "/var/lib/github-runner";
in {
  options.services.ci-runner = {
    enable = mkEnableOption "GitHub Actions self-hosted runner";
    repo = mkOption {
      type = types.str;
      description = "GitHub repository (owner/repo)";
    };
    tokenFile = mkOption {
      type = types.path;
      description = "Path to file containing GitHub runner token";
    };
    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically start the runner service";
    };
  };

  config = mkIf cfg.enable {
    users.users.github-runner = {
      isSystemUser = true;
      group = "github-runner";
      home = runnerHome;
      createHome = true;
    };
    users.groups.github-runner = {};

    systemd.services.github-runner-setup = {
      description = "GitHub Actions Runner Setup";
      before = [ "github-runner.service" ];
      requiredBy = [ "github-runner.service" ];
      script = ''
        if [ ! -f "${runnerHome}/.runner" ]; then
          ${runner}/bin/config.sh \
            --url "https://github.com/${cfg.repo}" \
            --token "$(cat ${cfg.tokenFile})" \
            --name "${config.networking.hostName}" \
            --labels "nixos" \
            --unattended
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "github-runner";
        WorkingDirectory = runnerHome;
      };
    };

    systemd.services.github-runner = mkIf cfg.autoStart {
      description = "GitHub Actions Self-Hosted Runner";
      after = [ "network-online.target" "github-runner-setup.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "github-runner";
        WorkingDirectory = runnerHome;
        ExecStart = "${runner}/bin/Runner.Listener run --startuptype service";
        Restart = "always";
        RestartSec = "10s";
      };
    };
  };
}
