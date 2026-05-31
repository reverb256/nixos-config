{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.ci-runner;
in {
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
    # Import the nixpkgs github-runners module
    imports = [
      "${toString pkgs.path}/nixos/modules/services/continuous-integration/github-runners.nix"
    ];

    # Configure a runner named after the host
    services.github-runners."${config.networking.hostName}" = {
      enable = cfg.enable;
      url = "https://github.com/${cfg.repo}";
      tokenFile = cfg.tokenFile;
      name = "${config.networking.hostName}-runner";
      extraLabels = [ "nixos" ];
      replace = true;

      # Only use node24 to avoid building nodejs_20 from source
      nodeRuntimes = [ "node24" ];

      # Auto-start if requested
      serviceOverrides = lib.mkIf cfg.autoStart {
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
