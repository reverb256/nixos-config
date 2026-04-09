# Colmena Cluster Deployment Configuration
# Single-source-of-truth: Host definitions from flake.nix
{
  inputs,
  self,
  ...
}:
let

  # CPU TUNING - Base x86_64

  # All cluster nodes use base x86_64 for binary cache compatibility
  tunedNixpkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

  # COMMON MODULES - Shared across all hosts (matches flake.nix)

  # Import from shared file to ensure flake.nix and colmena.nix stay in sync
  commonModules = import ./common-modules-list.nix {
    inherit inputs self;
  };

  # HELPER FUNCTION - Add deployment metadata to host config

  mkHost =
    {
      hostName,
      targetHost,
      tags ? [ ],
    }:
    { ... }:
    {
      imports = commonModules ++ [
        ./hosts/${hostName}/configuration.nix
      ];
      deployment = {
        inherit targetHost;
        targetUser = "j_kro";
        inherit tags;
        allowLocalDeployment = if targetHost == null then true else false;
      };
    };

  # DEPLOYMENT METADATA - Target host addresses
  # Using local network IPs (10.1.1.x) for reliable SSH connectivity
  # Tailscale IPs kept as reference comment in case needed

in
{
  meta = {
    nixpkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    # Per-node CPU microarchitecture tuning - unified x86_64
    nodeNixpkgs = {
      zephyr = tunedNixpkgs "x86_64-linux";
      nexus = tunedNixpkgs "x86_64-linux";
      forge = tunedNixpkgs "x86_64-linux";
      sentry = tunedNixpkgs "x86_64-linux";
    };
    # Distributed builds
    machinesFile = ./machines;
    specialArgs = {
      inherit inputs self;
      k8sManifestPackage = self.packages.x86_64-linux.k8s-manifests;
    };
  };

  # GENERATE HOST CONFIGURATIONS

  zephyr = mkHost {
    hostName = "zephyr";
    targetHost = null; # No SSH (local deployment)
    tags = [
      "control-plane"
      "k8s-master"
      "k8s-node"
      "local"
    ];
  };
  nexus = mkHost {
    hostName = "nexus";
    targetHost = "10.1.1.120";
    tags = [
      "storage"
      "k8s-worker"
      "k8s-storage"
      "nvidia-gpu"
      "remote"
    ];
  };
  forge = mkHost {
    hostName = "forge";
    targetHost = "10.1.1.130";
    tags = [
      "gpu"
      "compute"
      "k8s-worker"
      "k8s-gpu-mixed"
      "remote"
    ];
  };
  sentry = mkHost {
    hostName = "sentry";
    targetHost = "10.1.1.140";
    tags = [
      "monitoring"
      "k8s-worker"
      "k8s-gpu-amd"
      "remote"
    ];
  };
}
