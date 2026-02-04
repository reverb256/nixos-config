{
  meta = {
    nixpkgs = import <nixpkgs> {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
  };

  defaults = {pkgs, ...}: {
    deployment = {
      targetUser = "j_kro";
      allowLocalDeployment = false;
    };
  };

  zephyr = {
    imports = [
      ./configuration.nix
      ./hosts/zephyr/configuration.nix
    ];
    deployment.targetHost = "10.1.1.110";
  };

  nexus = {
    imports = [
      ./configuration.nix
      ./hosts/nexus/configuration.nix
    ];
    deployment.targetHost = "10.1.1.120";
  };

  forge = {
    imports = [
      ./configuration.nix
      ./hosts/forge/configuration.nix
    ];
    deployment.targetHost = "10.1.1.130";
  };

  sentry = {
    imports = [
      ./configuration.nix
      ./hosts/sentry/configuration.nix
    ];
    deployment.targetHost = "10.1.1.140";
  };
}
