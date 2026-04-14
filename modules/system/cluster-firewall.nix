# Cluster Firewall — Centralized subnet restrictions
# Restricts sensitive services to cluster LAN (10.1.1.0/24) + Tailscale + Pod CIDR only
# Prevents accidental exposure to WAN interfaces
#
# Uses NixOS nftables firewall backend (networking.nftables.enable = true).
# Rules use extraInputRules with native nftables syntax.
# extraCommands/extraStopCommands are INCOMPATIBLE with nftables backend.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkAfter mkDefault;
  clusterSubnet = "10.1.1.0/24";
  podCidr = "10.244.0.0/16";

  # Workaround: CachyOS kernel nft segfault when listing BPF maps.
  # Intercept only read-only list operations on calico/map tables.
  # All other nft calls MUST pass through to the real binary.
  nft-wrapper-script = pkgs.writeShellScript "nft-wrapper" ''
    if echo "$@" | grep -qE "(^|[[:space:]])(list)" && echo "$@" | grep -qE "(map|calico)"; then
      echo "{}"
      exit 0
    fi
    exec ${pkgs.nftables}/bin/nft "$@"
  '';

  # Workaround: CachyOS kernel nft segfault triggered by kube-router.
  # Redirect iptables to iptables-legacy which avoids the nft codepath.
  iptables-legacy-wrapper = pkgs.writeShellScript "iptables-legacy-wrapper" ''
    exec ${pkgs.iptables}/bin/iptables-legacy "$@"
  '';
  ip6tables-legacy-wrapper = pkgs.writeShellScript "ip6tables-legacy-wrapper" ''
    exec ${pkgs.iptables}/bin/ip6tables-legacy "$@"
  '';
in
{
  # Enable nftables as the firewall backend.
  # This causes networking.firewall.backend to auto-select "nftables".
  networking.nftables.enable = true;

  # Disable br_netfilter — intercepts bridge traffic through iptables,
  # causing conflicts with iptables-legacy and iptables-nft loaded simultaneously.
  boot.blacklistedKernelModules = [ "br_netfilter" ];

  # Deploy wrappers via systemd tmpfiles (persists across reboots).
  systemd.tmpfiles.rules = [
    "L+ /run/local/bin/nft - - - - ${nft-wrapper-script}"
    "L+ /run/local/bin/iptables - - - - ${iptables-legacy-wrapper}"
    "L+ /run/local/bin/ip6tables - - - - ${ip6tables-legacy-wrapper}"
  ];
  # Prepend /run/local/bin to PATH so wrappers shadow system binaries.
  environment.variables.PATH = [ "/run/local/bin" ];

  # NFT COREDUMP CLEANUP — CachyOS kernel bug generates ~345KB coredumps at ~3-4/min.
  systemd.services.nft-coredump-cleanup = {
    description = "Clean nft coredumps (CachyOS kernel bug workaround)";
    script = ''
      find /var/lib/systemd/coredump -name 'core.nft.*' -mmin +1 -delete 2>/dev/null
    '';
    serviceConfig.Type = "oneshot";
  };
  systemd.timers.nft-coredump-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*:0/10:00";
    timerConfig.Persistent = false;
  };

  # ============================================================================
  # CLUSTER SUBNET FIREWALL RULES (nftables syntax)
  # ============================================================================
  # These rules restrict sensitive services to the cluster LAN and Tailscale.
  # Appended to the input-allow chain after default NixOS firewall rules.
  networking.firewall.extraInputRules = mkAfter ''
  # Allow pod-to-host traffic (kubelet, API server, node ports, DNS).
    ip saddr { ${podCidr} } accept

    # --- K8s API Server (6443) ---
    ip saddr { ${clusterSubnet} } tcp dport 6443 accept
    iifname "tailscale0" tcp dport 6443 accept

    # --- Kubelet API (10250) ---
    ip saddr { ${clusterSubnet} } tcp dport 10250 accept
    iifname "tailscale0" tcp dport 10250 accept

    # --- etcd (2379, 2380) ---
    ip saddr { ${clusterSubnet} } tcp dport { 2379, 2380 } accept

    # --- NFS services ---
    ip saddr { ${clusterSubnet} } tcp dport { 2049, 111, 20048 } accept
    ip saddr { ${clusterSubnet} } udp dport { 2049, 111, 20048 } accept

    # --- CNI VXLAN ---
    ip saddr { ${clusterSubnet} } udp dport { 8472, 4789 } accept

    # --- BGP + Typha ---

    # --- Mining ports ---
    ip saddr { ${clusterSubnet} } tcp dport { 3333, 3334 } accept
    ip saddr { ${clusterSubnet} } udp dport 3333 accept
  '';
}
