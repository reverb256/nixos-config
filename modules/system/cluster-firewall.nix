{
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkAfter;
  clusterSubnet = "10.1.1.0/24";
  podCidr = "10.42.0.0/16";

  nft-wrapper-script = pkgs.writeShellScript "nft-wrapper" ''
    if echo "$@" | grep -qE "(^|[[:space:]])(list)" && echo "$@" | grep -qE "(map|calico)"; then
      echo "{}"
      exit 0
    fi
    exec ${pkgs.nftables}/bin/nft "$@"
  '';

  iptables-legacy-wrapper = pkgs.writeShellScript "iptables-legacy-wrapper" ''
    exec ${pkgs.iptables}/bin/iptables-legacy "$@"
  '';
  ip6tables-legacy-wrapper = pkgs.writeShellScript "ip6tables-legacy-wrapper" ''
    exec ${pkgs.iptables}/bin/ip6tables-legacy "$@"
  '';
in {
  networking.nftables.enable = true;

  # K3s/Calico IPIP tunneling confuses strict rpfilter.
  # Pod-to-host traffic gets dropped by rpfilter before reaching input-allow.
  # "loose" mode allows traffic if source IP is routable via ANY interface.
  networking.firewall.checkReversePath = "loose";

