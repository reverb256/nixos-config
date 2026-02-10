# Colmena Cluster Deployment Configuration
{
  inputs,
  self,
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
    deployment.targetHost = "100.81.182.5"; # Local: 10.1.1.110
    deployment.targetUser = "j_kro";
  };

  nexus = {
    imports = [
      ./configuration.nix
      ./hosts/nexus/configuration.nix
    ];
    deployment.targetHost = "100.86.158.18"; # Local: 10.1.1.120
    deployment.targetUser = "j_kro";
  };

  forge = {
    imports = [
      ./configuration.nix
      ./hosts/forge/configuration.nix
    ];
    deployment.targetHost = "100.95.222.45"; # Local: 10.1.1.130
    deployment.targetUser = "j_kro";
  };

  sentry = {
    imports = [
      ./configuration.nix
      ./hosts/sentry/configuration.nix
    ];
    deployment.targetHost = "100.82.210.39"; # Local: 10.1.1.140
    deployment.targetUser = "j_kro";
  };
}
