{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.security.kubernetes;
in {
  options.security.kubernetes = {
    enable = mkEnableOption "Kubernetes security tools";

    enableFalco = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Falco for runtime threat detection (requires manual configuration)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs;
      [
        kubectl
      ]
      ++ lib.optional cfg.enableFalco falcoctl;
  };
}
