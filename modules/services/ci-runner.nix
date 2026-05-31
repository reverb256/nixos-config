{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.ci-runner;
in {
  # Import the nixpkgs github-runners module (must be top-level)
  imports = [
    "${toString pkgs.path}/nixos/modules/services/continuous-integration/github-runners.nix"
  ];

  options.services.ci-runner = {
    enable = mkEnableOption "GitHub Actions self-hosted runner";
    repo = mkOption {
      type = types.str;
      example = "username/nixos-config";
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
    # Configure a runner named after the host
    services.github-runners."${config.networking.hostName}" = {
      enable = true;
      url = "https://github.com/${cfg.repo}";
      tokenFile = cfg.tokenFile;
      name = "${config.networking.hostName}-runner";
      extraLabels = [ "nixos" ];
      replace = true;

      # Auto-start if requested
      serviceOverrides = mkIf cfg.autoStart {
        wantedBy = [ "multi-user.target" ];
      };

      # Apply nodeRuntimes override
      package = pkgs.github-runner.override {
        nodeRuntimes = [ "node24" ];
      };
    };
  };
}
