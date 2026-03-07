# Colmena Cluster Deployment Configuration
# Single-source-of-truth: Host definitions from flake.nix
{
  inputs,
  self,
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
    {nixpkgs.overlays = [self.overlays.default];}
  ];

  # ========================================================================
  # HELPER FUNCTION - Add deployment metadata to host config
  # ========================================================================
  mkHost = {
    hostName,
    targetHost,
  }: {...}: {
    imports =
      commonModules
      ++ [
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
  # All hosts use Tailscale IPs for reliable SSH connectivity
  # ========================================================================
  hostDeployment = {
    zephyr = {targetHost = null;};         # Local host - no SSH needed
    nexus = {targetHost = "100.86.158.18";}; # Tailscale IP
    forge = {targetHost = "100.95.222.45";};  # Tailscale IP
    sentry = {targetHost = "100.81.171.24";}; # Tailscale IP
  };
in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
    specialArgs = {inherit inputs self;};
  };

  # ========================================================================
  # GENERATE HOST CONFIGURATIONS
  # ========================================================================
  zephyr = mkHost {
    hostName = "zephyr";
    inherit (hostDeployment.zephyr) targetHost;
  };

  nexus = mkHost {
    hostName = "nexus";
    inherit (hostDeployment.nexus) targetHost;
  };

  forge = mkHost {
    hostName = "forge";
    inherit (hostDeployment.forge) targetHost;
  };

  sentry = mkHost {
    hostName = "sentry";
    inherit (hostDeployment.sentry) targetHost;
  };
}
