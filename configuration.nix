# NixOS Configuration - Entry Point for Zephyr
# This file imports the modular configuration from hosts/zephyr
{inputs, ...}: {
  imports = [
    # Import the host-specific configuration
    ./hosts/zephyr/configuration.nix

    # Home Manager
    inputs.home-manager.nixosModules.home-manager

    # AAGL for anime game launchers
    inputs.aagl.nixosModules.default

    # Overlay
    {nixpkgs.overlays = [(import ./overlay.nix)];}
  ];

  # ============================================================================
  # ADDITIONAL FLAKE INPUTS
  # ============================================================================
  # Note: gaming.nix will use nixpkgs-xr when added to inputs
  # For now, gaming works with standard Proton
}
