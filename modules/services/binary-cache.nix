# Deprecated: services.nix-cache replaces this module.
# The old option tree is preserved so hosts with `services.binary-cache.enable = true`
# get a clear deprecation warning instead of an eval error.
{config, lib, ...}: let
  inherit (lib) mkEnableOption mkIf;
in {
  options.services.binary-cache = {
    enable = mkEnableOption "Nix binary cache server (deprecated - use services.nix-cache)";
  };

  config = mkIf config.services.binary-cache.enable {
    warnings = [
      "services.binary-cache is deprecated - use services.nix-cache instead."
      "  services.nix-cache = { enable = true; port = 50000; bindAddress = \"10.1.1.120\"; };"
    ];
  };
}
