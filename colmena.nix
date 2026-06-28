{
  inputs,
  self,
  ...
}: let
  tunedNixpkgs = system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [((import ./overlay.nix) {inherit inputs;})];
    };

  tunedNixpkgs2605 = system:
    import inputs.nixpkgs-2605 {
      inherit system;
      config.allowUnfree = true;
      overlays = [((import ./overlay.nix) {inherit inputs;})];
    };

  commonModules = import ./common-modules-list.nix {
    inherit inputs self;
  };

  mkHost = {
    hostName,
    targetHost,
    tags ? [],
  }: {...}: {
    imports =
      commonModules
      ++ [
        ./hosts/${hostName}/configuration.nix
      ];
    deployment = {
      inherit targetHost;
      targetUser = "j_kro";
      inherit tags;
      buildOnTarget = false;
      replaceUnknownProfiles = true;
      allowLocalDeployment =
        if targetHost == null
        then true
        else false;
      keys = {};
    };
  };
in {
  meta = {
    nixpkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    nodeNixpkgs = {
      zephyr = tunedNixpkgs "x86_64-linux";
      nexus = tunedNixpkgs "x86_64-linux";
      forge = tunedNixpkgs "x86_64-linux";
      sentry = tunedNixpkgs "x86_64-linux";
      krash3 = tunedNixpkgs2605 "x86_64-linux";
    };
    machinesFile = ./machines;
    specialArgs = {
      inherit inputs self;
    };
    allowApplyAll = false;
  };

  zephyr = mkHost { hostName = "zephyr"; targetHost = null; tags = ["control-plane" "k8s-master" "k8s-node" "local"]; };
  nexus = mkHost { hostName = "nexus"; targetHost = "10.1.1.120"; tags = ["storage" "k8s-worker" "k8s-storage" "nvidia-gpu" "remote"]; };
  forge = mkHost { hostName = "forge"; targetHost = "10.1.1.130"; tags = ["gpu" "compute" "k8s-worker" "k8s-gpu-mixed" "remote"]; };
  sentry = mkHost { hostName = "sentry"; targetHost = "10.1.1.140"; tags = ["monitoring" "k8s-worker" "k8s-gpu-amd" "remote"]; };

  krash3 = mkHost { hostName = "krash3"; targetHost = "10.1.1.150"; tags = ["gaming-vm" "storage" "remote"]; };
}
