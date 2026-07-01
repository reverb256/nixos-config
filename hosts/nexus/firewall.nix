{lib, ...}: let
  # Cluster VIP — keepalived-managed virtual IP (currently on nexus)
  vip = "10.1.1.100";
  # Nexus host IP
  hostIP = "10.1.1.120";
in {
  networking = {
    firewall = {
      extraInputRules = lib.mkAfter ''
        # Nix binary cache (nix-serve)
        tcp dport { 50000 } accept
        # K3s server ports — restricted to cluster nodes only
        ip saddr { 10.1.1.110, 10.1.1.120, 10.1.1.130, 10.1.1.140 } tcp dport { 6443, 2379, 2380, 10250 } accept
        # General services
        tcp dport { 80, 443, 3000, 3900, 3901, 6333, 6334, 8040, 8080, 8642, 8643, 8650, 8787, 9119, 9100, 9400 } accept
      '';
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472
      ];
    };

    # Keep NAT module for masquerade only (K8s pod-to-outside).
    # DNAT is handled by custom nftables table below with VIP exception.
    nat = {
      enable = true;
      externalInterface = "eth0";
      internalInterfaces = [ "kube-bridge" ];
      forwardPorts = [];  # DNAT rules removed — see nixos-nat-dnat table below
    };

    nftables.tables = {
      # Custom DNAT table with VIP bypass.
      #     ┌─ VIP traffic (10.1.1.100) → Nexus Caddy on :80/:443 (serves .lan routes)
      #     └─ Host IP traffic (10.1.1.120) → caddy-ingress NodePorts (30080/30443)
      nixos-nat-dnat = {
        family = "ip";
        content = ''
          chain pre_dnat {
            type nat hook prerouting priority dstnat; policy accept;
            # VIP traffic bypasses DNAT — reaches Nexus Caddy directly
            ip daddr ${vip} return
            # Host IP traffic: DNAT to caddy-ingress K8s NodePorts
            iifname "eth0" tcp dport 80 dnat to ${hostIP}:30080
            iifname "eth0" tcp dport 443 dnat to ${hostIP}:30443
          }
        '';
      };
    };
  };
}
