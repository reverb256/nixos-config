{
  schemaVersion = 1;
  interfaceVersion = "1.0";

  # Canonical Infrastructure -> Platform inventory. NixOS and Colmena consume
  # this data through flake.nix; tests validate all external metadata against it.
  # `memoryMiB` and `capabilities` are declared planning/inventory facts, not
  # live hardware discovery. A future hardware-evidence phase may attach
  # observed values and provenance without changing this contract's shape.
  hosts = {
    zephyr = {
      hostName = "zephyr";
      targetHost = "10.1.1.110";
      targetUser = "j_kro";
      buildOnTarget = false;
      allowLocalDeployment = false;
      tags = ["control-plane" "k8s-master" "k8s-node" "local" "desktop"];
      system = "x86_64-linux";
      memoryMiB = 31744;
      capabilities = ["workstation" "development" "gaming" "nvidia" "k3s-excluded"];
      ipAddress = "10.1.1.110";
      interfaceName = "enp38s0";
      extraModules = [../modules/desktop/desktop-modules.nix];
    };

    nexus = {
      hostName = "nexus";
      targetHost = null;
      targetUser = "j_kro";
      buildOnTarget = false;
      allowLocalDeployment = true;
      tags = ["storage" "k8s-worker" "k8s-storage" "nvidia-gpu" "remote"];
      system = "x86_64-linux";
      memoryMiB = 47104;
      capabilities = ["storage" "builder" "deployment-dispatcher" "nvidia" "k3s-server"];
      ipAddress = "10.1.1.120";
      interfaceName = "eth0";
      extraModules = [];
    };

    forge = {
      hostName = "forge";
      targetHost = "10.1.1.130";
      targetUser = "j_kro";
      # Build forge's closure ON THE DISPATCH HOST (nexus). Deploys are now
      # dispatched from nexus (nexus-dispatch.sh), which is the exclusive build
      # executor and CAN build locally via its own daemon. Setting
      # buildOnTarget=true made forge build on itself and route its build to
      # nexus as an ssh-ng:// remote builder -> self-dispatch deadlock (nexus's
      # daemon waiting on store locks it holds) that permanently stalled the
      # whole colmena apply. buildOnTarget=false lets nexus build forge locally
      # with no ssh self-loop. (The original true assumed dispatch from zephyr,
      # which is max-jobs=0 and cannot build.)
      buildOnTarget = false;
      allowLocalDeployment = false;
      tags = ["gpu" "compute" "k8s-worker" "k8s-gpu-mixed" "remote"];
      system = "x86_64-linux";
      memoryMiB = 15360;
      capabilities = ["gpu" "compute" "mining" "nvidia" "amd" "k3s-server"];
      ipAddress = "10.1.1.130";
      interfaceName = "eno1";
      extraModules = [];
    };

    sentry = {
      hostName = "sentry";
      targetHost = "10.1.1.140";
      targetUser = "j_kro";
      buildOnTarget = false;
      allowLocalDeployment = false;
      tags = ["monitoring" "k8s-worker" "k8s-gpu-amd" "remote"];
      system = "x86_64-linux";
      memoryMiB = 31744;
      capabilities = ["monitoring" "builder" "amd" "k3s-server"];
      ipAddress = "10.1.1.140";
      interfaceName = "enp7s0";
      extraModules = [];
    };
  };
}
