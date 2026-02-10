# Colmena Cluster Deployment Configuration (v0.5+)
{
  inputs,
  self,
  ...
}: let
  inherit (inputs.nixpkgs) lib;
in {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
  };

  # Default deployment settings
  defaults = {pkgs, ...}: {
    deployment = {
      allowLocalDeployment = true;
    };
  };

  # Host configurations with NixOS configs
  zephyr = { config, pkgs, ... }: {
    imports = [
      ./configuration.nix
      ./hosts/zephyr/configuration.nix
    ];
    deployment.targetHost = "100.81.182.5"; # Tailscale IP (Local: 10.1.1.110)
    deployment.targetUser = "root";
  };

  nexus = { config, pkgs, ... }: {
    imports = [
      ./configuration.nix
      ./hosts/nexus/configuration.nix
    ];
    deployment.targetHost = "100.86.158.18"; # Tailscale IP (Local: 10.1.1.120)
    deployment.targetUser = "j_kro";
  };

  forge = { config, pkgs, ... }: {
    imports = [
      ./configuration.nix
      ./hosts/forge/configuration.nix
    ];
    deployment.targetHost = "100.95.222.45"; # Tailscale IP (Local: 10.1.1.130)
    deployment.targetUser = "j_kro";
  };

  sentry = { config, pkgs, ... }: {
    imports = [
      ./configuration.nix
      ./hosts/sentry/configuration.nix
    ];
    deployment.targetHost = "100.82.210.39"; # Tailscale IP (Local: 10.1.1.140)
    deployment.targetUser = "j_kro";
  };
}
