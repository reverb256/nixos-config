# Colmena Cluster Deployment Configuration
# Single-source-of-truth: Host definitions from flake.nix
{
  inputs,
  self,
  ...
}: let
  # ========================================================================
  # CPU TUNING - Per-node microarchitecture optimization
  # ========================================================================
  tunedNixpkgs = system: microarch:
    import inputs.nixpkgs {
      localSystem = {
        inherit system;
        gcc.arch = microarch;
      };
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

    # Per-node CPU microarchitecture tuning
    nodeNixpkgs = {
      zephyr = tunedNixpkgs "x86_64-linux" "znver3"; # Ryzen 9 5950X (Zen 3)
      nexus = tunedNixpkgs "x86_64-linux" "znver2"; # Ryzen 9 3900X (Zen 2)
      forge = tunedNixpkgs "x86_64-linux" "skylake"; # i5-9500 (Coffee Lake)
      sentry = tunedNixpkgs "x86_64-linux" "znver1"; # Ryzen 7 1700 (Zen 1)
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
