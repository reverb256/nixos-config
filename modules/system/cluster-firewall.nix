{
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkAfter mkDefault;
  clusterSubnet = "10.1.1.0/24";
  podCidr = "10.244.0.0/16";

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

  # Force pod CIDR traffic to use main routing table (eth0) instead of flannel VXLAN.
  # Fixes K3s hostNetwork pods that get CNI default route but need to reach node IPs.
  networking.localCommands = ''
    ip rule add from 10.244.0.0/16 table main priority 100 2>/dev/null || true
  '';

  boot.blacklistedKernelModules = ["br_netfilter"];

  systemd.tmpfiles.rules = [
    "L+ /run/local/bin/nft - - - - ${nft-wrapper-script}"
    "L+ /run/local/bin/iptables - - - - ${iptables-legacy-wrapper}"
    "L+ /run/local/bin/ip6tables - - - - ${ip6tables-legacy-wrapper}"
  ];
  environment.variables.PATH = ["/run/local/bin"];

  systemd.services.nft-coredump-cleanup = {
    description = "Clean nft coredumps (CachyOS kernel bug workaround)";
    script = ''
      find /var/lib/systemd/coredump -name 'core.nft.*' -mmin +1 -delete 2>/dev/null
    '';
    serviceConfig.Type = "oneshot";
  };
  systemd.timers.nft-coredump-cleanup = {
    wantedBy = ["timers.target"];
    timerConfig.OnCalendar = "*:0/10:00";
    timerConfig.Persistent = false;
  };

  networking.firewall.extraInputRules = mkAfter ''
      ip saddr { ${podCidr} } accept

      # SECURITY: K3s API restricted to control plane nodes only
    ip saddr { 10.1.1.120,10.1.1.130,10.1.1.140 } tcp dport { 6443, 10443 } accept
      iifname "tailscale0" tcp dport { 6443, 10443 } accept

      ip saddr { ${clusterSubnet} } tcp dport 10250 accept
      iifname "tailscale0" tcp dport 10250 accept

      # SECURITY: etcd restricted to control plane nodes only
    ip saddr { 10.1.1.120,10.1.1.130,10.1.1.140 } tcp dport { 2379, 2380 } accept

      ip saddr { ${clusterSubnet} } tcp dport { 2049, 111, 20048 } accept
      ip saddr { ${clusterSubnet} } udp dport { 2049, 111, 20048 } accept

      ip saddr { ${clusterSubnet} } udp dport { 8472, 4789 } accept


      ip saddr { ${clusterSubnet} } tcp dport { 3333, 3334 } accept
      ip saddr { ${clusterSubnet} } udp dport 3333 accept
  '';
}
