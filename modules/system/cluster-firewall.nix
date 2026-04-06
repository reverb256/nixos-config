# Cluster Firewall — Centralized subnet restrictions
# Restricts sensitive services to cluster LAN (10.1.1.0/24) + Tailscale only
# Prevents accidental exposure to WAN interfaces
{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkAfter;
  clusterSubnet = "10.1.1.0/24";
in
{
  # ============================================================================
  # NFTABLES — Modern firewall backend
  # ============================================================================
  # Enable nftables as the primary backend. NixOS networking.firewall
  # generates iptables rules which are translated by iptables-nft compat
  # layer. nftables.enable=true ensures the nftables service is active
  # and we can add native nft rules alongside.
  networking.nftables.enable = true;

  # ============================================================================
  # CLUSTER SUBNET FIREWALL RULES
  # ============================================================================
  # These rules restrict sensitive services to the cluster LAN only.
  # They are appended AFTER the default nixos-fw chain so they take
  # precedence over broader rules.
  #
  # Services restricted:
  #   - K8s API server (6443)
  #   - Kubelet API (10250)
  #   - etcd (2379, 2380)
  #   - NFS (2049, 111, 20048)
  #   - Calico/Flannel CNI (8472, 4789)
  #   - k3s agent (6443, 5473)
  networking.firewall.extraCommands = mkAfter ''
    # --- K8s API Server (6443) — cluster subnet only ---
    iptables -A nixos-fw -p tcp --dport 6443 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p tcp --dport 6443 -i tailscale0 -j nixos-fw-accept

    # --- Kubelet API (10250) — cluster subnet only ---
    iptables -A nixos-fw -p tcp --dport 10250 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p tcp --dport 10250 -i tailscale0 -j nixos-fw-accept

    # --- etcd (2379, 2380) — cluster subnet only ---
    iptables -A nixos-fw -p tcp --dport 2379 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p tcp --dport 2380 -s ${clusterSubnet} -j nixos-fw-accept

    # --- NFS services — cluster subnet only ---
    iptables -A nixos-fw -p tcp --dport 2049 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p udp --dport 2049 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p tcp --dport 111 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p udp --dport 111 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p tcp --dport 20048 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p udp --dport 20048 -s ${clusterSubnet} -j nixos-fw-accept

    # --- CNI VXLAN (8472, 4789) — cluster subnet only ---
    iptables -A nixos-fw -p udp --dport 8472 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p udp --dport 4789 -s ${clusterSubnet} -j nixos-fw-accept

    # --- k3s agent (5473) — cluster subnet only ---
    iptables -A nixos-fw -p tcp --dport 5473 -s ${clusterSubnet} -j nixos-fw-accept

    # --- Calico BGP (179) — cluster subnet only ---
    iptables -A nixos-fw -p tcp --dport 179 -s ${clusterSubnet} -j nixos-fw-accept

    # --- Mining ports (3333, 3334) — cluster subnet only ---
    iptables -A nixos-fw -p tcp --dport 3333 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p udp --dport 3333 -s ${clusterSubnet} -j nixos-fw-accept
    iptables -A nixos-fw -p tcp --dport 3334 -s ${clusterSubnet} -j nixos-fw-accept
  '';

  networking.firewall.extraStopCommands = ''
    iptables -F nixos-fw-extra 2>/dev/null || true
  '';
}
