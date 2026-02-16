# Colmena Cluster Deployment Configuration (v0.5+)
# Refactored to eliminate duplication using helper functions
{
  inputs,
  self,
  ...
}: let
  # Overlay configuration shared across all hosts
  overlays = [
    self.overlays.default
    inputs.nix-openclaw.overlays.default
    inputs.cachyos-kernel.overlays.pinned
  ];

  # Common modules imported by all hosts
  commonExternalModules = [
    inputs.aagl.nixosModules.default
    inputs.determinate.nixosModules.default
    inputs.nix-gaming.nixosModules.pipewireLowLatency
    inputs.nix-gaming.nixosModules.platformOptimizations
    inputs.agenix.nixosModules.default
    inputs.nix-flatpak.nixosModules.nix-flatpak
  ];

  # Home Manager configuration (identical for all hosts)
  homeManagerConfig = {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.j_kro = import ./home.nix;
    home-manager.backupFileExtension = "bak";
    home-manager.extraSpecialArgs = {inherit inputs;};
  };

  # Helper function to create host configuration
  mkHost = {
    hostConfig,
    tailscaleIP,
    extraModules ? [],
  }: {...}: {
    imports =
      commonExternalModules
      ++ [
        ./common-base.nix
        hostConfig
        inputs.home-manager.nixosModules.home-manager
        homeManagerConfig
      ]
      ++ extraModules;

    deployment = {
      targetHost = tailscaleIP;
      targetUser = "j_kro";
      allowLocalDeployment = true;
    };
  };

  # Host configurations
  hosts = {
    zephyr = {
      hostname = "zephyr";
      hostConfig = ./hosts/zephyr/configuration.nix;
      tailscaleIP = "100.81.182.5";
    };

    nexus = {
      hostname = "nexus";
      hostConfig = ./hosts/nexus/configuration.nix;
      tailscaleIP = "100.86.158.18";
    };

    forge = {
      hostname = "forge";
      hostConfig = ./hosts/forge/configuration.nix;
      tailscaleIP = "100.95.222.45";
    };

    sentry = {
      hostname = "sentry";
      hostConfig = ./hosts/sentry/configuration.nix;
      tailscaleIP = "100.82.210.39";
    };
  };
in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
      inherit overlays;
    };
    specialArgs = {
      inherit inputs self;
    };
  };

  # Generate host configurations using the helper function
  zephyr = mkHost hosts.zephyr;
  nexus = mkHost hosts.nexus;
  forge = mkHost hosts.forge;
  sentry = mkHost hosts.sentry;
}
