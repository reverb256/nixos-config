{lib, ...}: {
  networking = {
    firewall = {
      extraInputRules = lib.mkAfter ''
        # Nix binary cache (nix-cache-proxy + nix-serve-ng)
        tcp dport { 50000 } accept
        # K3s server ports — restricted to cluster nodes only
        ip saddr { 10.1.1.110, 10.1.1.120, 10.1.1.130, 10.1.1.140 } tcp dport { 6443, 2379, 2380, 10250 } accept
        # Quill OCI registry (nexus:5000)
        tcp dport { 5000 } accept
        # General services
        tcp dport { 80, 443, 3000, 6333, 6334, 8040, 8080, 8642, 8643, 8650, 8787, 9100, 9101, 9102, 9400 } accept
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
    # memlawb encrypted memory MCP server (user systemd service) —
    # reachable ONLY over the Tailscale mesh, never the LAN.
    # The merged tailscale0 allowlist (6443 etc. from cluster-networking
    # + monitoring) did not include 8090, so the memory backend was dead
    # from every host except nexus itself. #2026-08-10.
    firewall.interfaces."tailscale0".allowedTCPPorts = lib.mkAfter [8090];
  };
}
