# MicroVM configuration: CI Test Runner
# Phase 3: Disposable VM for pre-deploy integration testing
#
# This is NOT a regular host -- it's a microVM that runs on zephyr.
# It imports the microvm module and gets minimal services for testing.
#
# The host (zephyr) references this via microvm.vms.ci-test.flake = inputs.self

{ inputs, ... }:

{
  imports = [
    inputs.microvm.nixosModules.microvm
  ];

  microvm = {
    hypervisor = "cloud-hypervisor";
    mem = 2048;
    vcpu = 2;
    interfaces = [{
      type = "tap";
      id = "vm-ci-test";
      mac = "02:00:00:00:00:01";
    }];
    shares = [{
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag = "ro-store";
      proto = "virtiofs";
    }];
  };

  # Minimal VM config
  system.stateVersion = "24.11";
  services.openssh.enable = true;
  networking.firewall.enable = true;

  environment.systemPackages = with inputs.nixpkgs.legacyPackages.x86_64-linux; [
    curl
    jq
    coreutils
  ];

  # Health check service inside the VM
  systemd.services.ci-healthcheck = {
    description = "CI health check";
    wantedBy = [ "multi-user.target" ];
    script = ''
      echo "CI VM health check passed at $(date)"
    '';
    serviceConfig.Type = "oneshot";
  };
}
