{
  meta = {
    nixpkgs = import <nixpkgs> {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
  };

  defaults = {pkgs, ...}: {
    imports = [
      ./configuration.nix
    ];
    deployment = {
      targetUser = "j_kro";
      allowLocalDeployment = false;
    };
  };

  zephyr = {
    imports = [./hosts/zephyr/configuration.nix];
    deployment.targetHost = "10.1.1.110";
  };

  nexus = {
    imports = [./hosts/nexus/configuration.nix];
    deployment.targetHost = "10.1.1.120";
  };

  forge = {
    imports = [./hosts/forge/configuration.nix];
    deployment.targetHost = "10.1.1.130";
  };

  sentry = {
    imports = [./hosts/sentry/configuration.nix];
    deployment.targetHost = "10.1.1.140";
  };
}
