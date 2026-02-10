# Mining Services Module
# References existing mining module
# This is a placeholder - actual mining module is in modules/mining.nix
{lib, ...}:
with lib; {
  # Import the existing mining module
  imports = [../../modules/mining.nix];
}
