# MicroVM host configuration for declarative MicroVMs
# Phase 3: Qubes-like compartmentalization via microvm.nix
# https://github.com/microvm-nix/microvm.nix
#
# Prepares zephyr to run MicroVMs:
# - /var/lib/microvms state directory (one per VM)
# - systemd services: microvm-tap-interfaces@, microvm-virtiofsd@, microvm@
#
# VMs defined in microvm.vms use two modes:
# - flake = self: declarative deployment (initial only, update via microvm -u)
# - config = { ... }: fully declarative (built with host)
#
# NOTE: No NAT configured here -- zephyr's existing firewall handles routing.
# VMs communicate via the microvm0 bridge.
{inputs, ...}: {
  imports = [inputs.microvm.nixosModules.host];

  # No autostart -- VMs are created on-demand for CI testing
  microvm.autostart = [];

  # Network bridge for MicroVMs
  networking.bridges.microvm0.interfaces = [];

  # Open firewall for MicroVM management
  networking.firewall.interfaces.microvm0.allowedTCPPorts = [22];

  # MicroVM definitions
  microvm.vms = {
    # ── CI Test Runner (on-demand, declarative deployment) ──
    # Disposable VM for pre-deploy integration testing
    # Spin up → run health checks → destroy
    #
    # Usage:
    #   microvm -u ci-test   # update from flake
    #   microvm -r ci-test   # start the VM
    #   microvm -s ci-test   # stop and destroy
    ci-test = {
      flake = inputs.self;
      updateFlake = "git+file:///etc/nixos";
    };

    # ── Future: Hermes AI Gateway (fully declarative) ──
    # Network-facing service isolated in its own kernel
    # hermes-gateway = { config = { pkgs, ... }: { ... }; };

    # ── Future: Sensitive Ops (on-demand) ──
    # Crypto wallets, secrets, air-gapped operations
    # sensitive-ops = { flake = inputs.self; updateFlake = "git+file:///etc/nixos"; };
  };
}
