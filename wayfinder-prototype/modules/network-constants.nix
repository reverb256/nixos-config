# network-constants — plumbing (dissolve Q3 → B)
#
# REAL file stays at modules/network-constants.nix in the repo. This is a
# MINIMAL STAND-IN for the prototype so the reference flake evaluates. Content
# unchanged in the real conversion (inputs-specialargs-plumbing Q2 → A): it
# stays a plain NixOS module, imported by path in base, read via
# config.networking.cluster.
{
  config,
  lib,
  ...
}: {
  options.networking.cluster = lib.mkOption {
    type = lib.types.attrs;
    description = "Cluster constants (hosts, VIPs, roles) — SSOT from contracts/host-inventory.nix";
  };

  config.networking.cluster = {
    kubernetes.vip = "10.1.1.120";
    hosts = {
      zephyr.ip = "10.1.1.111";
      nexus.ip = "10.1.1.114";
      forge.ip = "10.1.1.115";
      sentry.ip = "10.1.1.120";
    };
  };
}
