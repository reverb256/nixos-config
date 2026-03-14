# Colmena Cluster Deployment Configuration
# Single-source-of-truth: Host definitions from flake.nix
{
  inputs,
  self,
  ...
}: let
  # ========================================================================
  # CPU TUNING - Base x86_64 (v3 reverted 2026-03-14)
  # ========================================================================
  # All cluster nodes use base x86_64 for binary cache compatibility
  tunedNixpkgs = system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
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

    # x86-64-v3 microarchitecture tuning DISABLED - reverting to base x86_64
    # {
    #   nixpkgs.hostPlatform = {
    #     system = "x86_64-linux";
    #     gcc.arch = "x86-64-v3";
    #   };
    # }
  ];

  # ========================================================================
  # HELPER FUNCTION - Add deployment metadata to host config
  # ========================================================================
  mkHost = {
    hostName,
    targetHost,
    tags ? [],
  }: {...}: {
    imports =
      commonModules
      ++ [
        ./hosts/${hostName}/configuration.nix
      ];

    deployment = {
      inherit targetHost;
      targetUser = "j_kro";
      inherit tags;
      allowLocalDeployment =
        if targetHost == null
        then true
        else false;
    };
  };
  # ========================================================================
  # DEPLOYMENT METADATA - Target host addresses
  # Using local network IPs (10.1.1.x) for reliable SSH connectivity
  # Tailscale IPs kept as reference comment in case needed
  # ========================================================================
in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    # Per-node CPU microarchitecture tuning - unified x86-64-v3
    nodeNixpkgs = {
      zephyr = tunedNixpkgs "x86_64-linux";
      nexus = tunedNixpkgs "x86_64-linux";
      forge = tunedNixpkgs "x86_64-linux";
      sentry = tunedNixpkgs "x86_64-linux";
    };

    # Distributed builds
    machinesFile = ./machines;

    specialArgs = {inherit inputs self;};
  };

  # ========================================================================
  # GENERATE HOST CONFIGURATIONS
  # ========================================================================
  zephyr = mkHost {
    hostName = "zephyr";
    targetHost = null; # No SSH (local deployment)
    tags = ["control-plane" "k8s-master" "k8s-node" "local"];
  };

  nexus = mkHost {
    hostName = "nexus";
    targetHost = "10.1.1.120";
    tags = ["storage" "k8s-worker" "k8s-storage" "nvidia-gpu" "remote"];
  };

  forge = mkHost {
    hostName = "forge";
    targetHost = "10.1.1.130";
    tags = ["gpu" "compute" "k8s-worker" "k8s-gpu-mixed" "remote"];
  };

  sentry = mkHost {
    hostName = "sentry";
    targetHost = "10.1.1.140";
    tags = ["monitoring" "k8s-worker" "k8s-gpu-amd" "remote"];
  };
}
