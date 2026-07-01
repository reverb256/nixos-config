{lib, ...}: {
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

    # DNAT host ports 80/443 -> K8s caddy-ingress NodePorts (30080/30443)
    # Ensures VIP traffic reaches the ingress controller pods
    nat = {
      enable = true;
      externalInterface = "eth0";
      internalInterfaces = [ "kube-bridge" ];
      # nftables-native DNAT (replaces old iptables extraCommands)
      forwardPorts = [
        {
          sourcePort = 80;
          destination = "10.1.1.120:30080";
          proto = "tcp";
        }
        {
          sourcePort = 443;
          destination = "10.1.1.120:30443";
          proto = "tcp";
        }
      ];
    };
  };
}
