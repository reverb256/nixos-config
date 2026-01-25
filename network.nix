let
  # Use the same nixpkgs as our flake
  nixpkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable") {};
in {
  network = {
    inherit nixpkgs;
    description = "NixOS Cluster Deployment";
  };

  zephyr = {
    deployment = {
      targetHost = "10.1.1.110";
      targetUser = "j_kro";
      tags = ["workstation" "gaming" "vr"];
    };
    imports = [
      ./hosts/zephyr/configuration.nix
      ./hosts/zephyr/hardware-configuration.nix
    ];
    networking.hostName = "zephyr";
  };

  nexus = {
    deployment = {
      targetHost = "10.1.1.120";
      targetUser = "j_kro";
      tags = ["db" "mining"];
    };
    imports = [
      ./hosts/nexus/configuration.nix
      ./hosts/nexus/hardware-configuration.nix
    ];
    networking.hostName = "nexus";
  };

  forge = {
    deployment = {
      targetHost = "10.1.1.130";
      targetUser = "j_kro";
      tags = ["compute" "gpu" "mining"];
    };
    imports = [
      ./hosts/forge/configuration.nix
      ./hosts/forge/hardware-configuration.nix
    ];
    networking.hostName = "forge";
  };

  sentry = {
    deployment = {
      targetHost = "10.1.1.140";
      targetUser = "j_kro";
      tags = ["monitoring" "gateway"];
    };
    imports = [
      ./hosts/sentry/configuration.nix
      ./hosts/sentry/hardware-configuration.nix
    ];
    networking.hostName = "sentry";
  };
}
