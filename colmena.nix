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
  };
in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      overlays = [];
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
      ./configuration.nix
      ./hosts/zephyr/configuration.nix
    ];
    deployment.targetHost = "100.81.182.5"; # Tailscale IP (Local: 10.1.1.110)
    deployment.targetUser = "root";
  };

  nexus = {
    name,
    nodes,
    pkgs,
    ...
  }: {
    imports = [
      ./configuration.nix
      ./hosts/nexus/configuration.nix
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
      ./configuration.nix
      ./hosts/forge/configuration.nix
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
      ./configuration.nix
      ./hosts/sentry/configuration.nix
    ];
    deployment.targetHost = "100.82.210.39"; # Tailscale IP (Local: 10.1.1.140)
    deployment.targetUser = "j_kro";
  };
}
