# Colmena Cluster Deployment Configuration (v0.5+)
# Full module imports - required for proper evaluation
{
  inputs,
  self,
  ...
}: let
  pkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
    overlays = [ self.overlays.default ];
  };
in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      overlays = [ self.overlays.default ];
    };
    specialArgs = {
      inherit inputs self;
    };
  };

  # Default deployment settings
  defaults = {
    deployment = {
      allowLocalDeployment = true;
    };
  };

  # Host configurations with full module imports
  zephyr = {
    name,
    nodes,
    pkgs,
    ...
  }: {
    imports = [
      # External modules (must come before common-base.nix)
      inputs.aagl.nixosModules.default
      inputs.determinate.nixosModules.default
      inputs.nix-gaming.nixosModules.pipewireLowLatency
      inputs.nix-gaming.nixosModules.platformOptimizations
      inputs.agenix.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak
      # Base configuration
      ./common-base.nix
      ./hosts/zephyr/configuration.nix
      # Home Manager (CRITICAL - was missing!)
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.j_kro = import ./home.nix;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = {inherit inputs;};
      }
    ];
    deployment.targetHost = "100.81.182.5"; # Tailscale IP (Local: 10.1.1.110)
    deployment.targetUser = "j_kro";
  };

  nexus = {
    name,
    nodes,
    pkgs,
    ...
  }: {
    imports = [
      # External modules (must come before common-base.nix)
      inputs.aagl.nixosModules.default
      inputs.determinate.nixosModules.default
      inputs.nix-gaming.nixosModules.pipewireLowLatency
      inputs.nix-gaming.nixosModules.platformOptimizations
      inputs.agenix.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak
      # Base configuration
      ./common-base.nix
      ./hosts/nexus/configuration.nix
      # Home Manager (CRITICAL - was missing!)
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.j_kro = import ./home.nix;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = {inherit inputs;};
      }
    ];
    deployment.targetHost = "100.86.158.18"; # Tailscale IP (Local: 10.1.1.120)
    deployment.targetUser = "j_kro";
  };

  forge = {
    name,
    nodes,
    pkgs,
    ...
  }: {
    imports = [
      # External modules (must come before common-base.nix)
      inputs.aagl.nixosModules.default
      inputs.determinate.nixosModules.default
      inputs.nix-gaming.nixosModules.pipewireLowLatency
      inputs.nix-gaming.nixosModules.platformOptimizations
      inputs.agenix.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak
      # Base configuration
      ./common-base.nix
      ./hosts/forge/configuration.nix
      # Home Manager (CRITICAL - was missing!)
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.j_kro = import ./home.nix;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = {inherit inputs;};
      }
    ];
    deployment.targetHost = "100.95.222.45"; # Tailscale IP (Local: 10.1.1.130)
    deployment.targetUser = "j_kro";
  };

  sentry = {
    name,
    nodes,
    pkgs,
    ...
  }: {
    imports = [
      # External modules (must come before common-base.nix)
      inputs.aagl.nixosModules.default
      inputs.determinate.nixosModules.default
      inputs.nix-gaming.nixosModules.pipewireLowLatency
      inputs.nix-gaming.nixosModules.platformOptimizations
      inputs.agenix.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak
      # Base configuration
      ./common-base.nix
      ./hosts/sentry/configuration.nix
      # Home Manager (CRITICAL - was missing!)
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.j_kro = import ./home.nix;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = {inherit inputs;};
      }
    ];
    deployment.targetHost = "100.82.210.39"; # Tailscale IP (Local: 10.1.1.140)
    deployment.targetUser = "j_kro";
  };
}
