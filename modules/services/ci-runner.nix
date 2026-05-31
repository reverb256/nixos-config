{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.ci-runner;
  hostName = config.networking.hostName;
in {
  imports = [
    "${toString pkgs.path}/nixos/modules/services/continuous-integration/github-runners.nix"
  ];

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
    services.github-runners."${hostName}" = {
      enable = true;
      url = "https://github.com/${cfg.repo}";
      tokenFile = cfg.tokenFile;
      name = "${hostName}-runner";
      extraLabels = [ "nixos" ];
      replace = true;
      nodeRuntimes = [ "node24" ];
      serviceOverrides = lib.mkIf cfg.autoStart {
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
