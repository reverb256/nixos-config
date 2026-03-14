# Nix Cache Services Wrapper
# Provides unified interface for Harmonia binary cache
# Auto-build is handled by separate auto-build.nix module
{
  config,
  lib,
  ...
}: let
  cfg = config.services.nix-cache;
in {
  options.services.nix-cache = {
    enable = lib.mkEnableOption "Nix cache services (Harmonia binary cache)";
  };

  config = lib.mkIf cfg.enable {
    # Enable Harmonia binary cache
    services.nix-cache.harmonia = {
      enable = true;
    };
  };
}
