# Colmena Cluster Deployment Configuration
{
  inputs,
  lib,
  ...
}: let
  nixpkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
in {
  meta = {
    inherit nixpkgs;
  };

  defaults = {
    deployment = {
      allowLocalDeployment = true;
    };
  };

  zephyr = {
    imports = [
      ./configuration.nix
      ./hosts/zephyr/configuration.nix
    ];
    deployment.targetHost = "100.81.182.5";
    deployment.targetUser = "j_kro";
  };

  nexus = {
    imports = [
      ./configuration.nix
      ./hosts/nexus/configuration.nix
    ];
    deployment.targetHost = "100.86.158.18";
    deployment.targetUser = "j_kro";
  };

  forge = {
    imports = [
      ./configuration.nix
      ./hosts/forge/configuration.nix
    ];
    deployment.targetHost = "100.116.190.124";
    deployment.targetUser = "j_kro";
  };

  sentry = {
    imports = [
      ./configuration.nix
      ./hosts/sentry/configuration.nix
    ];
    deployment.targetHost = "100.82.210.39";
    deployment.targetUser = "j_kro";
  };
}
