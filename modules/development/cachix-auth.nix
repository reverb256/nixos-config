{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.cachix-auth;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.cachix-auth = {
    enable = mkEnableOption "Cachix authentication via agenix secret";

    tokenFile = mkOption {
      type = types.path;
      default = "/run/agenix/cachix-token";
      description = "Path to the Cachix authentication token file (agenix secret)";
    };
  };

  config = mkIf cfg.enable {
    # One-shot service that authenticates Cachix on boot
    systemd.services.cachix-auth = {
      description = "Configure Cachix authentication token";
      wantedBy = ["multi-user.target"];
      after = ["nix-daemon.service"];
      wants = ["nix-daemon.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "j_kro";
        StateDirectory = "cachix";
      };
      script = ''
        if [ -f "${cfg.tokenFile}" ]; then
          TOKEN=$(cat "${cfg.tokenFile}")
          ${lib.getExe pkgs.cachix} authtoken "$TOKEN" || true
          echo "cachix-auth: authenticated successfully"
        else
          echo "cachix-auth: token file not found at ${cfg.tokenFile}"
          exit 1
        fi
      '';
    };

    # Ensure cachix is available in system packages
    environment.systemPackages = with pkgs; [cachix];
  };
}
