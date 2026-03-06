# Colmena Cluster Deployment Configuration
# Single-source-of-truth: Host definitions from flake.nix
{
  inputs,
  self,
  hosts,
  ...
}: let
  # ========================================================================
  # COMMON MODULES - Shared across all hosts (matches flake.nix)
  # ========================================================================
  commonModules = [
    # External modules
    inputs.home-manager.nixosModules.home-manager
    inputs.aagl.nixosModules.default
    inputs.nur.modules.nixos.default
    inputs.agenix.nixosModules.default

    # Internal modules (auto-imports all subdirectories)
    ./modules/default.nix

    # Overlays configuration - applies overlays.default to all hosts
    { nixpkgs.overlays = [ self.overlays.default ]; }
  ];

  # ========================================================================
  # HELPER FUNCTION - Add deployment metadata to host config
  # ========================================================================
  mkHost = {
    hostName,
    targetHost,
  }: { ... }: {
    imports = commonModules ++ [
      ./hosts/${hostName}/configuration.nix
    ];

    deployment = {
      inherit targetHost;
      targetUser = "j_kro";
      allowLocalDeployment = true;
    };
  };

  # ========================================================================
  # DEPLOYMENT METADATA - Target host addresses
  # Uses Tailscale DNS for reliable cluster connectivity
  # ========================================================================
  hostDeployment = {
    zephyr = { targetHost = null; };  # Local host - no SSH needed
    nexus = { targetHost = "nexus"; };
    forge = { targetHost = "forge"; };
    sentry = { targetHost = "sentry"; };
  };

in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
    specialArgs = { inherit inputs self; };
  };

  # ========================================================================
  # GENERATE HOST CONFIGURATIONS
  # ========================================================================
  zephyr = mkHost {
    hostName = "zephyr";
    targetHost = hostDeployment.zephyr.targetHost;
  };

  nexus = mkHost {
    hostName = "nexus";
    targetHost = hostDeployment.nexus.targetHost;
  };

  forge = mkHost {
    hostName = "forge";
    targetHost = hostDeployment.forge.targetHost;
  };

  sentry = mkHost {
    hostName = "sentry";
    targetHost = hostDeployment.sentry.targetHost;
  };
}
