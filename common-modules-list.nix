# Common Modules List
#
# This file defines the shared module list for both flake.nix and colmena.nix.
# This ensures they always stay in sync and prevents divergence.
#
# Usage:
#   In flake.nix:   commonModules = import ./modules/common-modules-list.nix { inherit inputs self; };
#   In colmena.nix: commonModules = import ./modules/common-modules-list.nix { inherit inputs self; };
#
{
  inputs,
  self,
}:
[

  # EXTERNAL MODULES

  # Home Manager - User configuration management
  inputs.home-manager.nixosModules.home-manager
  # AAGL - Anime Game Launcher (provides anime-game-launcher packages)
  inputs.aagl.nixosModules.default
  # NUR - Nix User Repository (community packages)
  inputs.nur.modules.nixos.default
  # Agenix - Secret encryption/decryption for NixOS
  inputs.agenix.nixosModules.default
  # nixpkgs-xr - Bleeding-edge XR/VR packages with binary cache
  # Provides: wivrn, monado, libsurvive, xrizer, opencomposite, etc.
  # Adds nix-community.cachix.org binary cache automatically
  inputs.nixpkgs-xr.nixosModules.nixpkgs-xr
  # Niri - Scrollable-tiling Wayland compositor
  # Provides: programs.niri NixOS module (enable, settings, package)
  inputs.niri.nixosModules.niri

  # Stylix - Declarative theming framework
  # Provides: stylix.* options for unified color scheme, fonts, wallpaper
  inputs.stylix.nixosModules.stylix

  # INTERNAL MODULES

  # Auto-imports all subdirectories (profiles, system, services, etc.)
  # Path relative to the flake root (where flake.nix and colmena.nix are)
  ./modules/default.nix

  # OVERLAYS CONFIGURATION

  # Custom package overlays applied to ALL hosts
  #
  # Order matters: nixpkgs-xr overlay (above) provides base VR packages,
  # then our custom overlay adds lighthouse support to WiVRn, etc.
  #
  # Scope: System + Home Manager (due to useGlobalPkgs = true)
  # Location: ./overlay.nix defines custom packages (lolminer, xmrig, etc.)
  #
  # See: modules/system/home-manager.nix for useGlobalPkgs setting
  {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.default
      self.overlays.default
    ];
  }

  # AGENIX IDENTITY PATHS - Cluster-wide secret decryption

  # Priority: Syncthing-synced > System > Home directory
  #
  # /etc/nixos/.age/key.txt - Synced via Syncthing across all hosts
  # /etc/age/key.txt - System location (fallback, populated by activation script)
  # /home/j_kro/.age/key.txt - Original location (Zephyr only)
  {
    age.identityPaths = [
      "/etc/nixos/.age/key.txt"
      "/etc/age/key.txt"
      "/home/j_kro/.age/key.txt"
    ];
  }
]
