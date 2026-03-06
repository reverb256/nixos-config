# Nix Settings Module
# Nix configuration, auto-upgrade, and system settings
{lib, ...}: {
  nix = {
    # Automatic garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = lib.mkDefault "--delete-older-than 7d";
    };

    # Nix channel settings
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    # System-wide optimisation
    optimise.automatic = true;
  };

  # Auto upgrade (optional - disabled for stability)
  # system.autoUpgrade = {
  #   enable = false;
  #   dates = "weekly";
  # };

  # =========================================================================
  # FLAKE SETTINGS
  # =========================================================================
  #
  # Update flakes:
  #   sudo nix flake update /etc/nixos
  #
  # Show flake metadata:
  #   nix flake metadata /etc/nixos
  #
  # Check for outdated inputs:
  #   nix flake show /etc/nixos
  #
  # =========================================================================
}
