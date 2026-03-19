# Kubernetes Security Module
# Security tools for Kubernetes runtime monitoring

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
      default = false;  # Disabled by default - requires external setup
      description = "Enable Falco for runtime threat detection (requires manual configuration)";
    };
  };

  config = mkIf cfg.enable {
    # Install security tools
    environment.systemPackages = with pkgs; [
      kubectl   # For audit scripts and management
    ] ++ lib.optional cfg.enableFalco falcoctl;
  };
}
