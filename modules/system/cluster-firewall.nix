# Cluster Firewall — Centralized subnet restrictions
# Restricts sensitive services to cluster LAN (10.1.1.0/24) + Tailscale only
# Prevents accidental exposure to WAN interfaces
#
# Uses iptables-compat syntax (extraCommands/extraStopCommands).
# Another agent is migrating to native nftables — this module will be
# updated as part of that migration.
{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkAfter mkDefault;
  clusterSubnet = "10.1.1.0/24";
in
{
  # ============================================================================
  # CLUSTER SUBNET FIREWALL RULES (iptables-compat syntax)
  # ============================================================================
  # These rules restrict sensitive services to the cluster LAN and Tailscale.
  # Appended to the nixos-fw chain after default NixOS firewall rules.
  # NOTE: These will be migrated to native nftables rules as part of the
  # nftables migration.
  networking.firewall.extraCommands = ''
    # --- K8s API Server (6443) ---
    iptables -A nixos-fw -s ${clusterSubnet} -p tcp --dport 6443 -j ACCEPT
    iptables -A nixos-fw -i tailscale0 -p tcp --dport 6443 -j ACCEPT

    # --- Kubelet API (10250) ---
    iptables -A nixos-fw -s ${clusterSubnet} -p tcp --dport 10250 -j ACCEPT
    iptables -A nixos-fw -i tailscale0 -p tcp --dport 10250 -j ACCEPT

    # --- etcd (2379, 2380) ---
    iptables -A nixos-fw -s ${clusterSubnet} -p tcp -m multiport --dports 2379,2380 -j ACCEPT

    # --- NFS services ---
    iptables -A nixos-fw -s ${clusterSubnet} -p tcp -m multiport --dports 2049,111,20048 -j ACCEPT
    iptables -A nixos-fw -s ${clusterSubnet} -p udp -m multiport --dports 2049,111,20048 -j ACCEPT

    # --- CNI VXLAN ---
    iptables -A nixos-fw -s ${clusterSubnet} -p udp -m multiport --dports 8472,4789 -j ACCEPT

    # --- Calico BGP + Typha ---
    iptables -A nixos-fw -s ${clusterSubnet} -p tcp -m multiport --dports 179,5473 -j ACCEPT

    # --- Mining ports ---
    iptables -A nixos-fw -s ${clusterSubnet} -p tcp -m multiport --dports 3333,3334 -j ACCEPT
    iptables -A nixos-fw -s ${clusterSubnet} -p udp --dport 3333 -j ACCEPT
  '';

  networking.firewall.extraStopCommands = ''
    iptables -F nixos-fw-submodule-cluster 2>/dev/null || true
  '';
}
