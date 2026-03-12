# NixOS Configuration - Multi-Host Entry Point
# Automatically imports the host-specific configuration based on hostname
{inputs, config, ...}: {
  imports = [
    # Import the host-specific configuration (detected by hostname)
    ./hosts/${config.networking.hostName}/configuration.nix

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
