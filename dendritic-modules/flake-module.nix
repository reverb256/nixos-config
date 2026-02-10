# Flake-Parts Module for NixOS Configurations
# Defines NixOS systems using dendritic architecture
{
  lib,
  inputs,
  ...
}:
with lib; let
  inherit (inputs.nixpkgs) lib;
in {
  # ============================================================================
  # NIXOS CONFIGURATIONS
  # ============================================================================

  flake.nixosModules = rec {
    # Import common modules (from legacy modules/ for now)
    commonModules = [
      ./core/base.nix
      ./core/users.nix
      ./core/networking.nix
      ./core/nix-config.nix

      # External modules
      inputs.ezkea.nixosModules.default
      inputs.determinate.nixosModules.default
      inputs.nix-gaming.nixosModules.pipewireLowLatency
      inputs.nix-gaming.nixosModules.platformOptimizations
      inputs.agenix.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak

      # Legacy shared modules (will be migrated gradually)
      inputs.self.legacyModules.systemPackages
      inputs.self.legacyModules.lobsterUser
    ];

    # Function to create a NixOS system definition
    mkNixosSystem = {modules ? []}:
      inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        # Pass all inputs to specialArgs for modules to use
        specialArgs = {inherit inputs;};
        modules = commonModules ++ modules;
      };

    # ============================================================================
    # ZEPHYR - Master Workstation (32 cores, RTX 3090)
    # ============================================================================

    zephyr = mkNixosSystem {
      modules = [
        ./profiles/desktop.nix
        ./compute/nvidia.nix

        # Host-specific modules from legacy modules/
        inputs.self.legacyModules.autoUpdate
        inputs.self.legacyModules.tailscale
        inputs.self.legacyModules.aistorSecrets
        inputs.self.legacyModules.nixCacheServer
        inputs.self.legacyModules.mcpServers
        inputs.self.legacyModules.nixLd
        inputs.self.legacyModules.mining

        # Host-specific configuration
        ./hosts/zephyr.nix
      ];
    };

    # ============================================================================
    # NEXUS - Build Server (24 cores, 2x RTX 3060 Ti)
    # ============================================================================

    nexus = mkNixosSystem {
      modules = [
        ./profiles/desktop.nix
        ./compute/nvidia.nix

        # Host-specific modules from legacy modules/
        inputs.self.legacyModules.autoUpdate
        inputs.self.legacyModules.tailscale
        inputs.self.legacyModules.aistorSecrets
        inputs.self.legacyModules.mining
        inputs.self.legacyModules.distributedBuilds

        # Host-specific configuration
        ./hosts/nexus.nix
      ];
    };

    # ============================================================================
    # FORGE - GPU Mining Rig (6 cores, 2x RTX 4060 + 2x RX 5700 XT)
    # ============================================================================

    forge = mkNixosSystem {
      modules = [
        ./profiles/desktop.nix
        ./compute/nvidia.nix
        ./compute/amd.nix

        # Host-specific modules from legacy modules/
        inputs.self.legacyModules.autoUpdate
        inputs.self.legacyModules.tailscale
        inputs.self.legacyModules.mining
        inputs.self.legacyModules.distributedBuilds

        # Host-specific configuration
        ./hosts/forge.nix
      ];
    };

    # ============================================================================
    # SENTRY - Monitoring Server (8 cores, RX 5600 XT)
    # ============================================================================

    sentry = mkNixosSystem {
      modules = [
        ./profiles/desktop.nix
        ./compute/amd.nix

        # Host-specific modules from legacy modules/
        inputs.self.legacyModules.autoUpdate
        inputs.self.legacyModules.tailscale
        inputs.self.legacyModules.mining

        # Host-specific configuration
        ./hosts/sentry.nix
      ];
    };
  };

  # ============================================================================
  # LEGACY MODULES (temporary shim during migration)
  # ============================================================================

  flake.legacyModules = rec {
    systemPackages = ../modules/system-packages.nix;
    lobsterUser = ../modules/lobster-user.nix;
    autoUpdate = ../modules/auto-update.nix;
    tailscale = ../modules/tailscale.nix;
    aistorSecrets = ../modules/aistor-secrets.nix;
    nixCacheServer = ../modules/nix-cache-server.nix;
    mcpServers = ../modules/mcp-servers.nix;
    nixLd = ../modules/nix-ld.nix;
    mining = ../modules/mining.nix;
    distributedBuilds = ../modules/distributed-builds.nix;
  };

  # ============================================================================
  # HOME MANAGER CONFIGURATION
  # ============================================================================

  flake.homeManagerModules = {
    default = {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bak";
      home-manager.extraSpecialArgs = {inherit inputs;};
      home-manager.users.j_kro = import ../home.nix;
    };
  };

  # ============================================================================
  # COLMENA CONFIGURATION
  # ============================================================================

  flake.colmena = import ../colmena.nix {
    inherit inputs;
    inherit (inputs.nixpkgs) lib;
  };

  # ============================================================================
  # SHARED OVERLAYS
  # ============================================================================

  flake.overlays = {
    default = import ../modules/mining-overlay.nix;
  };
}
