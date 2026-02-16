# Colmena Cluster Deployment Configuration (v0.5+)
# Refactored to eliminate duplication using helper functions
#
# Can be used in two ways:
# 1. As a flake output: receives 'inputs' and 'self' from flake.nix
# 2. Directly: when used without flake, uses throw to remind users to use flake
{
  inputs ? null,
  self ? null,
  ...
}:
let
  # Check if we're in flake context
  isFlake = inputs != null && self != null;
  # Handle the case where we're not in flake context
  actualInputs = if isFlake then inputs else throw "colmena.nix must be used as a flake output. Use 'nix run .#apps.x86_64-linux.colmena' instead of 'colmena -f ./colmena.nix'";
  actualSelf = if isFlake then self else throw "colmena.nix must be used as a flake output. Use 'nix run .#apps.x86_64-linux.colmena' instead of 'colmena -f ./colmena.nix'";
in
if !isFlake then
  throw "colmena.nix must be used as a flake output. Use 'nix run .#apps.x86_64-linux.colmena' instead of 'colmena -f ./colmena.nix'"
else
let
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
    # Stylix modules must be imported early
    inputs.stylix.nixosModules.stylix
  ];

  # Home Manager configuration (identical for all hosts)
  homeManagerConfig = {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.j_kro = { pkgs, ... }: {
      imports = [
        ./home.nix
        inputs.stylix.homeModules.stylix
      ];
    };
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
      hostConfig = ./hosts/zephyr/configuration.nix;
      tailscaleIP = "100.81.182.5";
    };

    nexus = {
      hostConfig = ./hosts/nexus/configuration.nix;
      tailscaleIP = "100.86.158.18";
    };

    forge = {
      hostConfig = ./hosts/forge/configuration.nix;
      tailscaleIP = "100.95.222.45";
    };

    sentry = {
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
