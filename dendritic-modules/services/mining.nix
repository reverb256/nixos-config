# Mining Services Module
# References the existing mining module
# This is a placeholder - actual mining module is in modules/mining.nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  # Import the existing mining module
  imports = [../../modules/mining.nix];
}
