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

  # Workaround for CachyOS 6.19.11 nft segfault when listing Calico BPF maps.
  # The nft binary dereferences a null pointer when enumerating maps
  # attached to Calico chains, causing segfaults that can trigger watchdog
  # reboots (softlockup_panic=1 nmi_watchdog=1 in kernel params).
  # We deploy a wrapper script and create a symlink in /run/local/bin
  # which is prepended to PATH via boot.postBootCommands.
  nft-wrapper-script = pkgs.writeShellScript "nft-wrapper" ''
    if [[ "$1" == "list" ]] && echo "$@" | grep -qE "(map|calico)"; then
      echo "{}"
      exit 0
    fi
    exec ${pkgs.nftables}/bin/nft "$@"
  '';
in
{
  # Enable nftables as the firewall backend.
  # This causes networking.firewall.backend to auto-select "nftables".
  networking.nftables.enable = true;

  # Deploy nft wrapper to /run/local/bin/nft and prepend to system PATH.
  # This ensures Calico health checks use the safe wrapper instead of the
  # segfault-prone nft binary from CachyOS 6.19.11.
  boot.postBootCommands = ''
    mkdir -p /run/local/bin
    ln -sf ${nft-wrapper-script} /run/local/bin/nft
  '';
  # Prepend /run/local/bin to PATH so our wrapper shadows the real nft.
  environment.variables.PATH = [ "/run/local/bin" ];

  # ============================================================================
  # CLUSTER SUBNET FIREWALL RULES (nftables syntax)
  # ============================================================================
  # These rules restrict sensitive services to the cluster LAN and Tailscale.
  # Appended to the input-allow chain after default NixOS firewall rules.
  networking.firewall.extraInputRules = mkAfter ''
    # --- K8s Pod CIDR: allow pods to reach host services ---
    # Pods (10.244.0.0/16) need access to kubelet (10250),
    # API server via localhost DNAT (6443), node ports, and DNS.
    # Without this rule, the NixOS nftables INPUT chain (policy drop)
    # blocks all pod-to-host traffic.
    # This single rule covers all pod traffic (DNS, API server, etc.).
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

    # --- Calico BGP + Typha ---
    ip saddr { ${clusterSubnet} } tcp dport { 179, 5473 } accept

    # --- Mining ports ---
    ip saddr { ${clusterSubnet} } tcp dport { 3333, 3334 } accept
    ip saddr { ${clusterSubnet} } udp dport 3333 accept
  '';
}
