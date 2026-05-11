{ config, lib, pkgs, ... }:
let
  cfg = config.networking.cluster;
  hosts = cfg.hosts;
in {
  # Auto-generate /etc/hosts from cluster topology
  networking.extraHosts = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: host:
      "${host.ip} ${name}.cluster.local ${name}"
    ) hosts
  );

  # Firewall rules use cluster CIDRs, not hardcoded IPs
  networking.firewall.extraCommands = lib.mkAfter ''
    # Allow cluster pod network
    iptables -A nixos-fw -s ${cfg.podCidr} -j nixos-fw-accept
    # Allow cluster service network
    iptables -A nixos-fw -s ${cfg.serviceCidr} -j nixos-fw-accept
  '';
}
