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
  #
  # IMPORTANT: Only intercept "list" + "map|calico" queries (read-only).
  # All other nft calls (add, delete, flush, create) MUST pass through
  # to the real binary — intercepting them prevents Calico from
  # initializing its dataplane (tables/chains), causing infinite retries
  # and cascading nft segfaults.
  nft-wrapper-script = pkgs.writeShellScript "nft-wrapper" ''
    # Only intercept list operations involving maps or calico tables.
    # "list" may appear as $1 or after flags (e.g., "--json list maps ip"),
    # so we grep across all args rather than checking $1 alone.
    # All other nft calls (add, delete, flush, create) MUST pass through
    # to the real binary — intercepting them prevents Calico from
    # initializing its dataplane (tables/chains).
    if echo "$@" | grep -qE "(^|[[:space:]])(list)" && echo "$@" | grep -qE "(map|calico)"; then
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

  # Disable br_netfilter — it intercepts bridge traffic through iptables,
  # causing conflicts with both iptables-legacy and iptables-nft loaded.
  # This breaks K8s pod networking (TCP/UDP forwarded traffic silently dropped).
  # K3s/Calico handle their own packet filtering via iptables-nft.
  boot.blacklistedKernelModules = [
    "br_netfilter"
    "ip_tables"
    "iptable_filter"
    "iptable_nat"
    "iptable_mangle"
    "iptable_raw"
  ];

  # Deploy nft wrapper via systemd tmpfiles (persists across reboots).
  # This ensures Calico health checks use the safe wrapper instead of the
  # segfault-prone nft binary from CachyOS 6.19.11.
  systemd.tmpfiles.rules = [
    "L+ /run/local/bin/nft - - - - ${nft-wrapper-script}"
  ];
  # Prepend /run/local/bin to PATH so our wrapper shadows the real nft.
  environment.variables.PATH = [ "/run/local/bin" ];

  # ============================================================================
  # NFT COREDUMP CLEANUP
  # ============================================================================
  # CachyOS 6.19.11 kernel bug: nft segfaults (null pointer deref) when
  # listing BPF maps inside Calico's container-internal /usr/sbin/nft.
  # The Tigera operator prevents injecting a wrapper into the container,
  # so segfaults cannot be fully stopped without a kernel update.
  #
  # Each coredump is ~345KB compressed at ~3-4/min. This timer cleans them
  # every 10 minutes to prevent disk exhaustion.
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
